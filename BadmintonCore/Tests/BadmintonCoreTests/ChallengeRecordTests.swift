//
//  ChallengeRecordTests.swift
//  BadmintonCoreTests
//
//  Roadmap Phase 5 backlog (#162): ChallengeRecord codec round-trips.
//

import Foundation
import Testing
@testable import BadmintonCore

struct ChallengeRecordTests {

    @Test func encodeDecodeRoundTripsAChallengeList() throws {
        let challenges = [
            ChallengeRecord(
                clubId: UUID(), fromParticipantId: "alice-id", fromDisplayName: "Alice",
                toParticipantId: "bob-id", toDisplayName: "Bob",
                createdDate: Date(timeIntervalSince1970: 1_000)
            ),
            ChallengeRecord(
                clubId: UUID(), fromParticipantId: "carol-id", fromDisplayName: "Carol",
                toParticipantId: "dave-id", toDisplayName: "Dave", status: .accepted,
                createdDate: Date(timeIntervalSince1970: 2_000)
            )
        ]
        let encoded = try #require(PersistenceStore.encodeChallenges(challenges))
        #expect(PersistenceStore.decodeChallenges(encoded) == challenges)
    }

    @Test func decodeChallengesReturnsEmptyArrayOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeChallenges(Data()).isEmpty)
        #expect(PersistenceStore.decodeChallenges(Data("not json".utf8)).isEmpty)
    }

    @Test func singleChallengeEncodeDecodeRoundTrip() throws {
        let challenge = ChallengeRecord(
            clubId: UUID(), fromParticipantId: "alice-id", fromDisplayName: "Alice",
            toParticipantId: "bob-id", toDisplayName: "Bob"
        )
        let encoded = try #require(PersistenceStore.encodeChallenge(challenge))
        let decoded = try #require(PersistenceStore.decodeChallenge(encoded))
        #expect(decoded == challenge)
    }

    @Test func statusRoundTripsThroughAllCases() throws {
        for status: ChallengeRecord.Status in [.pending, .accepted, .declined] {
            var challenge = ChallengeRecord(
                clubId: UUID(), fromParticipantId: "alice-id", fromDisplayName: "Alice",
                toParticipantId: "bob-id", toDisplayName: "Bob"
            )
            challenge.status = status
            let encoded = try #require(PersistenceStore.encodeChallenge(challenge))
            let decoded = try #require(PersistenceStore.decodeChallenge(encoded))
            #expect(decoded.status == status)
        }
    }

    @Test func diffChallengesReportsUpsertsAndDeletes() {
        let clubId = UUID()
        let unchanged = ChallengeRecord(
            id: UUID(), clubId: clubId, fromParticipantId: "a", fromDisplayName: "Alice",
            toParticipantId: "b", toDisplayName: "Bob"
        )
        let toRemove = ChallengeRecord(
            id: UUID(), clubId: clubId, fromParticipantId: "c", fromDisplayName: "Carol",
            toParticipantId: "d", toDisplayName: "Dave"
        )
        var accepted = unchanged
        accepted.status = .accepted
        let added = ChallengeRecord(
            id: UUID(), clubId: clubId, fromParticipantId: "e", fromDisplayName: "Eve",
            toParticipantId: "f", toDisplayName: "Frank"
        )

        let diff = PersistenceStore.diffChallenges(from: [unchanged, toRemove], to: [accepted, added])
        #expect(Set(diff.upsertedIds) == Set([accepted.id, added.id]))
        #expect(diff.deletedIds == [toRemove.id])
    }
}
