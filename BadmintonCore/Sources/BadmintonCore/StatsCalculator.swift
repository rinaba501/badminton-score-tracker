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

    /// True when `player`'s team won `record`. `winner` is a viewer-neutral
    /// `RecordSide` tag (near/far — see `MatchModel.swift`), so this works
    /// without needing `winner` to know about doubles partners directly, and
    /// without depending on which team `player` actually is.
    private static func teamWon(_ record: MatchRecord, player: String) -> Bool {
        if nearTeamNames(record).contains(player) { return record.winner == .near }
        if farTeamNames(record).contains(player) { return record.winner == .far }
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
            for name in nearTeamNames(record) + farTeamNames(record)
                where !Player.isGuestName(name) && seen.insert(name).inserted {
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
            for name in nearTeamNames(record) + farTeamNames(record) where !name.isEmpty && !Player.isGuestName(name) {
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
            for opp in oppTeam where !Player.isGuestName(opp) && seen.insert(opp).inserted {
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
            return onNearTeam && record.winner == .near
        }.count
        return (wins: wins, losses: relevant.count - wins)
    }

    // MARK: - Friend match conflict detection (Phase 10a)

    /// True when `a`/`b` involve the same two participants — participant-id
    /// match (`opponentParticipantId`) takes exclusive priority when BOTH
    /// records tag one, since that's unambiguous; otherwise falls back to
    /// comparing the unordered (myName, opponentName) pair, which is valid
    /// because both `a`/`b` are always THIS device's own personal records
    /// (myName is consistently "me" across them).
    private static func sameParticipants(_ a: MatchRecord, _ b: MatchRecord) -> Bool {
        if let aOpponent = a.opponentParticipantId, let bOpponent = b.opponentParticipantId {
            return aOpponent == bOpponent
        }
        return Set([a.myName, a.opponentName]) == Set([b.myName, b.opponentName])
    }

    /// `GameScore.id` is a fresh UUID assigned per-instance and carries no
    /// meaning about whether two games have the same result — comparing
    /// `[GameScore]` arrays with `==` (which includes `id` via synthesized
    /// `Equatable`) would treat any two independently-constructed matches
    /// with identical scores as "different games". This compares only the
    /// `my`/`opponent` value pairs, which is what "same score" actually means.
    private static func sameScore(_ a: [GameScore], _ b: [GameScore]) -> Bool {
        a.map { [$0.my, $0.opponent] } == b.map { [$0.my, $0.opponent] }
    }

    /// The first record in `history` that plausibly IS `candidate` under a
    /// different score — same two participants (`sameParticipants` above),
    /// within `dateProximity` of each other, but a `games` result that
    /// differs. Returns `nil` when no record shares both participants and
    /// date, OR when one does but the score already matches exactly (an
    /// already-agreeing duplicate isn't a conflict — see
    /// `MatchInviteMirror.swift`'s doc comment on why this feature doesn't
    /// attempt to auto-dedupe two independently-logged, identically-scored
    /// records into one). Both `candidate` and every `history` record
    /// considered are restricted to personal (`clubId == nil`) singles
    /// (`!isDoubles`) matches — this feature is scoped to that slice for v1;
    /// club matches already have their own `requireMatchConfirmation` flow.
    public static func conflictingRecord(
        for candidate: MatchRecord,
        in history: [MatchRecord],
        dateProximity: TimeInterval = 86_400
    ) -> MatchRecord? {
        guard candidate.clubId == nil, !candidate.isDoubles else { return nil }
        return history.first { existing in
            existing.id != candidate.id
                && existing.clubId == nil
                && !existing.isDoubles
                && sameParticipants(candidate, existing)
                && abs(existing.date.timeIntervalSince(candidate.date)) <= dateProximity
                && !sameScore(existing.games, candidate.games)
        }
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

    /// Consecutive wins counting back from the most recent record; 0 once the
    /// most recent record is a loss (or there's no history). Complements
    /// `longestStreak` (career-best) with "am I hot right now."
    public static func currentStreak(player: String, playerHistory: [MatchRecord]) -> Int {
        var streak = 0
        for record in playerHistory.reversed() {
            guard teamWon(record, player: player) else { break }
            streak += 1
        }
        return streak
    }

    /// Count of `playerHistory` broken down by Singles vs. Doubles.
    public static func matchTypeSplit(playerHistory: [MatchRecord]) -> (singles: Int, doubles: Int) {
        let doubles = playerHistory.filter { $0.isDoubles }.count
        return (singles: playerHistory.count - doubles, doubles: doubles)
    }

    // MARK: - Standings

    /// One player's aggregate record within a given (already scoped) slice
    /// of history — e.g. a club's shared matches. Sorted output puts the
    /// best win rate first, ties broken by more wins.
    public struct StandingsEntry: Identifiable, Equatable {
        public var id: String { name }
        public let name: String
        public let wins: Int
        public let losses: Int
        public let winRate: Double

        public init(name: String, wins: Int, losses: Int, winRate: Double) {
            self.name = name
            self.wins = wins
            self.losses = losses
            self.winRate = winRate
        }
    }

    /// Standings over `history` — pass a club-scoped slice (`clubId`-filtered,
    /// same convention as HistoryView/StatsView's club switcher) to get club
    /// standings, or the full personal history for a solo leaderboard-of-one.
    /// Reuses `participants`/`playerHistory`/`wins`/`winRate` as-is, so this
    /// is purely an aggregation-and-sort layer, not new stats math.
    public static func standings(history: [MatchRecord]) -> [StandingsEntry] {
        participants(history: history).map { name in
            let ph = playerHistory(history, player: name)
            let w = wins(player: name, playerHistory: ph)
            return StandingsEntry(name: name, wins: w, losses: ph.count - w,
                                  winRate: winRate(player: name, playerHistory: ph))
        }.sorted { lhs, rhs in
            lhs.winRate != rhs.winRate ? lhs.winRate > rhs.winRate : lhs.wins > rhs.wins
        }
    }

    // MARK: - Activity feed

    /// One recorded result, shaped for a chronological club activity feed.
    public struct ActivityFeedEntry: Identifiable, Equatable {
        public let id: UUID
        public let myName: String
        public let opponentName: String
        public let myGamesWon: Int
        public let opponentGamesWon: Int
        public let winner: RecordSide
        public let date: Date
        /// Per-game point scores (e.g. 21-18, 15-21, 21-19) — same source
        /// HistoryView's gameLine formats, so an activity row can show the
        /// exact score instead of just the games-won tally.
        public let games: [GameScore]
        /// Mirrors `MatchRecord.isOfficial` — a practice match still appears
        /// in the feed (unlike Standings, which filters it out at the call
        /// site), so the row can render a "Practice" tag.
        public let isOfficial: Bool

        public init(id: UUID, myName: String, opponentName: String, myGamesWon: Int,
                    opponentGamesWon: Int, winner: RecordSide, date: Date, games: [GameScore], isOfficial: Bool) {
            self.id = id
            self.myName = myName
            self.opponentName = opponentName
            self.myGamesWon = myGamesWon
            self.opponentGamesWon = opponentGamesWon
            self.winner = winner
            self.date = date
            self.games = games
            self.isOfficial = isOfficial
        }
    }

    /// Newest-first activity feed over `history` — pass an already
    /// club-scoped, confirmation-filtered slice (same convention as
    /// `standings(history:)`). Stored order is oldest-first, matching
    /// `filteredHistory`'s `newestFirst` reversal convention.
    public static func activityFeed(history: [MatchRecord]) -> [ActivityFeedEntry] {
        history.reversed().map { record in
            ActivityFeedEntry(id: record.id, myName: record.myName, opponentName: record.opponentName,
                              myGamesWon: record.myGamesWon, opponentGamesWon: record.opponentGamesWon,
                              winner: record.winner, date: record.date, games: record.games,
                              isOfficial: record.isOfficial)
        }
    }

    // MARK: - History filtering & formatting

    /// HistoryView semantics for filtering by Singles vs. Doubles.
    public enum MatchTypeFilter: String, CaseIterable, Codable {
        case all, singles, doubles
    }

    /// HistoryView semantics: newest first by default (reversed stored
    /// order), or oldest first (stored order) when `newestFirst` is false;
    /// keeping records where every name in `selectedPlayers` participated
    /// (on either team, in any combination — empty set = no filter), are on
    /// or after `cutoff` (nil = all time), and match `matchType` (`.all` = no
    /// filtering). Computing the cutoff date from a UI range selection stays
    /// in the view.
    public static func filteredHistory(_ history: [MatchRecord], selectedPlayers: Set<String>, cutoff: Date?,
                                       newestFirst: Bool = true,
                                       matchType: MatchTypeFilter = .all) -> [MatchRecord] {
        let ordered = newestFirst ? Array(history.reversed()) : history
        return ordered.filter { record in
            let participants = Set(nearTeamNames(record) + farTeamNames(record))
            let playerMatch = selectedPlayers.isSubset(of: participants)
            let dateMatch = cutoff.map { record.date >= $0 } ?? true
            let typeMatch: Bool
            switch matchType {
            case .all:     typeMatch = true
            case .singles: typeMatch = !record.isDoubles
            case .doubles: typeMatch = record.isDoubles
            }
            return playerMatch && dateMatch && typeMatch
        }
    }

    /// "3m 42s" when at least a minute, else "42s".
    public static func durationString(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }
}
