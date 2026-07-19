//
//  SupabaseSyncEngine.swift
//  badminton score tracker Watch App
//
//  Roadmap Phase 9c: the SyncEngine conformer AppStore swaps to when a
//  device opts into the Supabase backend (see AppStore.swift's syncEngine
//  property). Thin adapter over CloudSyncSpike's SupabaseSyncManager (the
//  low-level Supabase transport, which cannot import AppStore itself since
//  it lives in a shared package) — reads AppStore.shared's live roster/
//  history by id and re-encodes via PersistenceStore, the same "materialize
//  fresh from the live cache" pattern CloudKitSyncManager's own
//  materializeRecord already uses. Settings construction itself lives on
//  AppStore (AppStore.currentSettingsSnapshot()) since CloudKitSyncManager
//  needs the identical logic — one shared copy per target instead of one
//  per sync engine.
//
//  Only the personal-data tier (settings + personal players/match_records)
//  is real — clubs/challenges/reactions/friends-* stay no-ops here until
//  9d/9e migrate them, matching BadmintonCore.NoOpSyncEngine's shape.
//

import Foundation
import BadmintonCore
import CloudSyncSpike

@MainActor
final class SupabaseSyncEngine: SyncEngine {
    static let shared = SupabaseSyncEngine()

    private let manager = SupabaseSyncManager.shared

    /// Every enqueue* call chains onto this rather than spawning an
    /// independent Task, so writes apply in call order — two saves in quick
    /// succession would otherwise race, with the older write's network
    /// response landing after the newer one's and silently overwriting it.
    private var pendingWork: Task<Void, Never>?

    private init() {}

    private func enqueueWork(_ work: @escaping () async -> Void) {
        let previous = pendingWork
        pendingWork = Task {
            _ = await previous?.value
            await work()
        }
    }

    func enqueueRosterChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID?]) {
        enqueueWork { [self] in
            guard let ownerId = await manager.currentUserId() else { return }
            let items = upsertedIds.compactMap { id -> PendingRecord? in
                guard let player = AppStore.shared.roster.first(where: { $0.id == id }),
                      let payload = PersistenceStore.encodePlayer(player) else { return nil }
                return PendingRecord(id: id, ownerId: ownerId, clubId: player.clubId, payload: payload)
            }
            if !items.isEmpty {
                await manager.upsertPlayers(items)
            }
            if !deletedIds.isEmpty {
                await manager.deletePlayers(ids: Array(deletedIds.keys))
            }
        }
    }

    func enqueueHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID?]) {
        enqueueWork { [self] in
            guard let ownerId = await manager.currentUserId() else { return }
            let items = upsertedIds.compactMap { id -> PendingRecord? in
                guard let record = AppStore.shared.history.first(where: { $0.id == id }),
                      let payload = PersistenceStore.encodeRecord(record) else { return nil }
                return PendingRecord(id: id, ownerId: ownerId, clubId: record.clubId, payload: payload)
            }
            if !items.isEmpty {
                await manager.upsertMatchRecords(items)
            }
            if !deletedIds.isEmpty {
                await manager.deleteMatchRecords(ids: Array(deletedIds.keys))
            }
        }
    }

    func enqueueSettingsChange() {
        enqueueWork { [self] in
            guard let ownerId = await manager.currentUserId(),
                  let payload = PersistenceStore.encodeSettingsSnapshot(AppStore.shared.currentSettingsSnapshot()) else { return }
            await manager.upsertSettings(ownerId: ownerId, payload: payload)
        }
    }

    // MARK: - Not yet migrated (Phase 9d club data, 9e Friends graph)

    func enqueueClubChanges(upsertedIds: [UUID], deletedIds: [UUID: String?]) {}
    func enqueueChallengeChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID]) {}
    func enqueueReactionChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID]) {}
    func enqueueFriendsRosterChanges(upsertedIds: [UUID], deletedIds: [UUID]) {}
    func enqueueFriendsHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID]) {}
    func enqueueFriendIdentityChange() {}
    func removeFriendIdentityRecord() {}
    func enqueueFriendStatsChange() {}
    func deleteFriendsHistoryZone() async {}
    func deleteMyFriendProfile() async {}
    func deleteAllMyFriendRequests() async {}
}
