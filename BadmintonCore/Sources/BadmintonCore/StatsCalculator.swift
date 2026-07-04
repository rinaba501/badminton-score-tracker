//
//  StatsCalculator.swift
//  BadmintonCore
//
//  Pure derivations over match history, extracted as-is from StatsView,
//  HistoryView, and PreMatchView. The two "all players" functions and the
//  two head-to-head functions intentionally differ — each preserves its
//  original view's semantics and must not be unified without a product
//  decision.
//

import Foundation

public enum StatsCalculator {

    // MARK: - Team membership

    /// A "team" is one or two names: `myName` alone for singles, plus
    /// `myPartnerName` when the record is doubles. Every function below
    /// reasons about team membership through these helpers instead of
    /// comparing `record.myName`/`record.opponentName` directly, so singles
    /// (where a team degenerates to exactly one name) and doubles share the
    /// same logic.
    private static func nearTeamNames(_ record: MatchRecord) -> [String] {
        [record.myName, record.myPartnerName].compactMap { $0 }
    }
    private static func farTeamNames(_ record: MatchRecord) -> [String] {
        [record.opponentName, record.opponentPartnerName].compactMap { $0 }
    }
    private static func nearTeamIds(_ record: MatchRecord) -> [UUID] {
        [record.myPlayerId, record.myPartnerPlayerId].compactMap { $0 }
    }
    private static func farTeamIds(_ record: MatchRecord) -> [UUID] {
        [record.opponentPlayerId, record.opponentPartnerPlayerId].compactMap { $0 }
    }
    private static func idMatches(_ ids: [UUID], _ id: UUID?) -> Bool {
        guard let id else { return false }
        return ids.contains(id)
    }

    /// True when `player`'s team won `record`. `winner` is always equal to
    /// either `record.myName` or `record.opponentName` (the team's
    /// representative name — see `MatchModel.swift`), so this works without
    /// needing `winner` to know about doubles partners directly.
    private static func teamWon(_ record: MatchRecord, player: String) -> Bool {
        if nearTeamNames(record).contains(player) { return record.winner == record.myName }
        if farTeamNames(record).contains(player) { return record.winner == record.opponentName }
        return false
    }

    // MARK: - Participants

    /// StatsView semantics: every name that appears in history (including
    /// empty strings), first-seen order, with `mainPlayer` hoisted to the
    /// front when present.
    public static func allPlayers(history: [MatchRecord], hoisting mainPlayer: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for record in history {
            for name in nearTeamNames(record) + farTeamNames(record) where seen.insert(name).inserted {
                result.append(name)
            }
        }
        // Always show the main player first
        if let idx = result.firstIndex(of: mainPlayer), idx != 0 {
            result.remove(at: idx)
            result.insert(mainPlayer, at: 0)
        }
        return result
    }

    /// HistoryView semantics: non-empty names only, first-seen order,
    /// no hoisting.
    public static func participants(history: [MatchRecord]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for record in history {
            for name in nearTeamNames(record) + farTeamNames(record) where !name.isEmpty {
                if seen.insert(name).inserted { result.append(name) }
            }
        }
        return result
    }

    /// Records that involve `player` on either team (by name).
    public static func playerHistory(_ history: [MatchRecord], player: String) -> [MatchRecord] {
        history.filter { nearTeamNames($0).contains(player) || farTeamNames($0).contains(player) }
    }

    /// Distinct opponents of `player` across their records, first-seen order.
    /// In doubles this is the other team's *both* members — a teammate is
    /// never counted as an opponent.
    public static func opponents(of player: String, playerHistory: [MatchRecord]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for record in playerHistory {
            let onNearTeam = nearTeamNames(record).contains(player)
            let oppTeam = onNearTeam ? farTeamNames(record) : nearTeamNames(record)
            for opp in oppTeam where seen.insert(opp).inserted {
                result.append(opp)
            }
        }
        return result
    }

    // MARK: - Head-to-head

    /// True when `record` is a matchup between `a` and `b` — one on each
    /// team — matching either by stored display names or by the two roster
    /// players' ids. The single home of the matchup contract shared by both
    /// head-to-head functions below.
    private static func isMatchup(_ record: MatchRecord, _ a: String, _ b: String,
                                  aPlayer: Player?, bPlayer: Player?) -> Bool {
        let near = nearTeamNames(record)
        let far = farTeamNames(record)
        let namesMatch = (near.contains(a) && far.contains(b)) || (near.contains(b) && far.contains(a))
        let idsMatch: Bool = {
            guard let aId = aPlayer?.id, let bId = bPlayer?.id else { return false }
            let nearIds = nearTeamIds(record)
            let farIds = farTeamIds(record)
            return (nearIds.contains(aId) && farIds.contains(bId)) || (nearIds.contains(bId) && farIds.contains(aId))
        }()
        return namesMatch || idsMatch
    }

