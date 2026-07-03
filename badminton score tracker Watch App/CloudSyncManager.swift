import Foundation
import Combine
import BadmintonCore

// Keys synced to iCloud key-value store. The key strings themselves live in
// BadmintonCore.AppStorageKeys; this list selects WHICH of them sync
// (matchMyName/matchOpponentName/playerSortOrder/gameMode intentionally
// do not — they are per-device state).
private enum SyncKeys {
    static let playerRoster = AppStorageKeys.playerRoster
    static let matchHistory = AppStorageKeys.matchHistory
    static let all: [String] = [
        AppStorageKeys.playerRoster,
        AppStorageKeys.matchHistory,
        AppStorageKeys.myName,
        AppStorageKeys.pointsToWin,
        AppStorageKeys.gamesInMatch,
        AppStorageKeys.courtTheme,
        AppStorageKeys.announceScore,
        AppStorageKeys.enableSounds,
        AppStorageKeys.enableCrownScoring,
        AppStorageKeys.timeModeEnabled,
        AppStorageKeys.timeLimitMinutes
    ]
}

@MainActor
final class CloudSyncManager: ObservableObject {
    static let shared = CloudSyncManager()

    private let kvStore = NSUbiquitousKeyValueStore.default
    private var cancellables = Set<AnyCancellable>()

    private init() {}

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
        for key in SyncKeys.all where key != SyncKeys.matchHistory {
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
        for key in SyncKeys.all where key != SyncKeys.matchHistory {
            if let value = kvStore.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
        syncHistory()
        AppStore.shared.reloadFromStorage()
    }

    @objc private func externalChange(_ notification: Notification) {
        guard let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return }
        // Only pull on server change or initial sync — not on quota exceeded
        guard reason == NSUbiquitousKeyValueStoreServerChange ||
              reason == NSUbiquitousKeyValueStoreInitialSyncChange else { return }

        var dataKeysChanged = false
        if let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
            let defaults = UserDefaults.standard
            for key in changedKeys where key != SyncKeys.matchHistory {
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
    }
}
