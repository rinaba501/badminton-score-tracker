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

    // MARK: - Pull-side sync (Phase 9c-6)
    //
    // Everything above only pushes local changes out. This is the read-back
    // half: activateSupabaseSync() and app launch (badminton_score_trackerApp.swift)
    // both call startIfActive(), which does a one-time catch-up read of
    // every row this account already owns remotely, then opens a Realtime
    // subscription for anything that changes afterward — mirroring
    // CKSyncEngine's own fetchChanges()-on-reconnect-plus-push-notifications
    // shape. Routed through enqueueWork like every push method, so a fresh
    // activation's migration-on-signin upload finishes before the catch-up
    // pull runs, rather than racing it.

    private static let pullTables = ["players", "match_records", "settings"]

    /// Deliberately does NOT gate on `manager.isSignedIn` — that flag is only
    /// set by `signInWithGoogle`/`adoptRelayedSession`, so it's still `false`
    /// on a cold relaunch even though the Supabase SDK auto-restores a
    /// persisted session from Keychain on demand. `pullInitialState()`/
    /// `startRealtimeSync` each independently no-op (and log) if
    /// `currentUserId()` comes back nil, so it's safe to call this
    /// unconditionally — including at launch, for a device that's never
    /// linked Supabase at all, where every downstream call quietly does
    /// nothing.
    func startIfActive() {
        enqueueWork { [self] in
            await pullInitialState()
            await manager.startRealtimeSync(tables: Self.pullTables) { change in
                Task { @MainActor in
                    SupabaseSyncEngine.shared.handleRemoteChange(change)
                }
            }
        }
    }

    /// Called from deactivateSupabaseSync() — also routed through
    /// enqueueWork so it can't race a startIfActive() still in flight.
    func stopRealtimeSync() {
        enqueueWork { [self] in
            await manager.stopRealtimeSync()
        }
    }

    private func pullInitialState() async {
        let playerChanges = await manager.fetchAllRows(table: "players")
        let players = playerChanges.compactMap { $0.payload.flatMap(PersistenceStore.decodePlayer) }
        if !players.isEmpty {
            AppStore.shared.applyRemoteUpsert(records: [], players: players, clubs: [])
        }
        let recordChanges = await manager.fetchAllRows(table: "match_records")
        let records = recordChanges.compactMap { $0.payload.flatMap(PersistenceStore.decodeRecord) }
        if !records.isEmpty {
            AppStore.shared.applyRemoteUpsert(records: records, players: [], clubs: [])
        }
        if let settingsChange = await manager.fetchSettings(),
           let payload = settingsChange.payload,
           let snapshot = PersistenceStore.decodeSettingsSnapshot(payload) {
            AppStore.shared.applyRemoteSettings(snapshot)
        }
    }

    /// The Realtime callback. Self-echoes (this same device's own push
    /// coming back through the subscription) are expected and harmless —
    /// applyRemoteUpsert/applyRemoteDeletions merge by id, so re-applying an
    /// unchanged row is just a redundant no-op write, the same tolerance
    /// CloudKit's own local-echo path already relies on.
    private func handleRemoteChange(_ change: RemoteChange) {
        switch change.kind {
        case .upsert:
            guard let payload = change.payload else { return }
            switch change.table {
            case "players":
                guard let player = PersistenceStore.decodePlayer(payload) else { return }
                AppStore.shared.applyRemoteUpsert(records: [], players: [player], clubs: [])
            case "match_records":
                guard let record = PersistenceStore.decodeRecord(payload) else { return }
                AppStore.shared.applyRemoteUpsert(records: [record], players: [], clubs: [])
            case "settings":
                guard let snapshot = PersistenceStore.decodeSettingsSnapshot(payload) else { return }
                AppStore.shared.applyRemoteSettings(snapshot)
            default:
                break
            }
        case .delete:
            switch change.table {
            case "players":
                AppStore.shared.applyRemoteDeletions(recordIds: [], playerIds: [change.id], clubIds: [])
            case "match_records":
                AppStore.shared.applyRemoteDeletions(recordIds: [change.id], playerIds: [], clubIds: [])
            default:
                break
            }
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
