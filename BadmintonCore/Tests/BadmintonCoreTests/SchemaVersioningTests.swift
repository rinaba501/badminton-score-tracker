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

    @Test func migratedHistoryDataUpgradesLegacyFormat() throws {
        let record = MatchRecord(
            games: [GameScore(my: 21, opponent: 15)],
            myGamesWon: 1, opponentGamesWon: 0,
            winner: .near, myName: "Alice", opponentName: "Bob",
            date: Date(timeIntervalSinceReferenceDate: 0)
        )
        // Build legacy bare-array Data by encoding a plain [MatchRecord] directly
        // (bypassing PersistenceStore, which always emits the envelope now).
        let legacyData = try JSONEncoder().encode([record])

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

    // MARK: - MatchRecord.winner: String -> RecordSide (self-migrating Codable)

    /// Records persisted before `RecordSide` existed stored `winner` as a copy
    /// of the winning team's display name. `MatchRecord.init(from:)` must
    /// still decode that shape and convert it, without any PersistenceStore
    /// schema-version bump.
    @Test func legacyStringWinnerDecodesToNearWhenItMatchesMyName() {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","games":[],"myGamesWon":1,"opponentGamesWon":0,
         "winner":"Alice","myName":"Alice","opponentName":"Bob","date":0,"duration":0}]
        """
        let history = PersistenceStore.decodeHistory(Data(json.utf8))
        #expect(history.count == 1)
        #expect(history.first?.winner == .near)
    }

    @Test func legacyStringWinnerDecodesToFarWhenItMatchesOpponentName() {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","games":[],"myGamesWon":0,"opponentGamesWon":1,
         "winner":"Bob","myName":"Alice","opponentName":"Bob","date":0,"duration":0}]
        """
        let history = PersistenceStore.decodeHistory(Data(json.utf8))
        #expect(history.count == 1)
        #expect(history.first?.winner == .far)
    }

    @Test func legacyStringWinnerDecodesInADoublesRecord() {
        // Doubles: the legacy winner string was still just the representative
        // (non-partner) name of whichever team won.
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","games":[],"myGamesWon":0,"opponentGamesWon":1,
         "winner":"Cara","myName":"Alice","opponentName":"Cara",
         "myPartnerName":"Bob","opponentPartnerName":"Dan","date":0,"duration":0}]
        """
        let history = PersistenceStore.decodeHistory(Data(json.utf8))
        #expect(history.count == 1)
        #expect(history.first?.winner == .far)
        #expect(history.first?.isDoubles == true)
    }

    @Test func currentRecordSideWinnerRoundTripsThroughEncodeDecode() {
        let record = MatchRecord(games: [GameScore(my: 21, opponent: 15)], myGamesWon: 1, opponentGamesWon: 0,
                                  winner: .near, myName: "Alice", opponentName: "Bob",
                                  date: Date(timeIntervalSinceReferenceDate: 0))
        let encoded = PersistenceStore.encodeHistory([record])!
        #expect(PersistenceStore.decodeHistory(encoded) == [record])
    }

    // MARK: - MatchRecord.isConfirmed (issue #160, match confirmation)

    @Test func legacyRecordWithoutIsConfirmedKeyDecodesAsConfirmed() {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","games":[],"myGamesWon":1,"opponentGamesWon":0,
         "winner":"near","myName":"Alice","opponentName":"Bob","date":0,"duration":0}]
        """
        let history = PersistenceStore.decodeHistory(Data(json.utf8))
        #expect(history.count == 1)
        #expect(history.first?.isConfirmed == true)
    }

    @Test func isConfirmedRoundTripsThroughEncodeDecodeWhenFalse() {
        let record = MatchRecord(games: [GameScore(my: 21, opponent: 15)], myGamesWon: 1, opponentGamesWon: 0,
                                  winner: .near, myName: "Alice", opponentName: "Bob",
                                  date: Date(timeIntervalSinceReferenceDate: 0),
                                  clubId: UUID(), isConfirmed: false)
        let encoded = PersistenceStore.encodeHistory([record])!
        let decoded = PersistenceStore.decodeHistory(encoded)
        #expect(decoded == [record])
        #expect(decoded.first?.isConfirmed == false)
    }

    // MARK: - MatchRecord.isOfficial (practice matches)

    @Test func legacyRecordWithoutIsOfficialKeyDecodesAsOfficial() {
        let json = """
        [{"id":"11111111-1111-1111-1111-111111111111","games":[],"myGamesWon":1,"opponentGamesWon":0,
         "winner":"near","myName":"Alice","opponentName":"Bob","date":0,"duration":0}]
        """
        let history = PersistenceStore.decodeHistory(Data(json.utf8))
        #expect(history.count == 1)
        #expect(history.first?.isOfficial == true)
    }

    @Test func isOfficialRoundTripsThroughEncodeDecodeWhenFalse() {
        let record = MatchRecord(games: [GameScore(my: 21, opponent: 15)], myGamesWon: 1, opponentGamesWon: 0,
                                  winner: .near, myName: "Alice", opponentName: "Bob",
                                  date: Date(timeIntervalSinceReferenceDate: 0),
                                  clubId: UUID(), isOfficial: false)
        let encoded = PersistenceStore.encodeHistory([record])!
        let decoded = PersistenceStore.decodeHistory(encoded)
        #expect(decoded == [record])
        #expect(decoded.first?.isOfficial == false)
    }
}
