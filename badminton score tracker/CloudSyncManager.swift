//
//  CloudSyncManager.swift
//  badminton score tracker (iOS)
//
//  iCloud key-value sync for the iPhone companion app (ROADMAP Phase 6, #41).
//  A KV-only port of the Watch App's CloudSyncManager: the iOS app v1 has no
//  CloudKit path, so every CloudKitSyncManager branch is dropped and the KV
//  store always owns history + roster. The phone shares the Watch's KV bucket
//  via a byte-identical `ubiquity-kvstore-identifier` entitlement on both
//  targets, so it reads/writes the same synced data. The Watch stays the
//  scoring device; the phone reads history/stats/roster and can delete/edit.
//

import Foundation
import Combine
import SwiftUI
import os
import BadmintonCore

/// Non-blocking status surfaced when the iCloud KV store is close to (or has
/// hit) its ~1 MB quota. Mirrors the Watch App's warning; the phone is a
/// second writer to the same bucket, so it can surface the same condition.
enum CloudSyncWarning {
    case approachingLimit
    case quotaExceeded

    var messageKey: LocalizedStringKey {
        switch self {
        case .approachingLimit: LocalizedStringKey("settings.icloud_quota_warning")
        case .quotaExceeded: LocalizedStringKey("settings.icloud_quota_exceeded")
        }
    }
}

// Keys synced to iCloud key-value store. The key strings themselves live in
// BadmintonCore.AppStorageKeys; this list selects WHICH of them sync
// (matchMyName/matchOpponentName/playerSortOrder/gameMode intentionally
// do not — they are per-device state). Kept byte-identical to the Watch's
// SyncKeys so both targets agree on exactly what crosses the bucket.
private enum SyncKeys {
    static let playerRoster = AppStorageKeys.playerRoster
    static let matchHistory = AppStorageKeys.matchHistory
    static let scalars: [String] = [
        AppStorageKeys.myName,
        AppStorageKeys.localPlayerId,
        AppStorageKeys.pointsToWin,
        AppStorageKeys.gamesInMatch,
        AppStorageKeys.courtTheme,
        AppStorageKeys.announceScore,
        AppStorageKeys.enableSounds,
        AppStorageKeys.enableCrownScoring,
        AppStorageKeys.timeModeEnabled,
        AppStorageKeys.timeLimitMinutes
    ]
    static let all: [String] = scalars + [playerRoster, matchHistory]
}

@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    private let kvStore = NSUbiquitousKeyValueStore.default
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "badminton-score-tracker", category: "CloudSync")

    /// Set from `syncHistory()` (recomputed on every push/pull) and escalated
    /// by `externalChange(_:)` on an actual quota violation.
    @Published private(set) var syncWarning: CloudSyncWarning?

    private init() {}

    // Non-history keys the KV store pushes/pulls directly. Roster is a blob
    // treated like a scalar here (history is merged separately). The iOS app
    // has no CloudKit path, so the KV store always owns everything — there is
    // no `kvOwnsData` gate like the Watch has.
    private var directKeys: [String] { SyncKeys.scalars + [SyncKeys.playerRoster] }

    func start() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(externalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )
        kvStore.synchronize()
        pullFromCloud()
    }

    // Push all local UserDefaults values to iCloud. Match history is merged
    // (see syncHistory) rather than overwritten so no device clobbers another
    // — except when `overwriteHistory` is set, which pushes local history to
    // iCloud as-is. Callers pass that for intentional deletions (see
    // PersistenceStore.isHistoryShrink): merging a shrunk history against
    // iCloud's unshrunk copy would silently resurrect what was just deleted.
    func pushToCloud(overwriteHistory: Bool = false) {
        let defaults = UserDefaults.standard
        for key in directKeys {
            if let value = defaults.object(forKey: key) {
                kvStore.set(value, forKey: key)
            }
        }
        if overwriteHistory {
            let localData = defaults.data(forKey: SyncKeys.matchHistory) ?? Data()
            kvStore.set(localData, forKey: SyncKeys.matchHistory)
        } else {
            syncHistory()
        }
        AppStore.shared.reloadFromStorage()
        kvStore.synchronize()
    }

    // Pull iCloud values into UserDefaults, only overwriting if iCloud has data
    private func pullFromCloud() {
        let defaults = UserDefaults.standard
        for key in directKeys {
            if let value = kvStore.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        syncHistory()
        AppStore.shared.reloadFromStorage()
    }

    @objc private func externalChange(_ notification: Notification) {
        guard let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return }
        if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
            syncWarning = .quotaExceeded
            logger.error("iCloud KV store quota exceeded — sync has stopped for at least one key")
            return
        }
        // Only pull on server change or initial sync
        guard reason == NSUbiquitousKeyValueStoreServerChange ||
              reason == NSUbiquitousKeyValueStoreInitialSyncChange else { return }

        var dataKeysChanged = false
        if let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
            let defaults = UserDefaults.standard
            let applicable = Set(directKeys)
            for key in changedKeys where applicable.contains(key) {
                if let value = kvStore.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
                if key == SyncKeys.playerRoster { dataKeysChanged = true }
            }
            if changedKeys.contains(SyncKeys.matchHistory) {
                syncHistory()
                dataKeysChanged = true
            }
        }
        if dataKeysChanged {
            AppStore.shared.reloadFromStorage()
        }
    }

    // Reconcile local and iCloud match history by merging both by record id,
    // then write the union back to both stores. Match records are append-only,
    // so this converges without losing matches recorded on either device.
    private func syncHistory() {
        let defaults = UserDefaults.standard
        let localData = defaults.data(forKey: SyncKeys.matchHistory) ?? Data()
        let cloudData = kvStore.data(forKey: SyncKeys.matchHistory) ?? Data()
        let merged = PersistenceStore.mergeHistory(
            PersistenceStore.decodeHistory(localData),
            PersistenceStore.decodeHistory(cloudData)
        )
        guard let mergedData = PersistenceStore.encodeHistory(merged) else { return }
        if mergedData != localData { defaults.set(mergedData, forKey: SyncKeys.matchHistory) }
        if mergedData != cloudData { kvStore.set(mergedData, forKey: SyncKeys.matchHistory) }

        if PersistenceStore.exceedsICloudQuotaWarningThreshold(mergedData) {
            syncWarning = .approachingLimit
            logger.warning("iCloud KV store approaching quota: \(mergedData.count) bytes")
        } else {
            syncWarning = nil
        }
    }
}
