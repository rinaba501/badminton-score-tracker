//
//  AppStore.swift
//  badminton score tracker (iOS)
//
//  Cached, decoded roster and history for the iPhone companion app. Views read
//  @Published arrays instead of calling PersistenceStore.decode* on every
//  render. A KV-only port of the Watch App's AppStore: the iOS app v1 has no
//  CloudKit path, so the targeted applyRemote*/persist helpers are dropped and
//  every save goes through the KV store via CloudSyncManager.pushToCloud.
//

import Foundation
import SwiftUI
import BadmintonCore

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published private(set) var roster: [Player]
    @Published private(set) var history: [MatchRecord]

    @AppStorage(AppStorageKeys.localPlayerId) private var localPlayerIdString: String = ""

    /// A stable identity for the local user, independent of their display
    /// name (which can be renamed) and independent of the roster ("me" is
    /// deliberately never added there — see `Player.shouldBeStoredAsSavedPlayer`).
    /// `localPlayerId` is a synced scalar, so the phone adopts the Watch's id on
    /// first pull, keeping the "Me"/iWon perspective consistent across devices.
    var localPlayerId: UUID {
        if let existing = UUID(uuidString: localPlayerIdString) { return existing }
        let new = UUID()
        localPlayerIdString = new.uuidString
        return new
    }

    private init() {
        Self.runMigrations()
        let r = UserDefaults.standard.data(forKey: AppStorageKeys.playerRoster) ?? Data()
        let h = UserDefaults.standard.data(forKey: AppStorageKeys.matchHistory) ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
    }

    // Upgrades on-disk data to the current schema before the first decode.
    // The designated place for future schema migrations (see PersistenceStore).
    private static func runMigrations() {
        if let data = UserDefaults.standard.data(forKey: AppStorageKeys.playerRoster),
           let migrated = PersistenceStore.migratedRosterData(from: data) {
            UserDefaults.standard.set(migrated, forKey: AppStorageKeys.playerRoster)
        }
        if let data = UserDefaults.standard.data(forKey: AppStorageKeys.matchHistory),
           let migrated = PersistenceStore.migratedHistoryData(from: data) {
            UserDefaults.standard.set(migrated, forKey: AppStorageKeys.matchHistory)
        }
    }

    // Each save updates the local cache + UserDefaults, then pushes to the KV
    // store. The iPhone is a real second writer to the shared bucket.
    func saveRoster(_ players: [Player]) {
        guard let encoded = PersistenceStore.encodeRoster(players) else { return }
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.playerRoster)
        roster = players
        CloudSyncManager.shared.pushToCloud()
    }

    func saveHistory(_ records: [MatchRecord]) {
        guard let encoded = PersistenceStore.encodeHistory(records) else { return }
        // A deletion must push as an authoritative overwrite, not merge —
        // merging would silently resurrect the removed record(s) from iCloud's
        // still-unshrunk copy. This is the same resurrection-bug guard the Watch
        // uses, now exercised with two real writers (see PersistenceStore.isHistoryShrink).
        let isShrink = PersistenceStore.isHistoryShrink(from: history, to: records)
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.matchHistory)
        history = records
        CloudSyncManager.shared.pushToCloud(overwriteHistory: isShrink)
    }

    func clearHistory() {
        UserDefaults.standard.set(Data(), forKey: AppStorageKeys.matchHistory)
        history = []
        CloudSyncManager.shared.pushToCloud(overwriteHistory: true)
    }

    // Called by CloudSyncManager after external iCloud data lands in UserDefaults.
    func reloadFromStorage() {
        let r = UserDefaults.standard.data(forKey: AppStorageKeys.playerRoster) ?? Data()
        let h = UserDefaults.standard.data(forKey: AppStorageKeys.matchHistory) ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
    }
}
