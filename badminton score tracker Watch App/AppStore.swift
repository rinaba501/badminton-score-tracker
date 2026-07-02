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
        UserDefaults.standard.set(encoded, forKey: "matchHistory")
        history = records
        CloudSyncManager.shared.pushToCloud()
    }

    func clearHistory() {
        UserDefaults.standard.set(Data(), forKey: "matchHistory")
        history = []
        CloudSyncManager.shared.pushToCloud()
    }

    // Called by CloudSyncManager after external iCloud data lands in UserDefaults
    func reloadFromStorage() {
        let r = UserDefaults.standard.data(forKey: "playerRoster") ?? Data()
        let h = UserDefaults.standard.data(forKey: "matchHistory") ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
    }
}
