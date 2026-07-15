//
//  FriendStatsSnapshot.swift
//  BadmintonCore
//
//  A friend's shared *aggregate* stats — win rate, games played, head-to-head
//  — mirrored into the same "FriendsHistory" CKShare zone FriendHistorySnapshot
//  uses (see CloudKitSyncManager's ensureFriendsHistoryShareExists/
//  syncFriendsHistoryParticipants), gated by SettingsSnapshot.shareStatsWithFriends.
//  Deliberately a precomputed/derived snapshot rather than raw match records,
//  so a person can share their win-rate without exposing full match-by-match
//  history (that's the separate shareHistoryWithFriends toggle). Built via
//  StatsCalculator over the owner's own personal (clubId == nil) history —
//  uses headToHead(player:opponent:history:roster:) specifically (StatsView's
//  "standings" semantics), not headToHeadIfAny, per StatsCalculator's own
//  doc-comment about not unifying its two head-to-head variants.
//
//  Deliberately kept in its own local cache (AppStore.friendStats) rather than
//  merged into the viewer's own stats — read-only, someone else's data, same
//  convention as FriendHistorySnapshot/AppStore.friendActivity.
//

import Foundation

public struct FriendStatsSnapshot: Identifiable, Codable, Equatable {
    public struct HeadToHeadStat: Codable, Equatable {
        public var wins: Int
        public var losses: Int

        public init(wins: Int, losses: Int) {
            self.wins = wins
            self.losses = losses
        }
    }

    public var id: String { participantId }
    public let participantId: String
    public var displayName: String
    public var gamesPlayed: Int
    public var wins: Int
    public var winRate: Double
    public var longestStreak: Int
    public var headToHead: [String: HeadToHeadStat]

    public init(
        participantId: String,
        displayName: String,
        gamesPlayed: Int,
        wins: Int,
        winRate: Double,
        longestStreak: Int,
        headToHead: [String: HeadToHeadStat] = [:]
    ) {
        self.participantId = participantId
        self.displayName = displayName
        self.gamesPlayed = gamesPlayed
        self.wins = wins
        self.winRate = winRate
        self.longestStreak = longestStreak
        self.headToHead = headToHead
    }

    /// Builds a snapshot from the owner's own personal history — `history`
    /// and `roster` should already be scoped to clubId == nil, matching the
    /// scope shareHistoryWithFriends mirrors.
    public static func compute(
        participantId: String,
        displayName: String,
        history: [MatchRecord],
        roster: [Player]
    ) -> FriendStatsSnapshot {
        let playerHistory = StatsCalculator.playerHistory(history, player: displayName)
        let opponents = StatsCalculator.opponents(of: displayName, playerHistory: playerHistory)
        var headToHead: [String: HeadToHeadStat] = [:]
        for opponent in opponents {
            let record = StatsCalculator.headToHead(player: displayName, opponent: opponent, history: history, roster: roster)
            headToHead[opponent] = HeadToHeadStat(wins: record.wins, losses: record.losses)
        }
        return FriendStatsSnapshot(
            participantId: participantId,
            displayName: displayName,
            gamesPlayed: playerHistory.count,
            wins: StatsCalculator.wins(player: displayName, playerHistory: playerHistory),
            winRate: StatsCalculator.winRate(player: displayName, playerHistory: playerHistory),
            longestStreak: StatsCalculator.longestStreak(player: displayName, playerHistory: playerHistory),
            headToHead: headToHead
        )
    }
}
