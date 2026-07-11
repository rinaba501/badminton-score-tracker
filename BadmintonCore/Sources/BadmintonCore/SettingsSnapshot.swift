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
        clubLastViewedActivity: [String: Date] = [:],
        accountLinked: Bool = false
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
        self.clubLastViewedActivity = clubLastViewedActivity
        self.accountLinked = accountLinked
    }

    private enum CodingKeys: String, CodingKey {
        case myName, localPlayerId, pointsToWin, gamesInMatch, courtTheme
        case announceScore, enableSounds, enableCrownScoring, timeModeEnabled
        case timeLimitMinutes, clubLastViewedActivity
        case accountLinked
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
        clubLastViewedActivity = try container.decodeIfPresent([String: Date].self, forKey: .clubLastViewedActivity) ?? [:]
        accountLinked = try container.decodeIfPresent(Bool.self, forKey: .accountLinked) ?? false
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
        try container.encode(clubLastViewedActivity, forKey: .clubLastViewedActivity)
        try container.encode(accountLinked, forKey: .accountLinked)
    }
}
