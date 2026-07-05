//
//  RecordCodecTests.swift
//  BadmintonCoreTests
//
//  Pins the pure CloudKit-support helpers on PersistenceStore: single-record
//  payload codecs, the write-path diff (upserts/deletes), and per-record
//  conflict resolution. These are the CI-verifiable core of the CloudKit
//  migration (#109); the CKSyncEngine glue that consumes them lives in the app
//  target and is validated by a two-device test instead.
//

import Foundation
import Testing
@testable import BadmintonCore

struct RecordCodecTests {

    private func doublesRecord(id: UUID = UUID()) -> MatchRecord {
        MatchRecord(
            id: id,
            games: [GameScore(my: 21, opponent: 18), GameScore(my: 19, opponent: 21), GameScore(my: 21, opponent: 15)],
            myGamesWon: 2, opponentGamesWon: 1,
            winner: "Alice", myName: "Alice", opponentName: "Cara",
            date: Date(timeIntervalSince1970: 1_000), duration: 900,
            myPlayerId: UUID(), opponentPlayerId: UUID(),
            myPartnerName: "Bob", opponentPartnerName: "Dan",
            myPartnerPlayerId: UUID(), opponentPartnerPlayerId: UUID()
        )
    }

    private func singlesRecord(id: UUID = UUID(), name: String = "Me", opp: String = "Bob") -> MatchRecord {
        MatchRecord(games: [GameScore(my: 21, opponent: 15)], myGamesWon: 1, opponentGamesWon: 0,
                    winner: name, myName: name, opponentName: opp, date: Date(timeIntervalSince1970: 2_000),
                    myPlayerId: nil, opponentPlayerId: nil)
            .withId(id)
    }

    // MARK: - Single-record codecs

    @Test func encodeDecodeRoundTripsAFullDoublesRecord() throws {
        let record = doublesRecord()
        let data = try #require(PersistenceStore.encodeRecord(record))
        #expect(PersistenceStore.decodeRecord(data) == record)
    }

    @Test func encodeDecodeRoundTripsAMinimalSinglesRecord() throws {
        let record = singlesRecord()
        let data = try #require(PersistenceStore.encodeRecord(record))
        #expect(PersistenceStore.decodeRecord(data) == record)
    }

    @Test func decodeRecordReturnsNilOnEmptyOrGarbage() {
        #expect(PersistenceStore.decodeRecord(Data()) == nil)
        #expect(PersistenceStore.decodeRecord(Data([0x00, 0x01, 0x02, 0x03])) == nil)
        #expect(PersistenceStore.decodeRecord(Data("not json".utf8)) == nil)
    }

    @Test func encodeRecordIsByteDeterministic() {
        let record = doublesRecord()
        #expect(PersistenceStore.encodeRecord(record) == PersistenceStore.encodeRecord(record))
    }

    @Test func encodeDecodeRoundTripsAPlayer() throws {
        let player = Player(id: UUID(), name: "Jane Doe", colorIndex: 3, iconName: "star")
        let data = try #require(PersistenceStore.encodePlayer(player))
        #expect(PersistenceStore.decodePlayer(data) == player)
    }

    @Test func decodePlayerReturnsNilOnEmptyOrGarbage() {
        #expect(PersistenceStore.decodePlayer(Data()) == nil)
        #expect(PersistenceStore.decodePlayer(Data([0xFF, 0xEE])) == nil)
    }

    // MARK: - Diff (write path)

    @Test func diffHistoryAppendYieldsOneUpsertNoDelete() {
        let a = singlesRecord()
        let b = singlesRecord()
        let diff = PersistenceStore.diffHistory(from: [a], to: [a, b])
        #expect(diff.upsertedIds == [b.id])
        #expect(diff.deletedIds.isEmpty)
    }

    @Test func diffHistoryInPlaceEditUpsertsOnlyTheChangedId() {
        let a = singlesRecord(name: "Me")
        let b = singlesRecord()
        // Rename `a` in place (same id, changed fields); `b` is untouched.
        let renamed = a.renamed(to: "Renamed")
        let diff = PersistenceStore.diffHistory(from: [a, b], to: [renamed, b])
        #expect(diff.upsertedIds == [a.id])
        #expect(diff.deletedIds.isEmpty)
    }

    @Test func diffHistorySingleDeleteYieldsOneDeleteNoUpsert() {
        let a = singlesRecord()
        let b = singlesRecord()
        let diff = PersistenceStore.diffHistory(from: [a, b], to: [a])
        #expect(diff.upsertedIds.isEmpty)
        #expect(diff.deletedIds == [b.id])
    }

    @Test func diffHistoryClearAllYieldsAllDeletesNoUpsert() {
        let a = singlesRecord()
        let b = singlesRecord()
        let diff = PersistenceStore.diffHistory(from: [a, b], to: [])
        #expect(diff.upsertedIds.isEmpty)
        #expect(Set(diff.deletedIds) == [a.id, b.id])
    }

    @Test func diffHistoryReorderOnlyIsEmpty() {
        let a = singlesRecord()
        let b = singlesRecord()
        let diff = PersistenceStore.diffHistory(from: [a, b], to: [b, a])
        #expect(diff.upsertedIds.isEmpty)
        #expect(diff.deletedIds.isEmpty)
    }

    @Test func diffRosterDetectsAddEditAndRemove() {
        let keep = Player(name: "Keep")
        let edit = Player(name: "Old")
        let remove = Player(name: "Remove")
        var editedInPlace = edit
        editedInPlace.name = "New"
        let add = Player(name: "Add")

        let diff = PersistenceStore.diffRoster(from: [keep, edit, remove], to: [keep, editedInPlace, add])
        #expect(Set(diff.upsertedIds) == [edit.id, add.id])
        #expect(diff.deletedIds == [remove.id])
    }

    // MARK: - Conflict resolution

    @Test func resolveConflictKeepsLocalDeletionButOtherwiseTakesServer() {
        #expect(PersistenceStore.resolveConflict(localIntendedDelete: true) == .keepDeletion)
        #expect(PersistenceStore.resolveConflict(localIntendedDelete: false) == .takeServer)
    }
}

// Small test-only conveniences for building record variants without repeating
// the long MatchRecord initializer.
private extension MatchRecord {
    func withId(_ id: UUID) -> MatchRecord {
        MatchRecord(id: id, games: games, myGamesWon: myGamesWon, opponentGamesWon: opponentGamesWon,
                    winner: winner, myName: myName, opponentName: opponentName, date: date, duration: duration,
                    myPlayerId: myPlayerId, opponentPlayerId: opponentPlayerId,
                    myPartnerName: myPartnerName, opponentPartnerName: opponentPartnerName,
                    myPartnerPlayerId: myPartnerPlayerId, opponentPartnerPlayerId: opponentPartnerPlayerId)
    }

    func renamed(to newName: String) -> MatchRecord {
        MatchRecord(id: id, games: games, myGamesWon: myGamesWon, opponentGamesWon: opponentGamesWon,
                    winner: newName, myName: newName, opponentName: opponentName, date: date, duration: duration,
                    myPlayerId: myPlayerId, opponentPlayerId: opponentPlayerId,
                    myPartnerName: myPartnerName, opponentPartnerName: opponentPartnerName,
                    myPartnerPlayerId: myPartnerPlayerId, opponentPartnerPlayerId: opponentPartnerPlayerId)
    }
}
