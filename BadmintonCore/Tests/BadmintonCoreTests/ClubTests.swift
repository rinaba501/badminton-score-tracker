//
//  ClubTests.swift
//  BadmintonCoreTests
//
//  Roadmap Phase 5b: Club codec round-trips, and backward compatibility for
//  Player/MatchRecord records persisted before clubId existed.
//

import Foundation
import Testing
@testable import BadmintonCore

struct ClubTests {

    @Test func encodeDecodeRoundTripsAClubList() throws {
        let clubs = [
            Club(id: UUID(), name: "Sunday League", createdDate: Date(timeIntervalSince1970: 1_000)),
            Club(id: UUID(), name: "Work Doubles", createdDate: Date(timeIntervalSince1970: 2_000))
        ]
        let encoded = try #require(PersistenceStore.encodeClubs(clubs))
        #expect(PersistenceStore.decodeClubs(encoded) == clubs)
    }

    @Test func decodeClubsReturnsEmptyArrayOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeClubs(Data()).isEmpty)
        #expect(PersistenceStore.decodeClubs(Data("not json".utf8)).isEmpty)
    }

    @Test func encodeClubsProducesDecodableEnvelope() {
        let club = Club(name: "Test Club")
        let encoded = PersistenceStore.encodeClubs([club])
        #expect(encoded != nil)
        #expect(PersistenceStore.decodeClubs(encoded!) == [club])
    }

    // MARK: - clubId backward compatibility

    @Test func playerWithoutClubIdKeyDecodesWithNilClubId() throws {
        // Shaped exactly like a pre-5b roster entry — no clubId key present.
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Alice","colorIndex":0}]
        """
        let players = PersistenceStore.decodeRoster(Data(json.utf8))
        #expect(players.count == 1)
        #expect(players.first?.clubId == nil)
    }

    @Test func matchRecordWithoutClubIdKeyDecodesWithNilClubId() throws {
        // Shaped exactly like a pre-5b history entry — no clubId key present.
        let json = """
        [{"id":"\(UUID().uuidString)","games":[],"myGamesWon":1,"opponentGamesWon":0,
         "winner":"near","myName":"Alice","opponentName":"Bob","date":0,"duration":0}]
        """
        let history = PersistenceStore.decodeHistory(Data(json.utf8))
        #expect(history.count == 1)
        #expect(history.first?.clubId == nil)
    }

    @Test func playerAndMatchRecordRoundTripANonNilClubId() throws {
        let clubId = UUID()
        let player = Player(name: "Alice", clubId: clubId)
        let record = MatchRecord(games: [GameScore(my: 21, opponent: 15)], myGamesWon: 1, opponentGamesWon: 0,
                                  winner: .near, myName: "Alice", opponentName: "Bob",
                                  date: Date(timeIntervalSinceReferenceDate: 0), clubId: clubId)

        let encodedRoster = try #require(PersistenceStore.encodeRoster([player]))
        #expect(PersistenceStore.decodeRoster(encodedRoster).first?.clubId == clubId)

        let encodedHistory = try #require(PersistenceStore.encodeHistory([record]))
        #expect(PersistenceStore.decodeHistory(encodedHistory).first?.clubId == clubId)
    }

    @Test func singleClubEncodeDecodeRoundTrip() throws {
        let club = Club(id: UUID(), name: "League Club", createdDate: Date(timeIntervalSince1970: 5_000), ownerRecordName: "some-owner")
        let encoded = try #require(PersistenceStore.encodeClub(club))
        let decoded = try #require(PersistenceStore.decodeClub(encoded))
        #expect(decoded == club)
        #expect(decoded.ownerRecordName == "some-owner")
    }

    @Test func clubWithoutOwnerRecordNameDecodesWithNil() throws {
        // Shaped like a pre-5c club entry — no ownerRecordName key present.
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Alice's Club","createdDate":0}]
        """
        let clubs = PersistenceStore.decodeClubs(Data(json.utf8))
        #expect(clubs.count == 1)
        #expect(clubs.first?.ownerRecordName == nil)
    }

    // MARK: - requireMatchConfirmation (issue #160)

    @Test func clubWithoutRequireMatchConfirmationKeyDecodesWithNil() throws {
        // Shaped like a pre-#160 club entry — no requireMatchConfirmation key present.
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Alice's Club","createdDate":0}]
        """
        let clubs = PersistenceStore.decodeClubs(Data(json.utf8))
        #expect(clubs.count == 1)
        #expect(clubs.first?.requireMatchConfirmation == nil)
    }

    @Test func clubRoundTripsRequireMatchConfirmationTrue() throws {
        let club = Club(id: UUID(), name: "League Club", requireMatchConfirmation: true)
        let encoded = try #require(PersistenceStore.encodeClub(club))
        let decoded = try #require(PersistenceStore.decodeClub(encoded))
        #expect(decoded.requireMatchConfirmation == true)
    }

    // MARK: - Club seasons (issue #163)

    @Test func clubWithoutSeasonKeysDecodesWithNilDates() throws {
        // Shaped like a pre-#163 club entry — no season keys present.
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Alice's Club","createdDate":0}]
        """
        let clubs = PersistenceStore.decodeClubs(Data(json.utf8))
        #expect(clubs.count == 1)
        #expect(clubs.first?.seasonStartDate == nil)
        #expect(clubs.first?.seasonEndDate == nil)
    }

    @Test func clubRoundTripsSeasonDates() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let club = Club(id: UUID(), name: "League Club", seasonStartDate: start, seasonEndDate: end)
        let encoded = try #require(PersistenceStore.encodeClub(club))
        let decoded = try #require(PersistenceStore.decodeClub(encoded))
        #expect(decoded.seasonStartDate == start)
        #expect(decoded.seasonEndDate == end)
    }

    @Test func isDateInSeasonTrueWhenNoSeasonSet() {
        let club = Club(name: "No Season")
        #expect(club.isDateInSeason(Date(timeIntervalSince1970: 0)))
        #expect(club.isDateInSeason(Date()))
    }

    @Test func isDateInSeasonRespectsStartAndOpenEnd() {
        let start = Date(timeIntervalSince1970: 1_000)
        let club = Club(name: "Open", seasonStartDate: start)
        #expect(!club.isDateInSeason(Date(timeIntervalSince1970: 500)))
        #expect(club.isDateInSeason(start))
        #expect(club.isDateInSeason(Date(timeIntervalSince1970: 1_000_000)))
    }

    @Test func isDateInSeasonRespectsInclusiveEnd() {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        let club = Club(name: "Bounded", seasonStartDate: start, seasonEndDate: end)
        #expect(club.isDateInSeason(start))
        #expect(club.isDateInSeason(end))
        #expect(!club.isDateInSeason(Date(timeIntervalSince1970: 999)))
        #expect(!club.isDateInSeason(Date(timeIntervalSince1970: 2_001)))
    }

    // MARK: - trackStandings

    @Test func clubWithoutTrackStandingsKeyDecodesWithNil() throws {
        // Shaped like a pre-trackStandings club entry — no trackStandings key present.
        let json = """
        [{"id":"\(UUID().uuidString)","name":"Alice's Club","createdDate":0}]
        """
        let clubs = PersistenceStore.decodeClubs(Data(json.utf8))
        #expect(clubs.count == 1)
        #expect(clubs.first?.trackStandings == nil)
    }

    @Test func clubRoundTripsTrackStandingsFalse() throws {
        let club = Club(id: UUID(), name: "League Club", trackStandings: false)
        let encoded = try #require(PersistenceStore.encodeClub(club))
        let decoded = try #require(PersistenceStore.decodeClub(encoded))
        #expect(decoded.trackStandings == false)
    }

    @Test func clubRoundTripsTrackStandingsTrue() throws {
        let club = Club(id: UUID(), name: "League Club", trackStandings: true)
        let encoded = try #require(PersistenceStore.encodeClub(club))
        let decoded = try #require(PersistenceStore.decodeClub(encoded))
        #expect(decoded.trackStandings == true)
    }
}
