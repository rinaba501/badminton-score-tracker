//
//  SettingsSnapshot.swift
//  BadmintonCore
//
//  A single CloudKit record carrying every scalar setting that used to sync
//  via the iCloud KV store (see CloudKitSyncManager's "Settings" record).
//  Fields are the raw UserDefaults storage types, not app-side enums
//  (CourtTheme/GameMode live in each app target) — courtTheme is stored as
//  its String rawValue, matching what @AppStorage already persists.
//
//  Custom Codable: fields added after the first CloudKit Settings records
//  were written must decode as optional-with-default so an older payload
//  (missing those keys) still decodes instead of failing the whole record —
//  same self-migration approach MatchRecord uses for its `winner` field.
//  clubLastViewedActivity / accountLinked were added in this vein.
//

import Foundation

public struct SettingsSnapshot: Codable, Equatable {
    public var myName: String
    public var localPlayerId: String
    public var pointsToWin: Int
    public var gamesInMatch: Int
    public var courtTheme: String
    public var announceScore: Bool
    public var enableSounds: Bool
    public var enableCrownScoring: Bool
    public var timeModeEnabled: Bool
    public var timeLimitMinutes: Int
    /// Opt-in court-change reminder toggle (see AppStorageKeys.courtChangeRemindersEnabled).
    /// Blind-overwritten on apply, like the other plain Bools.
    public var courtChangeRemindersEnabled: Bool
    /// Per-club "last viewed activity" timestamps (club id string -> date)
    /// backing the unread dot on ClubsView. Merged (per-club max), never
    /// overwritten, on apply — see AppStore.applyRemoteSettings.
    public var clubLastViewedActivity: [String: Date]
    /// Whether the user has opted to link this local identity to their
    /// CloudKit account (the same account backing Friends/Club). The account
    /// id itself is never stored here — it's always re-derived via
    /// CloudKitSyncManager.resolveMyParticipantId(), which is deterministic
    /// per Apple ID. Blind-overwritten on apply, like the other plain Bools.
    public var accountLinked: Bool
    /// iOS-only GameView visual style ("Depth"/"Split"/"Minimal") stored as
    /// its raw String value, same rationale as courtTheme — Watch round-trips
    /// this field without ever reading it into a typed enum.
    public var gameScreenStyle: String
    /// Whether personal (clubId == nil) roster + history mirror read-only
    /// into the "FriendsHistory" CKShare zone for every accepted friend.
    /// Blind-overwritten on apply, like the other plain Bools.
    public var shareHistoryWithFriends: Bool
    /// Per-field friend-visibility toggles for the profile fields below
    /// (avatar/gender/birthday/introduction) plus derived stats — each
    /// independently gates whether that one field is mirrored into
    /// FriendIdentitySnapshot/FriendStatsSnapshot. Unlike shareHistoryWithFriends
    /// these never expose raw match records. Name has no toggle: an accepted
    /// FriendRequest already carries a snapshotted displayName, so there's no
    /// way to hide it from an existing friend (see FriendIdentitySnapshot).
    public var shareAvatarWithFriends: Bool
    public var shareGenderWithFriends: Bool
    public var shareBirthdayWithFriends: Bool
    public var shareIntroductionWithFriends: Bool
    public var shareStatsWithFriends: Bool
    /// Free-form gender label (e.g. "male"/"female"/"nonbinary"/"custom:<text>"),
    /// nil for "prefer not to say". Plain String rather than an enum so new
    /// options never require a schema/migration decision.
    public var gender: String?
    public var birthday: Date?
    /// Short bio, capped at 200 chars at the edit site (ProfileView).
    public var introduction: String?

    public init(
        myName: String,
        localPlayerId: String,
        pointsToWin: Int,
        gamesInMatch: Int,
        courtTheme: String,
        announceScore: Bool,
        enableSounds: Bool,
        enableCrownScoring: Bool,
        timeModeEnabled: Bool,
        timeLimitMinutes: Int,
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
    ) {
        self.myName = myName
        self.localPlayerId = localPlayerId
        self.pointsToWin = pointsToWin
        self.gamesInMatch = gamesInMatch
        self.courtTheme = courtTheme
        self.announceScore = announceScore
        self.enableSounds = enableSounds
        self.enableCrownScoring = enableCrownScoring
        self.timeModeEnabled = timeModeEnabled
        self.timeLimitMinutes = timeLimitMinutes
        self.courtChangeRemindersEnabled = courtChangeRemindersEnabled
        self.clubLastViewedActivity = clubLastViewedActivity
        self.accountLinked = accountLinked
        self.gameScreenStyle = gameScreenStyle
        self.shareHistoryWithFriends = shareHistoryWithFriends
        self.shareAvatarWithFriends = shareAvatarWithFriends
        self.shareGenderWithFriends = shareGenderWithFriends
        self.shareBirthdayWithFriends = shareBirthdayWithFriends
        self.shareIntroductionWithFriends = shareIntroductionWithFriends
        self.shareStatsWithFriends = shareStatsWithFriends
        self.gender = gender
        self.birthday = birthday
        self.introduction = introduction
    }

