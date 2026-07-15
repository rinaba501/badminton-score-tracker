//
//  FriendIdentitySnapshotTests.swift
//  BadmintonCoreTests
//
//  Friends can share per-field profile identity (see FriendIdentitySnapshot.swift):
//  local-cache codec round-trips.
//

import Foundation
import Testing
@testable import BadmintonCore

struct FriendIdentitySnapshotTests {

    private func makeSnapshot(
        participantId: String = "friend-id",
        displayName: String = "Alice",
        colorIndex: Int? = nil,
        iconName: String? = nil,
        gender: String? = nil,
        birthday: Date? = nil,
        introduction: String? = nil
    ) -> FriendIdentitySnapshot {
        FriendIdentitySnapshot(
            participantId: participantId, displayName: displayName,
            colorIndex: colorIndex, iconName: iconName,
            gender: gender, birthday: birthday, introduction: introduction
        )
    }

    @Test func encodeDecodeRoundTripsAFriendIdentityList() throws {
        let snapshots = [
            makeSnapshot(participantId: "alice-id", displayName: "Alice", colorIndex: 2, iconName: "bird",
                         gender: "female", birthday: Date(timeIntervalSince1970: 600_000_000), introduction: "Hi!"),
            makeSnapshot(participantId: "bob-id", displayName: "Bob")
        ]
        let encoded = try #require(PersistenceStore.encodeFriendIdentities(snapshots))
        #expect(PersistenceStore.decodeFriendIdentities(encoded) == snapshots)
    }

    @Test func decodeFriendIdentitiesReturnsEmptyArrayOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeFriendIdentities(Data()).isEmpty)
        #expect(PersistenceStore.decodeFriendIdentities(Data("not json".utf8)).isEmpty)
    }

    @Test func idIsDerivedFromParticipantId() {
        let snapshot = makeSnapshot(participantId: "friend-42")
        #expect(snapshot.id == "friend-42")
    }

    @Test func everyFieldButDisplayNameIsIndependentlyNilable() {
        let onlyGender = makeSnapshot(gender: "male")
        #expect(onlyGender.colorIndex == nil)
        #expect(onlyGender.iconName == nil)
        #expect(onlyGender.gender == "male")
        #expect(onlyGender.birthday == nil)
        #expect(onlyGender.introduction == nil)
    }
}
