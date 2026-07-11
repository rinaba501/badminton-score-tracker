//
//  SettingsSnapshotTests.swift
//  BadmintonCoreTests
//
//  CloudKit-only sync: SettingsSnapshot codec round-trips.
//

import Foundation
import Testing
@testable import BadmintonCore

struct SettingsSnapshotTests {

    private func makeSnapshot(
        myName: String = "Alex",
        localPlayerId: String = UUID().uuidString,
        pointsToWin: Int = 21,
        gamesInMatch: Int = 3,
        courtTheme: String = "Green",
        announceScore: Bool = true,
        enableSounds: Bool = true,
        enableCrownScoring: Bool = true,
        timeModeEnabled: Bool = false,
        timeLimitMinutes: Int = 10,
        myFriendsDisplayName: String = "Alex",
        clubLastViewedActivity: [String: Date] = [:],
        accountLinked: Bool = false
    ) -> SettingsSnapshot {
        SettingsSnapshot(
            myName: myName, localPlayerId: localPlayerId,
            pointsToWin: pointsToWin, gamesInMatch: gamesInMatch,
            courtTheme: courtTheme, announceScore: announceScore,
            enableSounds: enableSounds, enableCrownScoring: enableCrownScoring,
            timeModeEnabled: timeModeEnabled, timeLimitMinutes: timeLimitMinutes,
            myFriendsDisplayName: myFriendsDisplayName,
            clubLastViewedActivity: clubLastViewedActivity,
            accountLinked: accountLinked
        )
    }

    @Test func encodeDecodeRoundTripsASettingsSnapshot() throws {
        let snapshot = makeSnapshot()
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded == snapshot)
    }

    @Test func emptyLocalPlayerIdRoundTrips() throws {
        let snapshot = makeSnapshot(localPlayerId: "")
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded.localPlayerId == "")
    }

    @Test func accountLinkedRoundTrips() throws {
        let snapshot = makeSnapshot(accountLinked: true)
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded.accountLinked == true)
    }

    @Test func decodeSettingsSnapshotReturnsNilOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeSettingsSnapshot(Data()) == nil)
        #expect(PersistenceStore.decodeSettingsSnapshot(Data("not json".utf8)) == nil)
    }

    @Test func clubLastViewedActivityRoundTripsExactly() throws {
        var dates: [String: Date] = [:]
        dates[UUID().uuidString] = Date(timeIntervalSince1970: 1_700_000_000)
        dates[UUID().uuidString] = Date(timeIntervalSince1970: 1_700_500_000.5)
        let snapshot = makeSnapshot(myFriendsDisplayName: "Al", clubLastViewedActivity: dates)
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded == snapshot)
        #expect(decoded.clubLastViewedActivity == dates)
    }

    // A Settings payload written before myFriendsDisplayName /
    // clubLastViewedActivity / accountLinked existed must still decode,
    // defaulting the new fields — the whole point of the custom
    // decodeIfPresent init.
    @Test func decodesPreMigrationPayloadWithoutNewFields() throws {
        let legacyJSON = """
        {"schemaVersion":1,"records":[{\
        "myName":"Sam","localPlayerId":"","pointsToWin":15,"gamesInMatch":1,\
        "courtTheme":"Blue","announceScore":false,"enableSounds":true,\
        "enableCrownScoring":false,"timeModeEnabled":true,"timeLimitMinutes":20}]}
        """
        let decoded = try #require(
            PersistenceStore.decodeSettingsSnapshot(Data(legacyJSON.utf8))
        )
        #expect(decoded.myName == "Sam")
        #expect(decoded.pointsToWin == 15)
        #expect(decoded.myFriendsDisplayName == "")
        #expect(decoded.clubLastViewedActivity == [:])
        #expect(decoded.accountLinked == false)
    }
}
