//
//  FriendProfileTests.swift
//  BadmintonCoreTests
//
//  Friends v1 (graph-only): FriendProfile codec round-trips.
//

import Foundation
import Testing
@testable import BadmintonCore

struct FriendProfileTests {

    @Test func singleFriendProfileEncodeDecodeRoundTrip() throws {
        let profile = FriendProfile(
            participantId: "alice-id", displayName: "Alice",
            createdDate: Date(timeIntervalSince1970: 1_000)
        )
        let encoded = try #require(PersistenceStore.encodeFriendProfile(profile))
        let decoded = try #require(PersistenceStore.decodeFriendProfile(encoded))
        #expect(decoded == profile)
    }

    @Test func decodeFriendProfileReturnsNilOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeFriendProfile(Data()) == nil)
        #expect(PersistenceStore.decodeFriendProfile(Data("not json".utf8)) == nil)
    }

    @Test func unicodeDisplayNameRoundTripsIntact() throws {
        for name in ["田中", "José", "😀 Player"] {
            let profile = FriendProfile(participantId: "id", displayName: name)
            let encoded = try #require(PersistenceStore.encodeFriendProfile(profile))
            let decoded = try #require(PersistenceStore.decodeFriendProfile(encoded))
            #expect(decoded.displayName == name)
        }
    }
}
