//
//  FriendRequestTests.swift
//  BadmintonCoreTests
//
//  Friends v1 (graph-only): FriendRequest codec round-trips.
//

import Foundation
import Testing
@testable import BadmintonCore

struct FriendRequestTests {

    @Test func encodeDecodeRoundTripsAFriendRequestList() throws {
        let requests = [
            FriendRequest(
                fromParticipantId: "alice-id", fromDisplayName: "Alice",
                toParticipantId: "bob-id", toDisplayName: "Bob",
                createdDate: Date(timeIntervalSince1970: 1_000)
            ),
            FriendRequest(
                fromParticipantId: "carol-id", fromDisplayName: "Carol",
                toParticipantId: "dave-id", toDisplayName: "Dave", status: .accepted,
                createdDate: Date(timeIntervalSince1970: 2_000)
            )
        ]
        let encoded = try #require(PersistenceStore.encodeFriendRequests(requests))
        #expect(PersistenceStore.decodeFriendRequests(encoded) == requests)
    }

    @Test func decodeFriendRequestsReturnsEmptyArrayOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeFriendRequests(Data()).isEmpty)
        #expect(PersistenceStore.decodeFriendRequests(Data("not json".utf8)).isEmpty)
    }

    @Test func singleFriendRequestEncodeDecodeRoundTrip() throws {
        let request = FriendRequest(
            fromParticipantId: "alice-id", fromDisplayName: "Alice",
            toParticipantId: "bob-id", toDisplayName: "Bob"
        )
        let encoded = try #require(PersistenceStore.encodeFriendRequest(request))
        let decoded = try #require(PersistenceStore.decodeFriendRequest(encoded))
        #expect(decoded == request)
    }

    @Test func statusRoundTripsThroughAllCases() throws {
        for status: FriendRequest.Status in [.pending, .accepted, .declined] {
            var request = FriendRequest(
                fromParticipantId: "alice-id", fromDisplayName: "Alice",
                toParticipantId: "bob-id", toDisplayName: "Bob"
            )
            request.status = status
            let encoded = try #require(PersistenceStore.encodeFriendRequest(request))
            let decoded = try #require(PersistenceStore.decodeFriendRequest(encoded))
            #expect(decoded.status == status)
        }
    }

    @Test func diffFriendRequestsReportsUpsertsAndDeletes() {
        let unchanged = FriendRequest(
            id: UUID(), fromParticipantId: "a", fromDisplayName: "Alice",
            toParticipantId: "b", toDisplayName: "Bob"
        )
        let toRemove = FriendRequest(
            id: UUID(), fromParticipantId: "c", fromDisplayName: "Carol",
            toParticipantId: "d", toDisplayName: "Dave"
        )
        var accepted = unchanged
        accepted.status = .accepted
        let added = FriendRequest(
            id: UUID(), fromParticipantId: "e", fromDisplayName: "Eve",
            toParticipantId: "f", toDisplayName: "Frank"
        )

        let diff = PersistenceStore.diffFriendRequests(from: [unchanged, toRemove], to: [accepted, added])
        #expect(Set(diff.upsertedIds) == Set([accepted.id, added.id]))
        #expect(diff.deletedIds == [toRemove.id])
    }
}
