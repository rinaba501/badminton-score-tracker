//
//  SupabaseSyncEngine.swift
//  badminton score tracker Watch App
//
//  The SyncEngine conformer AppStore swaps to when a device opts into the
//  Supabase backend (see AppStore.swift's syncEngine property). Thin
//  adapter over CloudSyncSpike's SupabaseSyncManager (the low-level
//  Supabase transport, which cannot import AppStore itself since it lives
//  in a shared package) — reads AppStore.shared's live roster/history by id
//  and re-encodes via PersistenceStore, materializing each record fresh
//  from the live cache rather than caching a copy of its own. Settings
//  construction lives on AppStore (AppStore.currentSettingsSnapshot())
//  since this is the one place that needs it.
//
//  Every table is real: the personal-data tier (settings + personal
//  players/match_records), clubs/challenges/reactions, and the Friends
//  graph (FriendProfile/FriendRequest push+pull, identity/stats sharing,
//  history sharing). `enqueueFriendsRosterChanges`/
//  `enqueueFriendsHistoryChanges` stay permanent no-ops by design (see their
//  own doc comment below) — everything else this protocol declares has a
//  real implementation.
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
    // subscription for anything that changes afterward. Routed through
    // enqueueWork like every push method, so a fresh activation's
    // migration-on-signin upload finishes before the catch-up pull runs,
    // rather than racing it. Also upserts this device's own `profiles` row
    // on every call, so ClubDetailView's member list has *a* display name to
    // show. Also caches `currentUserId()` into
    // `AppStorageKeys.myParticipantId` — `AppStore.friends` reads that key
    // directly rather than going through `SyncEngine`, and without this call
    // it would never get populated, so `AppStore.friends` would silently
    // stay empty forever.

    private static let pullTables = [
        "players", "match_records", "settings", "clubs", "challenges", "reactions",
        "friend_requests", "friend_identity_snapshots", "friend_stats_snapshots", "match_invites"
    ]

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
            let displayName = Player.displayName(for: AppStore.shared.currentSettingsSnapshot().myName)
            await manager.upsertMyProfile(displayName: displayName)
            if let uid = await manager.currentUserId() {
                UserDefaults.standard.set(uid.uuidString, forKey: AppStorageKeys.myParticipantId)
            }
            // Same rationale as upsertMyProfile above: avatar mirrors
            // unconditionally now (Roadmap issue #272), so a device that has
            // never touched gender/birthday/introduction toggles still gets
            // its avatar mirrored as soon as it's signed in, not only after
            // the next roster edit.
            AppStore.shared.refreshMyIdentitySnapshot()
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
        let myId = await manager.currentUserId()
        var personalPlayers: [Player] = []
        var friendPlayersByOwner: [UUID: [Player]] = [:]
        for change in await manager.fetchAllRows(table: "players") {
            guard let payload = change.payload, let player = PersistenceStore.decodePlayer(payload) else { continue }
            if isPersonalOrClubRow(clubId: player.clubId, ownerId: change.ownerId, myId: myId) {
                personalPlayers.append(player)
            } else if let ownerId = change.ownerId {
                friendPlayersByOwner[ownerId, default: []].append(player)
            }
        }
        if !personalPlayers.isEmpty {
            AppStore.shared.applyRemoteUpsert(records: [], players: personalPlayers, clubs: [])
        }
        for (ownerId, players) in friendPlayersByOwner {
            AppStore.shared.applyRemoteFriendActivity(participantId: ownerId.uuidString, matches: [], players: players)
        }

        var personalRecords: [MatchRecord] = []
        var friendRecordsByOwner: [UUID: [MatchRecord]] = [:]
        for change in await manager.fetchAllRows(table: "match_records") {
            guard let payload = change.payload, let record = PersistenceStore.decodeRecord(payload) else { continue }
            if isPersonalOrClubRow(clubId: record.clubId, ownerId: change.ownerId, myId: myId) {
                personalRecords.append(record)
            } else if let ownerId = change.ownerId {
                friendRecordsByOwner[ownerId, default: []].append(record)
            }
        }
        if !personalRecords.isEmpty {
            AppStore.shared.applyRemoteUpsert(records: personalRecords, players: [], clubs: [])
        }
        for (ownerId, records) in friendRecordsByOwner {
            AppStore.shared.applyRemoteFriendActivity(participantId: ownerId.uuidString, matches: records, players: [])
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
        await refreshFriendRequests()
        await refreshMatchInvites()
        for change in await manager.fetchAllRows(table: "friend_identity_snapshots") where change.id != myId {
            guard let payload = change.payload, var identity = PersistenceStore.decodeFriendIdentitySnapshot(payload) else { continue }
            identity.displayName = displayName(forFriendParticipant: change.id)
            AppStore.shared.applyRemoteFriendIdentity(participantId: change.id.uuidString, snapshot: identity)
        }
        for change in await manager.fetchAllRows(table: "friend_stats_snapshots") where change.id != myId {
            guard let payload = change.payload, var stats = PersistenceStore.decodeFriendStatsSnapshot(payload) else { continue }
            stats.displayName = displayName(forFriendParticipant: change.id)
            AppStore.shared.applyRemoteFriendStats(participantId: change.id.uuidString, snapshot: stats)
        }
    }

    /// A full reconcile rather than a per-id merge: `friend_requests` is
    /// always a small set, and `AppStore.saveFriendRequests` already expects
    /// "here is the complete current list" rather than an incremental diff.
    /// Re-running this on every Realtime event (any kind, including deletes —
    /// a delete's absence is just missing from the fresh result) avoids
    /// needing separate insert/update/delete handling for this one table.
    func refreshFriendRequests() async {
        let changes = await manager.fetchAllRows(table: "friend_requests")
        let requests = changes.compactMap { $0.payload.flatMap(PersistenceStore.decodeFriendRequest) }
        AppStore.shared.saveFriendRequests(requests)
    }

    /// Same full-reconcile shape as `refreshFriendRequests`, and for the same
    /// reason it's safe: `AppStore.saveMatchInvites` → `autoResolvePendingMatchInvites`
    /// is idempotent (guarded by each mirrored record's `sourceMatchId`), so
    /// re-running this on every Realtime event needs no per-kind branching.
    func refreshMatchInvites() async {
        let changes = await manager.fetchAllRows(table: "match_invites")
        let invites = changes.compactMap { $0.payload.flatMap(PersistenceStore.decodeMatchInvite) }
        AppStore.shared.saveMatchInvites(invites)
    }

    /// A club's payload always encodes `ownerRecordName` as `nil` from its
    /// owner's point of view (they ARE the owner) — a receiving member must
    /// not adopt that as-is, or every device would think it owns every club
    /// it sees. Backfilled instead from the row's actual `owner_id` column
    /// (`RemoteChange.ownerId`).
    private func ownerRecordName(for ownerId: UUID?) async -> String? {
        guard let ownerId else { return nil }
        let myId = await manager.currentUserId()
        return ownerId == myId ? nil : ownerId.uuidString
    }

    /// A `clubId == nil` row belongs in this device's own `roster`/`history`
    /// only when it's actually this account's row (or `ownerId` came back
    /// nil, the personal-push-echo case) — club-tagged rows always take this
    /// path too. Everything else is a `friend_can_view_history`-granted row:
    /// a friend's personal data, now visible via RLS but never to be merged
    /// into this device's own caches — see `applyRemoteFriendActivity`'s doc
    /// comment.
    private func isPersonalOrClubRow(clubId: UUID?, ownerId: UUID?, myId: UUID?) -> Bool {
        clubId != nil || ownerId == nil || ownerId == myId
    }

    /// The Realtime callback. Self-echoes (this same device's own push
    /// coming back through the subscription) are expected and harmless —
    /// applyRemoteUpsert/applyRemoteDeletions merge by id, so re-applying an
    /// unchanged row is just a redundant no-op write.
    private func handleRemoteChange(_ change: RemoteChange) async {
        // friend_requests/match_invites both reconcile as a full refetch
        // regardless of kind (see refreshFriendRequests's/refreshMatchInvites's
        // doc comments) rather than joining the per-kind/per-table switch below.
        guard change.table != "friend_requests" else {
            await refreshFriendRequests()
            return
        }
        guard change.table != "match_invites" else {
            await refreshMatchInvites()
            return
        }
        switch change.kind {
        case .upsert:
            guard let payload = change.payload else { return }
            switch change.table {
            case "players":
                guard let player = PersistenceStore.decodePlayer(payload) else { return }
                if isPersonalOrClubRow(clubId: player.clubId, ownerId: change.ownerId, myId: await manager.currentUserId()) {
                    AppStore.shared.applyRemoteUpsert(records: [], players: [player], clubs: [])
                } else if let ownerId = change.ownerId {
                    AppStore.shared.applyRemoteFriendActivity(participantId: ownerId.uuidString, matches: [], players: [player])
                }
            case "match_records":
                guard let record = PersistenceStore.decodeRecord(payload) else { return }
                if isPersonalOrClubRow(clubId: record.clubId, ownerId: change.ownerId, myId: await manager.currentUserId()) {
                    AppStore.shared.applyRemoteUpsert(records: [record], players: [], clubs: [])
                } else if let ownerId = change.ownerId {
                    AppStore.shared.applyRemoteFriendActivity(participantId: ownerId.uuidString, matches: [record], players: [])
                }
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
            case "friend_identity_snapshots":
                guard change.id != (await manager.currentUserId()),
                      var identity = PersistenceStore.decodeFriendIdentitySnapshot(payload) else { return }
                identity.displayName = displayName(forFriendParticipant: change.id)
                AppStore.shared.applyRemoteFriendIdentity(participantId: change.id.uuidString, snapshot: identity)
            case "friend_stats_snapshots":
                guard change.id != (await manager.currentUserId()),
                      var stats = PersistenceStore.decodeFriendStatsSnapshot(payload) else { return }
                stats.displayName = displayName(forFriendParticipant: change.id)
                AppStore.shared.applyRemoteFriendStats(participantId: change.id.uuidString, snapshot: stats)
            default:
                break
            }
        case .delete:
            switch change.table {
            case "players":
                if isPersonalOrClubRow(clubId: change.clubId, ownerId: change.ownerId, myId: await manager.currentUserId()) {
                    AppStore.shared.applyRemoteDeletions(recordIds: [], playerIds: [change.id], clubIds: [])
                } else if let ownerId = change.ownerId {
                    AppStore.shared.applyRemoteFriendActivityDeletions(participantId: ownerId.uuidString, matchIds: [], playerIds: [change.id])
                }
            case "match_records":
                if isPersonalOrClubRow(clubId: change.clubId, ownerId: change.ownerId, myId: await manager.currentUserId()) {
                    AppStore.shared.applyRemoteDeletions(recordIds: [change.id], playerIds: [], clubIds: [])
                } else if let ownerId = change.ownerId {
                    AppStore.shared.applyRemoteFriendActivityDeletions(participantId: ownerId.uuidString, matchIds: [change.id], playerIds: [])
                }
            case "clubs":
                AppStore.shared.applyRemoteDeletions(recordIds: [], playerIds: [], clubIds: [change.id])
            case "challenges":
                AppStore.shared.applyRemoteDeletions(recordIds: [], playerIds: [], clubIds: [], challengeIds: [change.id])
            case "reactions":
                AppStore.shared.applyRemoteDeletions(recordIds: [], playerIds: [], clubIds: [], reactionIds: [change.id])
            case "friend_identity_snapshots":
                AppStore.shared.applyRemoteFriendIdentityDeletion(participantId: change.id.uuidString)
            case "friend_stats_snapshots":
                AppStore.shared.applyRemoteFriendStatsDeletion(participantId: change.id.uuidString)
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
    /// strings holding this account's `auth.uid()` string, so they parse
    /// straight to `UUID`. Any challenge that somehow doesn't parse (e.g.
    /// stale pre-migration data) is just dropped by `compactMap` rather than
    /// crashing.
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

    // MARK: - Match invites (Phase 10a)

    /// Builds the invite from the just-saved `MatchRecord` in `AppStore.shared.history`
    /// (materialized fresh, same "read the live cache by id" pattern every
    /// other enqueue* method here uses) and pushes it — `SupabaseSyncManager.sendMatchInvite`
    /// upserts by `recordId`, so a later edit to the same match re-sends
    /// cleanly instead of creating a duplicate row.
    func enqueueMatchInvite(recordId: UUID, opponentParticipantId: String) {
        enqueueWork { [self] in
            guard let fromId = await manager.currentUserId(),
                  let toId = UUID(uuidString: opponentParticipantId),
                  let record = AppStore.shared.history.first(where: { $0.id == recordId }) else { return }
            let myName = Player.displayName(for: UserDefaults.standard.string(forKey: AppStorageKeys.myName) ?? Player.defaultMyName)
            let invite = SharedMatchInvite(
                id: recordId, fromParticipantId: fromId.uuidString, fromDisplayName: myName,
                toParticipantId: opponentParticipantId, matchSnapshot: record
            )
            guard let payload = PersistenceStore.encodeMatchInvite(invite) else { return }
            try? await manager.sendMatchInvite(recordId: recordId, fromParticipantId: fromId, toParticipantId: toId, payload: payload)
        }
    }

    /// The one push path for both `AppStore.autoResolvePendingMatchInvites`'s
    /// silent auto-accept and a human tapping Accept-anyway/Ignore in
    /// FriendsView's conflict review.
    func enqueueMatchInviteResponse(id: UUID, accept: Bool) {
        enqueueWork { [self] in
            guard let invite = AppStore.shared.matchInvites.first(where: { $0.id == id }) else { return }
            var updated = invite
            updated.status = accept ? .accepted : .declined
            guard let payload = PersistenceStore.encodeMatchInvite(updated) else { return }
            await manager.respondToMatchInvite(id: id, status: updated.status.rawValue, payload: payload)
            await refreshMatchInvites()
        }
    }

    // MARK: - Friend identity / stats sharing

    /// Permanent no-ops: a personal record already pushes to
    /// `players`/`match_records` unconditionally via
    /// `enqueueRosterChanges`/`enqueueHistoryChanges` regardless of any
    /// friend-sharing toggle, and friend visibility is granted entirely by
    /// `friend_can_view_history` RLS reading that same row (see
    /// `isPersonalOrClubRow`'s routing below), not by a second, mirrored
    /// write.
    func enqueueFriendsRosterChanges(upsertedIds: [UUID], deletedIds: [UUID]) {}
    func enqueueFriendsHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID]) {}

    func enqueueFriendIdentityChange() {
        enqueueWork { [self] in
            guard let uid = await manager.currentUserId(),
                  let payload = PersistenceStore.encodeFriendIdentitySnapshot(currentFriendIdentitySnapshot(myId: uid)) else { return }
            await manager.upsertFriendIdentitySnapshot(id: uid, payload: payload)
        }
    }

    func removeFriendIdentityRecord() {
        enqueueWork { [self] in
            guard let uid = await manager.currentUserId() else { return }
            await manager.removeFriendIdentitySnapshot(id: uid)
        }
    }

    func enqueueFriendStatsChange() {
        enqueueWork { [self] in
            guard let uid = await manager.currentUserId(),
                  let payload = PersistenceStore.encodeFriendStatsSnapshot(currentFriendStatsSnapshot(myId: uid)) else { return }
            await manager.upsertFriendStatsSnapshot(id: uid, payload: payload)
        }
    }

    func removeFriendStatsRecord() {
        enqueueWork { [self] in
            guard let uid = await manager.currentUserId() else { return }
            await manager.removeFriendStatsSnapshot(id: uid)
        }
    }

    /// displayName and avatar (colorIndex/iconName) always mirror
    /// unconditionally (Roadmap issue #272 — avatar isn't sensitive like the
    /// fields below). gender/birthday/introduction stay per-field toggle
    /// gated: a field is left `nil` in the snapshot itself whenever its
    /// toggle is off, never written at all.
    private func currentFriendIdentitySnapshot(myId: UUID) -> FriendIdentitySnapshot {
        let defaults = UserDefaults.standard
        let myName = defaults.string(forKey: AppStorageKeys.myName) ?? Player.defaultMyName
        let mePlayer = AppStore.shared.roster.first(where: { $0.id == AppStore.shared.localPlayerId })
        let shareGender = defaults.object(forKey: AppStorageKeys.shareGenderWithFriends) as? Bool ?? false
        let shareBirthday = defaults.object(forKey: AppStorageKeys.shareBirthdayWithFriends) as? Bool ?? false
        let shareIntroduction = defaults.object(forKey: AppStorageKeys.shareIntroductionWithFriends) as? Bool ?? false
        return FriendIdentitySnapshot(
            participantId: myId.uuidString,
            displayName: Player.displayName(for: myName),
            colorIndex: mePlayer?.colorIndex,
            iconName: mePlayer?.iconName,
            gender: shareGender ? defaults.string(forKey: AppStorageKeys.gender) : nil,
            birthday: shareBirthday ? (defaults.object(forKey: AppStorageKeys.birthday) as? Date) : nil,
            introduction: shareIntroduction ? defaults.string(forKey: AppStorageKeys.introduction) : nil
        )
    }

    private func currentFriendStatsSnapshot(myId: UUID) -> FriendStatsSnapshot {
        let myName = Player.displayName(for: UserDefaults.standard.string(forKey: AppStorageKeys.myName) ?? Player.defaultMyName)
        let personalHistory = AppStore.shared.history.filter { $0.clubId == nil }
        let personalRoster = AppStore.shared.roster.filter { $0.clubId == nil }
        return FriendStatsSnapshot.compute(
            participantId: myId.uuidString, displayName: myName, history: personalHistory, roster: personalRoster
        )
    }

    /// `friend_identity_snapshots`/`friend_stats_snapshots` carry no display
    /// name of their own — `profiles`/`friend_requests` already have one, so
    /// this resolves it from the already-synced friend graph rather than
    /// duplicating it into a third table.
    private func displayName(forFriendParticipant id: UUID) -> String {
        AppStore.shared.friends.first(where: { $0.participantId == id.uuidString })?.displayName ?? ""
    }

    // MARK: - Erase All My Data teardown

    /// Permanent no-op — there is no zone-style construct to tear down.
    /// Friend history visibility is pure RLS (`friend_can_view_history`)
    /// gated by `shareHistoryWithFriends`, which `AppStore.eraseAllData()`
    /// already resets to `false` before calling this; the underlying
    /// `players`/`match_records` rows are themselves deleted outright by
    /// that same method's `saveRoster([])`/`clearHistory()` calls. Same
    /// "documented permanent no-op" precedent
    /// `enqueueFriendsRosterChanges`/`enqueueFriendsHistoryChanges` set.
    func deleteFriendsHistoryZone() async {}

    func deleteMyFriendProfile() async {
        await manager.deleteMyProfile()
    }

    func deleteAllMyFriendRequests() async {
        await manager.deleteAllFriendRequests()
    }

    func deleteAllMyMatchInvites() async {
        await manager.deleteAllMyMatchInvites()
    }
}
