//
//  SchemaVersioningTests.swift
//  BadmintonCoreTests
//
//  Pins the versioned-envelope format, per-record tolerant decoding, and the
//  migration hook added for issue #107.
//

import Foundation
import Testing
@testable import BadmintonCore

struct SchemaVersioningTests {

    private let alice = Player(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Alice", colorIndex: 0)
    private let bob = Player(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Bob", colorIndex: 1, iconName: "star.fill")

    // MARK: - Legacy bare-array format (implicit schema version 0)

    @Test func legacyBareArrayDecodesCorrectly() {
        let json = """
        [
          {"id":"11111111-1111-1111-1111-111111111111","name":"Alice","colorIndex":0},
          {"id":"22222222-2222-2222-2222-222222222222","name":"Bob","colorIndex":1,"iconName":"star.fill"}
        ]
        """
        let players = PersistenceStore.decodeRoster(Data(json.utf8))
        #expect(players == [alice, bob])
    }

    // MARK: - Current envelope format

    @Test func envelopeFormatDecodesCorrectly() {
        let json = """
        {"schemaVersion":1,"records":[
          {"id":"11111111-1111-1111-1111-111111111111","name":"Alice","colorIndex":0}
        ]}
        """
        let players = PersistenceStore.decodeRoster(Data(json.utf8))
        #expect(players == [alice])
    }

    @Test func encodeRosterProducesDecodableEnvelope() {
        let encoded = PersistenceStore.encodeRoster([alice, bob])
        #expect(encoded != nil)
        let decoded = PersistenceStore.decodeRoster(encoded!)
        #expect(decoded == [alice, bob])
    }

    // MARK: - Per-record tolerance

    @Test func corruptRecordInMiddleIsSkippedLegacyFormat() {
        let json = """
        [
          {"id":"11111111-1111-1111-1111-111111111111","name":"Alice","colorIndex":0},
          {"id":"33333333-3333-3333-3333-333333333333","name":"Corrupt","colorIndex":"not-a-number"},
          {"id":"22222222-2222-2222-2222-222222222222","name":"Bob","colorIndex":1,"iconName":"star.fill"}
        ]
        """
        let players = PersistenceStore.decodeRoster(Data(json.utf8))
        #expect(players == [alice, bob])
    }

    @Test func corruptRecordInMiddleIsSkippedEnvelopeFormat() {
        let json = """
        {"schemaVersion":1,"records":[
          {"id":"11111111-1111-1111-1111-111111111111","name":"Alice","colorIndex":0},
          {"id":"33333333-3333-3333-3333-333333333333","name":"Corrupt","colorIndex":"not-a-number"},
          {"id":"22222222-2222-2222-2222-222222222222","name":"Bob","colorIndex":1,"iconName":"star.fill"}
        ]}
        """
        let players = PersistenceStore.decodeRoster(Data(json.utf8))
        #expect(players == [alice, bob])
    }

    @Test func catastrophicallyCorruptDataReturnsEmptyArray() {
        let players = PersistenceStore.decodeRoster(Data("not json at all".utf8))
        #expect(players.isEmpty)
    }

    // MARK: - Migration hook

    @Test func migratedRosterDataUpgradesLegacyFormat() {
        let legacyJSON = """
        [{"id":"11111111-1111-1111-1111-111111111111","name":"Alice","colorIndex":0}]
        """
        let legacyData = Data(legacyJSON.utf8)

        let migrated = PersistenceStore.migratedRosterData(from: legacyData)
        #expect(migrated != nil)
        #expect(PersistenceStore.decodeRoster(migrated!) == [alice])

        // Re-migrating already-current data is a no-op.
        #expect(PersistenceStore.migratedRosterData(from: migrated!) == nil)
    }

    @Test func migratedHistoryDataUpgradesLegacyFormat() {
        let record = MatchRecord(
            games: [GameScore(my: 21, opponent: 15)],
            myGamesWon: 1, opponentGamesWon: 0,
            winner: "Alice", myName: "Alice", opponentName: "Bob",
            date: Date(timeIntervalSinceReferenceDate: 0)
        )
        // Build legacy bare-array Data by encoding a plain [MatchRecord] directly
        // (bypassing PersistenceStore, which always emits the envelope now).
        let legacyData = try! JSONEncoder().encode([record])

        let migrated = PersistenceStore.migratedHistoryData(from: legacyData)
        #expect(migrated != nil)
        #expect(PersistenceStore.decodeHistory(migrated!) == [record])
        #expect(PersistenceStore.migratedHistoryData(from: migrated!) == nil)
    }

    @Test func migratedDataReturnsNilForEmptyData() {
        #expect(PersistenceStore.migratedRosterData(from: Data()) == nil)
        #expect(PersistenceStore.migratedHistoryData(from: Data()) == nil)
    }

    @Test func migratedDataReturnsNilWhenAlreadyCurrent() {
        let encoded = PersistenceStore.encodeRoster([alice])!
        #expect(PersistenceStore.migratedRosterData(from: encoded) == nil)
    }
}
