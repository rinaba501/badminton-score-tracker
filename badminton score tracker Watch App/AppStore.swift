//
//  AppStore.swift
//  badminton score tracker Watch App
//
//  Cached, decoded roster and history. Views read @Published arrays instead
//  of calling PersistenceStore.decode* on every render.
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
    /// Generated once on first access and persisted thereafter.
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

    // Each save updates the local cache + UserDefaults, then syncs. When
    // CloudKit owns history/roster it gets precise per-record upserts/deletes;
    // CloudSyncManager.pushToCloud is still called either way — it carries the
    // scalar settings, and (only when CloudKit is disabled) the history/roster
    // blobs as the fallback. See CloudSyncManager for how it skips the data
    // blobs when CloudKit is enabled.
    func saveRoster(_ players: [Player]) {
        guard let encoded = PersistenceStore.encodeRoster(players) else { return }
        let diff = PersistenceStore.diffRoster(from: roster, to: players)
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.playerRoster)
        roster = players
        if CloudKitSyncManager.isEnabled {
            CloudKitSyncManager.shared.enqueueRosterChanges(upsertedIds: diff.upsertedIds, deletedIds: diff.deletedIds)
        }
        CloudSyncManager.shared.pushToCloud()
    }

    func saveHistory(_ records: [MatchRecord]) {
        guard let encoded = PersistenceStore.encodeHistory(records) else { return }
        // Compute both against the OLD `history` before reassigning it.
        let diff = PersistenceStore.diffHistory(from: history, to: records)
        // KV fallback only: a deletion must push as an authoritative overwrite,
        // not merge — merging would silently resurrect the removed record(s)
        // from iCloud's still-unshrunk copy. The CloudKit path deletes per
        // record instead (below), so it has no such hazard.
        let isShrink = PersistenceStore.isHistoryShrink(from: history, to: records)
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.matchHistory)
        history = records
        if CloudKitSyncManager.isEnabled {
            CloudKitSyncManager.shared.enqueueHistoryChanges(upsertedIds: diff.upsertedIds, deletedIds: diff.deletedIds)
        }
        CloudSyncManager.shared.pushToCloud(overwriteHistory: isShrink)
    }

    func clearHistory() {
        let diff = PersistenceStore.diffHistory(from: history, to: [])
        UserDefaults.standard.set(Data(), forKey: AppStorageKeys.matchHistory)
        history = []
        if CloudKitSyncManager.isEnabled {
            CloudKitSyncManager.shared.enqueueHistoryChanges(upsertedIds: [], deletedIds: diff.deletedIds)
        }
        CloudSyncManager.shared.pushToCloud(overwriteHistory: true)
    }

    // Called by CloudSyncManager after external iCloud data lands in UserDefaults
    // (KV path). The CloudKit path uses the targeted apply* methods below instead.
    func reloadFromStorage() {
        let r = UserDefaults.standard.data(forKey: AppStorageKeys.playerRoster) ?? Data()
        let h = UserDefaults.standard.data(forKey: AppStorageKeys.matchHistory) ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
    }

    // MARK: - CloudKit apply (called by CloudKitSyncManager)

    /// Merge remotely-fetched records into the caches by id and persist to the
    /// UserDefaults cache. Targeted (per id) rather than a full re-decode so a
    /// fetch landing mid-edit doesn't clobber an unrelated local change. History
    /// stays date-sorted; roster keeps its stored order (updates in place,
    /// appends new).
    func applyRemoteUpsert(records: [MatchRecord], players: [Player]) {
        if !records.isEmpty {
            var byId = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for record in records { byId[record.id] = record }
            history = byId.values.sorted { $0.date < $1.date }
            persist(history: history)
        }
        if !players.isEmpty {
            var updated = roster
            var indexById = Dictionary(roster.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for player in players {
                if let idx = indexById[player.id] {
                    updated[idx] = player
                } else {
                    indexById[player.id] = updated.count
                    updated.append(player)
                }
            }
            roster = updated
            persist(roster: roster)
        }
    }

    /// Remove remotely-deleted records by id from the caches and persist.
    func applyRemoteDeletions(recordIds: [UUID], playerIds: [UUID]) {
        if !recordIds.isEmpty {
            let removed = Set(recordIds)
            history = history.filter { !removed.contains($0.id) }
            persist(history: history)
        }
        if !playerIds.isEmpty {
            let removed = Set(playerIds)
            roster = roster.filter { !removed.contains($0.id) }
            persist(roster: roster)
        }
    }

    private func persist(history records: [MatchRecord]) {
        if let encoded = PersistenceStore.encodeHistory(records) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.matchHistory)
        }
    }

    private func persist(roster players: [Player]) {
        if let encoded = PersistenceStore.encodeRoster(players) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.playerRoster)
        }
    }
}
