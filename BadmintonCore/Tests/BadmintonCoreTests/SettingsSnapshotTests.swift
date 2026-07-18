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
        courtChangeRemindersEnabled: Bool = false,
        clubLastViewedActivity: [String: Date] = [:],
        accountLinked: Bool = false,
        gameScreenStyle: String = "Depth",
        shareHistoryWithFriends: Bool = false,
        shareAvatarWithFriends: Bool = false,
        shareGenderWithFriends: Bool = false,
        shareBirthdayWithFriends: Bool = false,
        shareIntroductionWithFriends: Bool = false,
        shareStatsWithFriends: Bool = false,
        gender: String? = nil,
        birthday: Date? = nil,
        introduction: String? = nil
    ) -> SettingsSnapshot {
        SettingsSnapshot(
            myName: myName, localPlayerId: localPlayerId,
            pointsToWin: pointsToWin, gamesInMatch: gamesInMatch,
            courtTheme: courtTheme, announceScore: announceScore,
            enableSounds: enableSounds, enableCrownScoring: enableCrownScoring,
            timeModeEnabled: timeModeEnabled, timeLimitMinutes: timeLimitMinutes,
            courtChangeRemindersEnabled: courtChangeRemindersEnabled,
            clubLastViewedActivity: clubLastViewedActivity,
            accountLinked: accountLinked,
            gameScreenStyle: gameScreenStyle,
            shareHistoryWithFriends: shareHistoryWithFriends,
            shareAvatarWithFriends: shareAvatarWithFriends,
            shareGenderWithFriends: shareGenderWithFriends,
            shareBirthdayWithFriends: shareBirthdayWithFriends,
            shareIntroductionWithFriends: shareIntroductionWithFriends,
            shareStatsWithFriends: shareStatsWithFriends,
            gender: gender,
            birthday: birthday,
            introduction: introduction
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

    @Test func courtChangeRemindersEnabledRoundTrips() throws {
        let snapshot = makeSnapshot(courtChangeRemindersEnabled: true)
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded.courtChangeRemindersEnabled == true)
    }

    @Test func accountLinkedRoundTrips() throws {
        let snapshot = makeSnapshot(accountLinked: true)
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded.accountLinked == true)
    }

    @Test func gameScreenStyleRoundTrips() throws {
        let snapshot = makeSnapshot(gameScreenStyle: "Split")
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded.gameScreenStyle == "Split")
    }

    @Test func shareHistoryWithFriendsRoundTrips() throws {
        let snapshot = makeSnapshot(shareHistoryWithFriends: true)
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded.shareHistoryWithFriends == true)
    }

    @Test func perFieldFriendVisibilityTogglesRoundTrip() throws {
        let snapshot = makeSnapshot(
            shareAvatarWithFriends: true,
            shareGenderWithFriends: true,
            shareBirthdayWithFriends: true,
            shareIntroductionWithFriends: true,
            shareStatsWithFriends: true
        )
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded.shareAvatarWithFriends == true)
        #expect(decoded.shareGenderWithFriends == true)
        #expect(decoded.shareBirthdayWithFriends == true)
        #expect(decoded.shareIntroductionWithFriends == true)
        #expect(decoded.shareStatsWithFriends == true)
    }

    @Test func genderBirthdayIntroductionRoundTrip() throws {
        let birthday = Date(timeIntervalSince1970: 700_000_000)
        let snapshot = makeSnapshot(gender: "nonbinary", birthday: birthday, introduction: "Loves smashes.")
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded.gender == "nonbinary")
        #expect(decoded.birthday == birthday)
        #expect(decoded.introduction == "Loves smashes.")
    }

    @Test func genderBirthdayIntroductionDefaultToNil() throws {
        let snapshot = makeSnapshot()
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded.gender == nil)
        #expect(decoded.birthday == nil)
        #expect(decoded.introduction == nil)
    }

    @Test func decodeSettingsSnapshotReturnsNilOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeSettingsSnapshot(Data()) == nil)
        #expect(PersistenceStore.decodeSettingsSnapshot(Data("not json".utf8)) == nil)
    }

    @Test func clubLastViewedActivityRoundTripsExactly() throws {
        var dates: [String: Date] = [:]
        dates[UUID().uuidString] = Date(timeIntervalSince1970: 1_700_000_000)
        dates[UUID().uuidString] = Date(timeIntervalSince1970: 1_700_500_000.5)
        let snapshot = makeSnapshot(clubLastViewedActivity: dates)
        let encoded = try #require(PersistenceStore.encodeSettingsSnapshot(snapshot))
        let decoded = try #require(PersistenceStore.decodeSettingsSnapshot(encoded))
        #expect(decoded == snapshot)
        #expect(decoded.clubLastViewedActivity == dates)
    }

    // A Settings payload written before clubLastViewedActivity /
    // accountLinked existed must still decode, defaulting the new fields —
    // the whole point of the custom decodeIfPresent init.
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
        #expect(decoded.courtChangeRemindersEnabled == false)
        #expect(decoded.clubLastViewedActivity == [:])
        #expect(decoded.accountLinked == false)
        #expect(decoded.gameScreenStyle == "Depth")
        #expect(decoded.shareHistoryWithFriends == false)
        #expect(decoded.shareAvatarWithFriends == false)
        #expect(decoded.shareGenderWithFriends == false)
        #expect(decoded.shareBirthdayWithFriends == false)
        #expect(decoded.shareIntroductionWithFriends == false)
        #expect(decoded.shareStatsWithFriends == false)
        #expect(decoded.gender == nil)
        #expect(decoded.birthday == nil)
        #expect(decoded.introduction == nil)
    }
}
