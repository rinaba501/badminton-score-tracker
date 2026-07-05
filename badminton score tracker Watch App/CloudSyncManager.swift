import Foundation
import Combine
import SwiftUI
import os
import BadmintonCore

/// Non-blocking status surfaced when the iCloud KV store is close to (or has
/// hit) its ~1 MB quota. This is a stopgap ahead of Phase 4's CloudKit
/// migration (#109), not a full replacement for it.
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
// do not — they are per-device state).
private enum SyncKeys {
    static let playerRoster = AppStorageKeys.playerRoster
    static let matchHistory = AppStorageKeys.matchHistory
    // Scalar settings — always synced via the KV store, even once CloudKit owns
    // history + roster (they're tiny and never approach the ~1 MB quota).
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
    private var cancellables = Set<AnyCancellable>()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "badminton-score-tracker", category: "CloudSync")

    /// Set from `syncHistory()` (recomputed on every push/pull) and escalated
    /// by `externalChange(_:)` on an actual quota violation. `SettingsView`
    /// observes this to show a passive, non-blocking warning.
    @Published private(set) var syncWarning: CloudSyncWarning?

    private init() {}

    // When CloudKit owns history + roster (the flag is on), the KV store carries
    // scalar settings only. Default-off, so this is `true` today and every path
    // below behaves exactly as before.
    private var kvOwnsData: Bool { !CloudKitSyncManager.isEnabled }

    // Non-history keys the KV store pushes/pulls directly. Roster is a blob
    // treated like a scalar here (history is merged separately); it drops out
    // once CloudKit owns it.
    private var directKeys: [String] {
        kvOwnsData ? SyncKeys.scalars + [SyncKeys.playerRoster] : SyncKeys.scalars
    }

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
        if kvOwnsData {
            if overwriteHistory {
                let localData = defaults.data(forKey: SyncKeys.matchHistory) ?? Data()
                kvStore.set(localData, forKey: SyncKeys.matchHistory)
            } else {
                syncHistory()
            }
            AppStore.shared.reloadFromStorage()
        }
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
        if kvOwnsData {
            syncHistory()
            AppStore.shared.reloadFromStorage()
        }
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
            if kvOwnsData && changedKeys.contains(SyncKeys.matchHistory) {
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
