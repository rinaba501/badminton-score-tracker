import Foundation
import Combine

// Keys synced to iCloud key-value store
private enum SyncKey: String, CaseIterable {
    case playerRoster
    case matchHistory
    case myName
    case pointsToWin
    case gamesInMatch
    case courtTheme
    case announceScore
    case enableSounds
    case enableCrownScoring
    case timeModeEnabled
    case timeLimitMinutes
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

    // Push all local UserDefaults values to iCloud
    func pushToCloud() {
        let defaults = UserDefaults.standard
        for key in SyncKey.allCases {
            if let value = defaults.object(forKey: key.rawValue) {
                kvStore.set(value, forKey: key.rawValue)
            }
        }
        kvStore.synchronize()
    }

    // Pull iCloud values into UserDefaults, only overwriting if iCloud has data
    private func pullFromCloud() {
        let defaults = UserDefaults.standard
        for key in SyncKey.allCases {
            if let value = kvStore.object(forKey: key.rawValue) {
                defaults.set(value, forKey: key.rawValue)
            }
        }
    }

    @objc private func externalChange(_ notification: Notification) {
        guard let reason = notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int else { return }
        // Only pull on server change or initial sync — not on quota exceeded
        guard reason == NSUbiquitousKeyValueStoreServerChange ||
              reason == NSUbiquitousKeyValueStoreInitialSyncChange else { return }

        if let changedKeys = notification.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] {
            let defaults = UserDefaults.standard
            for key in changedKeys {
                if let value = kvStore.object(forKey: key) {
                    defaults.set(value, forKey: key)
                }
            }
        }
    }
}