    /// StatsView semantics: filters `player`'s records to those against
    /// `opponent` (matching by names or by roster player ids), counts wins
    /// via team membership. Returns (0, 0) when nothing matches.
    public static func headToHead(player: String, opponent: String,
                                  history: [MatchRecord], roster: [Player]) -> (wins: Int, losses: Int) {
        let mePlayer = roster.first(where: { $0.name == player })
        let oppPlayer = roster.first(where: { $0.name == opponent })
        let relevant = playerHistory(history, player: player).filter {
            isMatchup($0, player, opponent, aPlayer: mePlayer, bPlayer: oppPlayer)
        }
        let wins = relevant.filter { teamWon($0, player: player) }.count
        return (wins: wins, losses: relevant.count - wins)
    }

    /// PreMatchView semantics: filters the FULL history (not pre-sliced),
    /// returns nil when there are no relevant matches, and counts a win only
    /// when the record's near TEAM includes `me` (by name or roster id) and
    /// that team won.
    public static func headToHeadIfAny(me: String, opponent: String,
                                       history: [MatchRecord], roster: [Player]) -> (wins: Int, losses: Int)? {
        let mePlayer = roster.first(where: { $0.name == me })
        let oppPlayer = roster.first(where: { $0.name == opponent })
        let relevant = history.filter {
            isMatchup($0, me, opponent, aPlayer: mePlayer, bPlayer: oppPlayer)
        }
        guard !relevant.isEmpty else { return nil }
        let wins = relevant.filter { record in
            let onNearTeam = nearTeamNames(record).contains(me) || idMatches(nearTeamIds(record), mePlayer?.id)
            return onNearTeam && record.winner == record.myName
        }.count
        return (wins: wins, losses: relevant.count - wins)
    }

    // MARK: - Aggregates

    public static func wins(player: String, playerHistory: [MatchRecord]) -> Int {
        playerHistory.filter { teamWon($0, player: player) }.count
    }

    /// Win percentage 0–100; 0 when there are no matches.
    public static func winRate(player: String, playerHistory: [MatchRecord]) -> Double {
        playerHistory.isEmpty ? 0 : Double(wins(player: player, playerHistory: playerHistory)) / Double(playerHistory.count) * 100
    }

    /// Average points scored per *game*, from the player's team's side of
    /// each record. Both partners on a doubles team share the same score,
    /// so this is correct regardless of which partner `player` is.
    public static func avgPointsScored(player: String, playerHistory: [MatchRecord]) -> Double {
        guard !playerHistory.isEmpty else { return 0 }
        let total = playerHistory.flatMap { record -> [Int] in
            nearTeamNames(record).contains(player) ? record.games.map { $0.my } : record.games.map { $0.opponent }
        }.reduce(0, +)
        let games = playerHistory.flatMap { $0.games }.count
        return games == 0 ? 0 : Double(total) / Double(games)
    }

    /// Mean duration of the records that carry one (duration > 0); 0 otherwise.
    public static func avgMatchDuration(playerHistory: [MatchRecord]) -> TimeInterval {
        let timed = playerHistory.filter { $0.duration > 0 }
        guard !timed.isEmpty else { return 0 }
        return timed.map { $0.duration }.reduce(0, +) / Double(timed.count)
    }

    /// Longest run of consecutive wins, scanning records in stored order.
    public static func longestStreak(player: String, playerHistory: [MatchRecord]) -> Int {
        var best = 0
        var current = 0
        for record in playerHistory {
            if teamWon(record, player: player) {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    // MARK: - History filtering & formatting

    /// HistoryView semantics: newest first by default (reversed stored
    /// order), or oldest first (stored order) when `newestFirst` is false;
    /// keeping records that involve `selectedPlayer` ("" = all players) on
    /// either team, and are on or after `cutoff` (nil = all time). Computing
    /// the cutoff date from a UI range selection stays in the view.
    public static func filteredHistory(_ history: [MatchRecord], selectedPlayer: String,
                                       cutoff: Date?, newestFirst: Bool = true) -> [MatchRecord] {
        let ordered = newestFirst ? Array(history.reversed()) : history
        return ordered.filter { record in
            let playerMatch = selectedPlayer.isEmpty ||
                nearTeamNames(record).contains(selectedPlayer) || farTeamNames(record).contains(selectedPlayer)
            let dateMatch = cutoff.map { record.date >= $0 } ?? true
            return playerMatch && dateMatch
        }
    }

    /// "3m 42s" when at least a minute, else "42s".
    public static func durationString(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}
