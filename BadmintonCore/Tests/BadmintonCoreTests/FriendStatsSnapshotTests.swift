//
//  FriendStatsSnapshotTests.swift
//  BadmintonCoreTests
//
//  Friends can share derived stats without full history (see
//  FriendStatsSnapshot.swift): compute() correctness + local-cache codec
//  round-trips.
//

import Foundation
import Testing
@testable import BadmintonCore

struct FriendStatsSnapshotTests {

    private func makeMatch(myName: String, opponentName: String, winner: RecordSide, offset: TimeInterval) -> MatchRecord {
        MatchRecord(games: [GameScore(my: 21, opponent: 15)], myGamesWon: 1, opponentGamesWon: 0,
                    winner: winner, myName: myName, opponentName: opponentName,
                    date: Date(timeIntervalSinceReferenceDate: offset))
    }

    @Test func computeDerivesWinRateWinsAndStreak() {
        let history = [
            makeMatch(myName: "Alice", opponentName: "Bob", winner: .near, offset: 0),
            makeMatch(myName: "Alice", opponentName: "Bob", winner: .near, offset: 1),
            makeMatch(myName: "Alice", opponentName: "Carol", winner: .far, offset: 2)
        ]
        let snapshot = FriendStatsSnapshot.compute(
            participantId: "alice-id", displayName: "Alice", history: history, roster: []
        )
        #expect(snapshot.gamesPlayed == 3)
        #expect(snapshot.wins == 2)
        #expect(abs(snapshot.winRate - 200.0 / 3.0) < 0.0001)
        #expect(snapshot.longestStreak == 2)
        #expect(snapshot.headToHead["Bob"] == .init(wins: 2, losses: 0))
        #expect(snapshot.headToHead["Carol"] == .init(wins: 0, losses: 1))
    }

    @Test func computeOnEmptyHistoryReturnsZeroedSnapshot() {
        let snapshot = FriendStatsSnapshot.compute(
            participantId: "alice-id", displayName: "Alice", history: [], roster: []
        )
        #expect(snapshot.gamesPlayed == 0)
        #expect(snapshot.wins == 0)
        #expect(snapshot.winRate == 0)
        #expect(snapshot.longestStreak == 0)
        #expect(snapshot.headToHead.isEmpty)
    }

    @Test func encodeDecodeRoundTripsAFriendStatsList() throws {
        let snapshots = [
            FriendStatsSnapshot(participantId: "alice-id", displayName: "Alice", gamesPlayed: 3, wins: 2,
                                winRate: 66.6, longestStreak: 2, headToHead: ["Bob": .init(wins: 2, losses: 0)]),
            FriendStatsSnapshot(participantId: "bob-id", displayName: "Bob", gamesPlayed: 0, wins: 0,
                                winRate: 0, longestStreak: 0)
        ]
        let encoded = try #require(PersistenceStore.encodeFriendStats(snapshots))
        #expect(PersistenceStore.decodeFriendStats(encoded) == snapshots)
    }

    @Test func decodeFriendStatsReturnsEmptyArrayOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeFriendStats(Data()).isEmpty)
        #expect(PersistenceStore.decodeFriendStats(Data("not json".utf8)).isEmpty)
    }

    @Test func idIsDerivedFromParticipantId() {
        let snapshot = FriendStatsSnapshot(participantId: "friend-42", displayName: "X", gamesPlayed: 0, wins: 0,
                                           winRate: 0, longestStreak: 0)
        #expect(snapshot.id == "friend-42")
    }
}
