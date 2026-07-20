//
//  MatchInviteTests.swift
//  BadmintonCoreTests
//
//  Roadmap Phase 10a: SharedMatchInvite codec round-trips.
//

import Foundation
import Testing
@testable import BadmintonCore

struct MatchInviteTests {

    private func snapshot(date: Date = Date(timeIntervalSince1970: 1_000)) -> MatchRecord {
        MatchRecord(games: [GameScore(my: 21, opponent: 15)], myGamesWon: 1, opponentGamesWon: 0,
                    winner: .near, myName: "Alex", opponentName: "Recipient", date: date, duration: 900)
    }

    @Test func encodeDecodeRoundTripsAMatchInviteList() throws {
        let a = SharedMatchInvite(
            id: UUID(), fromParticipantId: "alex-id", fromDisplayName: "Alex",
            toParticipantId: "recipient-id", createdDate: Date(timeIntervalSince1970: 1_000),
            matchSnapshot: snapshot()
        )
        let b = SharedMatchInvite(
            id: UUID(), fromParticipantId: "carol-id", fromDisplayName: "Carol",
            toParticipantId: "dave-id", status: .accepted, createdDate: Date(timeIntervalSince1970: 2_000),
            matchSnapshot: snapshot(date: Date(timeIntervalSince1970: 2_000))
        )
        let encoded = try #require(PersistenceStore.encodeMatchInvites([a, b]))
        #expect(PersistenceStore.decodeMatchInvites(encoded) == [a, b])
    }

    @Test func decodeMatchInvitesReturnsEmptyArrayOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeMatchInvites(Data()).isEmpty)
        #expect(PersistenceStore.decodeMatchInvites(Data("not json".utf8)).isEmpty)
    }

    @Test func singleMatchInviteEncodeDecodeRoundTrip() throws {
        let invite = SharedMatchInvite(
            id: UUID(), fromParticipantId: "alex-id", fromDisplayName: "Alex",
            toParticipantId: "recipient-id", matchSnapshot: snapshot()
        )
        let encoded = try #require(PersistenceStore.encodeMatchInvite(invite))
        let decoded = try #require(PersistenceStore.decodeMatchInvite(encoded))
        #expect(decoded == invite)
    }

    @Test func idIntentionallyEqualsMatchSnapshotIdByConvention() throws {
        // Not enforced by the type itself, but every real call site
        // constructs it this way (see SupabaseSyncEngine.enqueueMatchInvite)
        // so a later mirror's sourceMatchId can equal this id directly.
        let snap = snapshot()
        let invite = SharedMatchInvite(
            id: snap.id, fromParticipantId: "alex-id", fromDisplayName: "Alex",
            toParticipantId: "recipient-id", matchSnapshot: snap
        )
        #expect(invite.id == invite.matchSnapshot.id)
    }

    @Test func statusRoundTripsThroughAllCases() throws {
        for status: SharedMatchInvite.Status in [.pending, .accepted, .declined] {
            var invite = SharedMatchInvite(
                id: UUID(), fromParticipantId: "alex-id", fromDisplayName: "Alex",
                toParticipantId: "recipient-id", matchSnapshot: snapshot()
            )
            invite.status = status
            let encoded = try #require(PersistenceStore.encodeMatchInvite(invite))
            let decoded = try #require(PersistenceStore.decodeMatchInvite(encoded))
            #expect(decoded.status == status)
        }
    }

    @Test func decodeMatchInviteReturnsNilForAFriendRequestShapedPayload() throws {
        // FriendRequest has no matchSnapshot — decoding it as a
        // SharedMatchInvite must fail closed (nil), not crash.
        let request = FriendRequest(
            fromParticipantId: "alex-id", fromDisplayName: "Alex",
            toParticipantId: "recipient-id", toDisplayName: "Recipient"
        )
        let requestData = try #require(PersistenceStore.encodeFriendRequest(request))
        #expect(PersistenceStore.decodeMatchInvite(requestData) == nil)
    }
}
