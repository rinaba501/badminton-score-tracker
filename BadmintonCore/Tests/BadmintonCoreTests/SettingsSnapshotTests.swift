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
        timeLimitMinutes: Int = 10
    ) -> SettingsSnapshot {
        SettingsSnapshot(
            myName: myName, localPlayerId: localPlayerId,
            pointsToWin: pointsToWin, gamesInMatch: gamesInMatch,
            courtTheme: courtTheme, announceScore: announceScore,
            enableSounds: enableSounds, enableCrownScoring: enableCrownScoring,
            timeModeEnabled: timeModeEnabled, timeLimitMinutes: timeLimitMinutes
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

    @Test func decodeSettingsSnapshotReturnsNilOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeSettingsSnapshot(Data()) == nil)
        #expect(PersistenceStore.decodeSettingsSnapshot(Data("not json".utf8)) == nil)
    }
}
