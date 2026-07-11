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
        timeLimitMinutes: Int
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
    }
}
