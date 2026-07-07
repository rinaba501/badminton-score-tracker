//
//  AppStorageKeys.swift
//  BadmintonCore
//
//  Single source of truth for every UserDefaults / @AppStorage key the app
//  persists. Only the key *strings* live here — typed defaults stay at each
//  @AppStorage declaration site, because several reference app-only types
//  (CourtTheme, SettingsView.GameMode). New persisted keys must be added
//  here, never as inline string literals — and if the new key should sync
//  across devices, it must ALSO be added to the SyncKeys list in the app's
//  CloudSyncManager.swift; membership there is what opts a key into iCloud.
//

import Foundation

public enum AppStorageKeys {
    public static let myName = "myName"
    public static let matchMyName = "matchMyName"
    public static let matchOpponentName = "matchOpponentName"
    public static let matchMyPartnerName = "matchMyPartnerName"
    public static let matchOpponentPartnerName = "matchOpponentPartnerName"
    // PreMatchView's club picker (#169); UUID string, "" = Personal. Same
    // per-device match-config exclusion as matchMyName et al. — never added
    // to either target's CloudSyncManager.SyncKeys.
    public static let matchClubId = "matchClubId"
    public static let playerRoster = "playerRoster"
    public static let matchHistory = "matchHistory"
    // Roadmap Phase 5b: local-only club list (no CloudKit sync yet — see
    // Club.swift and AppStore.saveClubs).
    public static let clubs = "clubs"
    public static let playerSortOrder = "playerSortOrder"
    public static let pointsToWin = "pointsToWin"
    public static let gamesInMatch = "gamesInMatch"
    public static let courtTheme = "courtTheme"
    public static let announceScore = "announceScore"
    public static let enableSounds = "enableSounds"
    public static let enableCrownScoring = "enableCrownScoring"
    public static let timeModeEnabled = "timeModeEnabled"
    public static let timeLimitMinutes = "timeLimitMinutes"
    public static let gameMode = "gameMode"
    public static let localPlayerId = "localPlayerId"

    // CloudKit sync (Phase 4, #109). Not KV-synced — these are local device
    // state for the CloudKit transport: the serialized CKSyncEngine state, a
    // one-time "already uploaded local data" flag, and a runtime kill-switch
    // (default true) that falls back to the KV-store history path.
    public static let ckSyncEngineState = "ckSyncEngineState"
    public static let ckSharedSyncEngineState = "ckSharedSyncEngineState"
    public static let didMigrateToCloudKit = "didMigrateToCloudKit"
    public static let cloudKitSyncEnabled = "cloudKitSyncEnabled"
    // Per-record CKRecord system fields (change tags), keyed by recordName, so
    // in-place updates carry the right tag instead of conflicting every time.
    public static let ckRecordMetadata = "ckRecordMetadata"
}
