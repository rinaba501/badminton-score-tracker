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

    // MARK: - Participants

    /// StatsView semantics: every name that appears in history (including
    /// empty strings), first-seen order, with `mainPlayer` hoisted to the
    /// front when present.
    public static func allPlayers(history: [MatchRecord], hoisting mainPlayer: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for record in history {
            for name in [record.myName, record.opponentName] {
                if seen.insert(name).inserted { result.append(name) }
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
            for name in [record.myName, record.opponentName] where !name.isEmpty {
                if seen.insert(name).inserted { result.append(name) }
            }
        }
        return result
    }

    /// Records that involve `player` on either side (by name).
    public static func playerHistory(_ history: [MatchRecord], player: String) -> [MatchRecord] {
        history.filter { $0.myName == player || $0.opponentName == player }
    }

    /// Distinct opponents of `player` across their records, first-seen order.
    public static func opponents(of player: String, playerHistory: [MatchRecord]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for record in playerHistory {
            let opp = record.myName == player ? record.opponentName : record.myName
            if seen.insert(opp).inserted { result.append(opp) }
        }
        return result
    }

    // MARK: - Head-to-head

    /// StatsView semantics: filters `player`'s records to those against
    /// `opponent` (matching by names or by roster player ids), counts wins
    /// as `winner == player`. Returns (0, 0) when nothing matches.
    public static func headToHead(player: String, opponent: String,
                                  history: [MatchRecord], roster: [Player]) -> (wins: Int, losses: Int) {
        let mePlayer = roster.first(where: { $0.name == player })
        let oppPlayer = roster.first(where: { $0.name == opponent })
        let relevant = playerHistory(history, player: player).filter { record in
            let namesMatch = (record.myName == player && record.opponentName == opponent) ||
                             (record.myName == opponent && record.opponentName == player)
            let idsMatch: Bool = {
                guard let meId = mePlayer?.id, let oppId = oppPlayer?.id else { return false }
                return (record.myPlayerId == meId && record.opponentPlayerId == oppId) ||
                       (record.myPlayerId == oppId && record.opponentPlayerId == meId)
            }()
            return namesMatch || idsMatch
        }
        let wins = relevant.filter { $0.winner == player }.count
        return (wins: wins, losses: relevant.count - wins)
    }

    /// PreMatchView semantics: filters the FULL history (not pre-sliced),
    /// returns nil when there are no relevant matches, and counts a win only
    /// when the record's near side is `me` (by name or roster id) and the
    /// winner is `me`.
    public static func headToHeadIfAny(me: String, opponent: String,
                                       history: [MatchRecord], roster: [Player]) -> (wins: Int, losses: Int)? {
        let mePlayer = roster.first(where: { $0.name == me })
        let oppPlayer = roster.first(where: { $0.name == opponent })
        let relevant = history.filter { record in
            let namesMatch = (record.myName == me && record.opponentName == opponent) ||
                             (record.myName == opponent && record.opponentName == me)
            let idsMatch: Bool = {
                guard let meId = mePlayer?.id, let oppId = oppPlayer?.id else { return false }
                return (record.myPlayerId == meId && record.opponentPlayerId == oppId) ||
                       (record.myPlayerId == oppId && record.opponentPlayerId == meId)
            }()
            return namesMatch || idsMatch
        }
        guard !relevant.isEmpty else { return nil }
        let wins = relevant.filter { record in
            (record.myName == me || record.myPlayerId == mePlayer?.id) && record.winner == me
        }.count
        return (wins: wins, losses: relevant.count - wins)
    }

    // MARK: - Aggregates

    public static func wins(player: String, playerHistory: [MatchRecord]) -> Int {
        playerHistory.filter { $0.winner == player }.count
    }

    /// Win percentage 0–100; 0 when there are no matches.
    public static func winRate(player: String, playerHistory: [MatchRecord]) -> Double {
        playerHistory.isEmpty ? 0 : Double(wins(player: player, playerHistory: playerHistory)) / Double(playerHistory.count) * 100
    }

    /// Average points scored per *game*, from the player's side of each record.
    public static func avgPointsScored(player: String, playerHistory: [MatchRecord]) -> Double {
        guard !playerHistory.isEmpty else { return 0 }
        let total = playerHistory.flatMap { record -> [Int] in
            record.myName == player ? record.games.map { $0.my } : record.games.map { $0.opponent }
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
            if record.winner == player {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    // MARK: - History filtering & formatting

    /// HistoryView semantics: newest first (reversed stored order), keeping
    /// records that involve `selectedPlayer` ("" = all players) and are on or
    /// after `cutoff` (nil = all time). Computing the cutoff date from a UI
    /// range selection stays in the view.
    public static func filteredHistory(_ history: [MatchRecord],
                                       selectedPlayer: String, cutoff: Date?) -> [MatchRecord] {
        history.reversed().filter { record in
            let playerMatch = selectedPlayer.isEmpty ||
                record.myName == selectedPlayer || record.opponentName == selectedPlayer
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