    private enum CodingKeys: String, CodingKey {
        case myName, localPlayerId, pointsToWin, gamesInMatch, courtTheme
        case announceScore, enableSounds, enableCrownScoring, timeModeEnabled
        case timeLimitMinutes, courtChangeRemindersEnabled, clubLastViewedActivity
        case accountLinked, gameScreenStyle, shareHistoryWithFriends
        case shareAvatarWithFriends, shareGenderWithFriends, shareBirthdayWithFriends
        case shareIntroductionWithFriends, shareStatsWithFriends
        case gender, birthday, introduction
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        myName = try container.decode(String.self, forKey: .myName)
        localPlayerId = try container.decode(String.self, forKey: .localPlayerId)
        pointsToWin = try container.decode(Int.self, forKey: .pointsToWin)
        gamesInMatch = try container.decode(Int.self, forKey: .gamesInMatch)
        courtTheme = try container.decode(String.self, forKey: .courtTheme)
        announceScore = try container.decode(Bool.self, forKey: .announceScore)
        enableSounds = try container.decode(Bool.self, forKey: .enableSounds)
        enableCrownScoring = try container.decode(Bool.self, forKey: .enableCrownScoring)
        timeModeEnabled = try container.decode(Bool.self, forKey: .timeModeEnabled)
        timeLimitMinutes = try container.decode(Int.self, forKey: .timeLimitMinutes)
        // Added after the first Settings records shipped — tolerate absence.
        courtChangeRemindersEnabled = try container.decodeIfPresent(Bool.self, forKey: .courtChangeRemindersEnabled) ?? false
        clubLastViewedActivity = try container.decodeIfPresent([String: Date].self, forKey: .clubLastViewedActivity) ?? [:]
        accountLinked = try container.decodeIfPresent(Bool.self, forKey: .accountLinked) ?? false
        gameScreenStyle = try container.decodeIfPresent(String.self, forKey: .gameScreenStyle) ?? "Depth"
        shareHistoryWithFriends = try container.decodeIfPresent(Bool.self, forKey: .shareHistoryWithFriends) ?? false
        shareAvatarWithFriends = try container.decodeIfPresent(Bool.self, forKey: .shareAvatarWithFriends) ?? false
        shareGenderWithFriends = try container.decodeIfPresent(Bool.self, forKey: .shareGenderWithFriends) ?? false
        shareBirthdayWithFriends = try container.decodeIfPresent(Bool.self, forKey: .shareBirthdayWithFriends) ?? false
        shareIntroductionWithFriends = try container.decodeIfPresent(Bool.self, forKey: .shareIntroductionWithFriends) ?? false
        shareStatsWithFriends = try container.decodeIfPresent(Bool.self, forKey: .shareStatsWithFriends) ?? false
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        birthday = try container.decodeIfPresent(Date.self, forKey: .birthday)
        introduction = try container.decodeIfPresent(String.self, forKey: .introduction)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(myName, forKey: .myName)
        try container.encode(localPlayerId, forKey: .localPlayerId)
        try container.encode(pointsToWin, forKey: .pointsToWin)
        try container.encode(gamesInMatch, forKey: .gamesInMatch)
        try container.encode(courtTheme, forKey: .courtTheme)
        try container.encode(announceScore, forKey: .announceScore)
        try container.encode(enableSounds, forKey: .enableSounds)
        try container.encode(enableCrownScoring, forKey: .enableCrownScoring)
        try container.encode(timeModeEnabled, forKey: .timeModeEnabled)
        try container.encode(timeLimitMinutes, forKey: .timeLimitMinutes)
        try container.encode(courtChangeRemindersEnabled, forKey: .courtChangeRemindersEnabled)
        try container.encode(clubLastViewedActivity, forKey: .clubLastViewedActivity)
        try container.encode(accountLinked, forKey: .accountLinked)
        try container.encode(gameScreenStyle, forKey: .gameScreenStyle)
        try container.encode(shareHistoryWithFriends, forKey: .shareHistoryWithFriends)
        try container.encode(shareAvatarWithFriends, forKey: .shareAvatarWithFriends)
        try container.encode(shareGenderWithFriends, forKey: .shareGenderWithFriends)
        try container.encode(shareBirthdayWithFriends, forKey: .shareBirthdayWithFriends)
        try container.encode(shareIntroductionWithFriends, forKey: .shareIntroductionWithFriends)
        try container.encode(shareStatsWithFriends, forKey: .shareStatsWithFriends)
        try container.encodeIfPresent(gender, forKey: .gender)
        try container.encodeIfPresent(birthday, forKey: .birthday)
        try container.encodeIfPresent(introduction, forKey: .introduction)
    }
}
