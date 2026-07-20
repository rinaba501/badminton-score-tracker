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
//  The personal-data tier (settings + personal players/match_records) and,
//  as of Phase 9d, clubs/challenges/reactions are real — friends-* stay
//  no-ops here until 9e migrates them, matching BadmintonCore.NoOpSyncEngine's
//  shape.
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

    private static let pullTables = ["players", "match_records", "settings", "clubs", "challenges", "reactions"]

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
                    await SupabaseSyncEngine.shared.handleRemoteChange(change)
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
        var clubs: [Club] = []
        for change in await manager.fetchAllRows(table: "clubs") {
            guard let payload = change.payload, var club = PersistenceStore.decodeClub(payload) else { continue }
            club.ownerRecordName = await ownerRecordName(for: change.ownerId)
            clubs.append(club)
        }
        if !clubs.isEmpty {
            AppStore.shared.applyRemoteUpsert(records: [], players: [], clubs: clubs)
        }
        let challengeChanges = await manager.fetchAllRows(table: "challenges")
        let challenges = challengeChanges.compactMap { $0.payload.flatMap(PersistenceStore.decodeChallenge) }
        if !challenges.isEmpty {
            AppStore.shared.applyRemoteUpsert(records: [], players: [], clubs: [], challenges: challenges)
        }
        let reactionChanges = await manager.fetchAllRows(table: "reactions")
        let reactions = reactionChanges.compactMap { $0.payload.flatMap(PersistenceStore.decodeReaction) }
        if !reactions.isEmpty {
            AppStore.shared.applyRemoteUpsert(records: [], players: [], clubs: [], reactions: reactions)
        }
        if let settingsChange = await manager.fetchSettings(),
           let payload = settingsChange.payload,
           let snapshot = PersistenceStore.decodeSettingsSnapshot(payload) {
            AppStore.shared.applyRemoteSettings(snapshot)
        }
    }

    /// A club's payload always encodes `ownerRecordName` as `nil` from its
    /// owner's point of view (they ARE the owner) — a receiving member must
    /// not adopt that as-is, or every device would think it owns every club
    /// it sees. Backfilled instead from the row's actual `owner_id` column
    /// (`RemoteChange.ownerId`), mirroring how CloudKitSyncManager backfills
    /// the same field from `CKRecord.recordID.zoneID.ownerName`.
    private func ownerRecordName(for ownerId: UUID?) async -> String? {
        guard let ownerId else { return nil }
        let myId = await manager.currentUserId()
        return ownerId == myId ? nil : ownerId.uuidString
    }

    /// The Realtime callback. Self-echoes (this same device's own push
    /// coming back through the subscription) are expected and harmless —
    /// applyRemoteUpsert/applyRemoteDeletions merge by id, so re-applying an
    /// unchanged row is just a redundant no-op write, the same tolerance
    /// CloudKit's own local-echo path already relies on.
    private func handleRemoteChange(_ change: RemoteChange) async {
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
            case "clubs":
                guard var club = PersistenceStore.decodeClub(payload) else { return }
                club.ownerRecordName = await ownerRecordName(for: change.ownerId)
                AppStore.shared.applyRemoteUpsert(records: [], players: [], clubs: [club])
            case "challenges":
                guard let challenge = PersistenceStore.decodeChallenge(payload) else { return }
                AppStore.shared.applyRemoteUpsert(records: [], players: [], clubs: [], challenges: [challenge])
            case "reactions":
                guard let reaction = PersistenceStore.decodeReaction(payload) else { return }
                AppStore.shared.applyRemoteUpsert(records: [], players: [], clubs: [], reactions: [reaction])
            default:
                break
            }
        case .delete:
            switch change.table {
            case "players":
                AppStore.shared.applyRemoteDeletions(recordIds: [], playerIds: [change.id], clubIds: [])
            case "match_records":
                AppStore.shared.applyRemoteDeletions(recordIds: [change.id], playerIds: [], clubIds: [])
            case "clubs":
                AppStore.shared.applyRemoteDeletions(recordIds: [], playerIds: [], clubIds: [change.id])
            case "challenges":
                AppStore.shared.applyRemoteDeletions(recordIds: [], playerIds: [], clubIds: [], challengeIds: [change.id])
            case "reactions":
                AppStore.shared.applyRemoteDeletions(recordIds: [], playerIds: [], clubIds: [], reactionIds: [change.id])
            default:
                break
            }
        }
    }

    // MARK: - Club data push (Phase 9d)

    /// Skips any club this device doesn't own (`ownerRecordName != nil`) —
    /// Supabase's `clubs_update`/`clubs_delete` RLS is owner-only (a
    /// deliberate 9a tightening vs. CloudKit's permissive shared zone), so a
    /// non-owner's write would silently no-op anyway; skipping it here is
    /// just cleaner, not a correctness requirement.
    func enqueueClubChanges(upsertedIds: [UUID], deletedIds: [UUID: String?]) {
        enqueueWork { [self] in
            guard let ownerId = await manager.currentUserId() else { return }
            let items = upsertedIds.compactMap { id -> ClubPendingRecord? in
                guard let club = AppStore.shared.clubs.first(where: { $0.id == id }),
                      club.ownerRecordName == nil,
                      let payload = PersistenceStore.encodeClub(club) else { return nil }
                return ClubPendingRecord(id: id, ownerId: ownerId, payload: payload)
            }
            if !items.isEmpty {
                await manager.upsertClubs(items)
            }
            if !deletedIds.isEmpty {
                await manager.deleteClubs(ids: Array(deletedIds.keys))
            }
        }
    }

    /// `ChallengeRecord.fromParticipantId`/`toParticipantId` are opaque
    /// strings — under Supabase they hold this account's `auth.uid()`
    /// string (see the Phase 9d plan's participant-id resolution note), so
    /// they parse straight to `UUID`. A challenge created while this device
    /// was CloudKit-active would hold a CKShare participant record name
    /// instead, which fails to parse as a UUID — `compactMap` just drops
    /// that item rather than crashing; cross-backend migration of
    /// in-flight challenges is out of scope here (9f handles cutover).
    func enqueueChallengeChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID]) {
        enqueueWork { [self] in
            let items = upsertedIds.compactMap { id -> ChallengePendingRecord? in
                guard let challenge = AppStore.shared.challenges.first(where: { $0.id == id }),
                      let fromId = UUID(uuidString: challenge.fromParticipantId),
                      let toId = UUID(uuidString: challenge.toParticipantId),
                      let payload = PersistenceStore.encodeChallenge(challenge) else { return nil }
                return ChallengePendingRecord(
                    id: id, clubId: challenge.clubId,
                    fromParticipantId: fromId, toParticipantId: toId, payload: payload
                )
            }
            if !items.isEmpty {
                await manager.upsertChallenges(items)
            }
            if !deletedIds.isEmpty {
                await manager.deleteChallenges(ids: Array(deletedIds.keys))
            }
        }
    }

    /// Same opaque-string-holds-auth.uid() reasoning as challenges, for
    /// `ReactionRecord.authorParticipantId`.
    func enqueueReactionChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID]) {
        enqueueWork { [self] in
            let items = upsertedIds.compactMap { id -> ReactionPendingRecord? in
                guard let reaction = AppStore.shared.reactions.first(where: { $0.id == id }),
                      let authorId = UUID(uuidString: reaction.authorParticipantId),
                      let payload = PersistenceStore.encodeReaction(reaction) else { return nil }
                return ReactionPendingRecord(
                    id: id, clubId: reaction.clubId, matchId: reaction.matchId,
                    authorId: authorId, payload: payload
                )
            }
            if !items.isEmpty {
                await manager.upsertReactions(items)
            }
            if !deletedIds.isEmpty {
                await manager.deleteReactions(ids: Array(deletedIds.keys))
            }
        }
    }

    // MARK: - Not yet migrated (Phase 9e Friends graph)

    func enqueueFriendsRosterChanges(upsertedIds: [UUID], deletedIds: [UUID]) {}
    func enqueueFriendsHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID]) {}
    func enqueueFriendIdentityChange() {}
    func removeFriendIdentityRecord() {}
    func enqueueFriendStatsChange() {}
    func deleteFriendsHistoryZone() async {}
    func deleteMyFriendProfile() async {}
    func deleteAllMyFriendRequests() async {}
}
