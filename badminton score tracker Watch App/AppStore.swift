//
//  AppStore.swift
//  badminton score tracker Watch App
//
//  Cached, decoded roster and history. Views read @Published arrays instead
//  of calling PersistenceStore.decode* on every render.
//

import Foundation

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published private(set) var roster: [Player]
    @Published private(set) var history: [MatchRecord]

    private init() {
        let r = UserDefaults.standard.data(forKey: "playerRoster") ?? Data()
        let h = UserDefaults.standard.data(forKey: "matchHistory") ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
    }

    func saveRoster(_ players: [Player]) {
        guard let encoded = PersistenceStore.encodeRoster(players) else { return }
        UserDefaults.standard.set(encoded, forKey: "playerRoster")
        roster = players
        CloudSyncManager.shared.pushToCloud()
    }

    func saveHistory(_ records: [MatchRecord]) {
        guard let encoded = PersistenceStore.encodeHistory(records) else { return }
        // A deletion (single record or "clear all") must push as an
        // authoritative overwrite, not merge — merging would silently
        // resurrect the record(s) being removed from iCloud's still-unshrunk
        // copy. Appends and in-place edits (e.g. a rename) are unaffected and
        // still merge safely.
        let isShrink = PersistenceStore.isHistoryShrink(from: history, to: records)
        UserDefaults.standard.set(encoded, forKey: "matchHistory")
        history = records
        CloudSyncManager.shared.pushToCloud(overwriteHistory: isShrink)
    }

    func clearHistory() {
        UserDefaults.standard.set(Data(), forKey: "matchHistory")
        history = []
        CloudSyncManager.shared.pushToCloud(overwriteHistory: true)
    }

    // Called by CloudSyncManager after external iCloud data lands in UserDefaults
    func reloadFromStorage() {
        let r = UserDefaults.standard.data(forKey: "playerRoster") ?? Data()
        let h = UserDefaults.standard.data(forKey: "matchHistory") ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
    }
}
