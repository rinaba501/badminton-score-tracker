//
//  FriendHistorySnapshotTests.swift
//  BadmintonCoreTests
//
//  Friends can share their history (see FriendHistorySnapshot.swift):
//  local-cache codec round-trips.
//

import Foundation
import Testing
@testable import BadmintonCore

struct FriendHistorySnapshotTests {

    private func makePlayer(name: String = "Alice") -> Player {
        Player(id: UUID(), name: name, colorIndex: 0)
    }

    private func makeMatch(myName: String = "Alice", opponentName: String = "Bob") -> MatchRecord {
        MatchRecord(games: [GameScore(my: 21, opponent: 15)], myGamesWon: 1, opponentGamesWon: 0,
                    winner: .near, myName: myName, opponentName: opponentName,
                    date: Date(timeIntervalSinceReferenceDate: 0))
    }

    private func makeSnapshot(
        participantId: String = "friend-id",
        displayName: String = "Alice",
        roster: [Player] = [],
        history: [MatchRecord] = []
    ) -> FriendHistorySnapshot {
        FriendHistorySnapshot(participantId: participantId, displayName: displayName, roster: roster, history: history)
    }

    @Test func encodeDecodeRoundTripsAFriendActivityList() throws {
        let snapshots = [
            makeSnapshot(participantId: "alice-id", displayName: "Alice", roster: [makePlayer()], history: [makeMatch()]),
            makeSnapshot(participantId: "bob-id", displayName: "Bob")
        ]
        let encoded = try #require(PersistenceStore.encodeFriendActivity(snapshots))
        #expect(PersistenceStore.decodeFriendActivity(encoded) == snapshots)
    }

    @Test func decodeFriendActivityReturnsEmptyArrayOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeFriendActivity(Data()).isEmpty)
        #expect(PersistenceStore.decodeFriendActivity(Data("not json".utf8)).isEmpty)
    }

    @Test func idIsDerivedFromParticipantId() {
        let snapshot = makeSnapshot(participantId: "friend-42")
        #expect(snapshot.id == "friend-42")
    }

    @Test func aCorruptElementDoesNotDropItsSiblings() {
        let good = makeSnapshot(participantId: "good-id", displayName: "Good")
        let json = """
        {"schemaVersion":1,"records":[\
        {"participantId":"good-id","displayName":"Good","roster":[],"history":[]},\
        {"participantId":123}\
        ]}
        """
        let decoded = PersistenceStore.decodeFriendActivity(Data(json.utf8))
        #expect(decoded == [good])
    }
}
