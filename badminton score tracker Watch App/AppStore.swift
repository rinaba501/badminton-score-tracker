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
import CloudSyncSpike

@MainActor
final class AppStore: ObservableObject {
    /// Reads whichever backend was active last session, so a relaunch after
    /// activateSupabaseSync() stays on Supabase rather than silently
    /// reverting to local-only (can't use @AppStorage in a static
    /// initializer). An unlinked device defaults to `NoOpSyncEngine` —
    /// nothing leaves the device until an explicit Supabase sign-in.
    static let shared = AppStore(
        syncEngine: UserDefaults.standard.bool(forKey: AppStorageKeys.supabaseAccountLinked)
            ? SupabaseSyncEngine.shared
            : NoOpSyncEngine()
    )

    @Published private(set) var roster: [Player]
    @Published private(set) var history: [MatchRecord]
    @Published private(set) var clubs: [Club]
    /// Roadmap Phase 5 backlog (#162): club-scoped only — there's no
    /// meaningful "personal" challenge, so unlike roster/history there's no
    /// personal/KV fallback at all (see saveChallenges).
    @Published private(set) var challenges: [ChallengeRecord]
    /// Roadmap Phase 5 backlog (#164): club-scoped only, same contract as
    /// `challenges` — no personal/KV fallback (see saveReactions).
    @Published private(set) var reactions: [ReactionRecord]
    /// Friends v1 (graph-only, #7c): synced via the `friend_requests` table
    /// through `SupabaseSyncManager.sendFriendRequest`/`respondToFriendRequest`
    /// (see saveFriendRequests). This cache is updated only after such a
    /// direct call succeeds, or after a `refreshFriendRequests()` poll.
    @Published private(set) var friendRequests: [FriendRequest]
    /// Roadmap Phase 10a: "did this happen?" pings for personal singles
    /// matches whose opponent was picked from Friends — same "updated only
    /// after a direct network call/refetch, not through syncEngine's
    /// enqueue* diffing" contract as `friendRequests` (see
    /// `saveMatchInvites`). Most of these are resolved silently by
    /// `autoResolvePendingMatchInvites()` and never seen by a human — see
    /// `matchConflicts` for the ones that aren't.
    @Published private(set) var matchInvites: [SharedMatchInvite]
    /// Friends' shared personal roster/history, keyed by their participantId
    /// — a friend's own players/match_records rows become visible via the
    /// friend_can_view_history RLS policy once they've turned on history
    /// sharing, and route in here (SupabaseSyncEngine,
    /// applyRemoteFriendActivity) rather than a duplicated copy.
    /// Deliberately separate from `roster`/`history`: this is someone else's
    /// data, shown read-only, and must never be merged into the viewer's own
    /// caches or stats.
    @Published private(set) var friendActivity: [String: FriendHistorySnapshot]
    /// Friends' shared profile identity fields (avatar/gender/birthday/
    /// introduction), keyed by participantId — same "never merged into your
    /// own data" contract as `friendActivity`, mirrored from each friend's
    /// row in `friend_identity_snapshots`. See FriendIdentitySnapshot.swift.
    @Published private(set) var friendIdentities: [String: FriendIdentitySnapshot]
    /// Friends' shared derived stats, keyed by participantId — same contract
    /// as `friendIdentities`, mirrored from each friend's row in
    /// `friend_stats_snapshots`. See FriendStatsSnapshot.swift.
    @Published private(set) var friendStats: [String: FriendStatsSnapshot]

    /// Accepted friend requests, derived — Friends v1 has no separate
    /// `Friendship` record (see `FriendRequest.swift`).
    var friends: [(participantId: String, displayName: String)] {
        friendRequests.compactMap { request in
            guard request.status == .accepted else { return nil }
            guard let myId = UserDefaults.standard.string(forKey: AppStorageKeys.myParticipantId) else { return nil }
            if request.fromParticipantId == myId {
                return (request.toParticipantId, request.toDisplayName)
            } else if request.toParticipantId == myId {
                return (request.fromParticipantId, request.fromDisplayName)
            }
            return nil
        }
    }

    /// Pending invites addressed to me that `autoResolvePendingMatchInvites`
    /// could NOT silently mirror because `StatsCalculator.conflictingRecord`
    /// found a pre-existing, differently-scored record for the same two
    /// participants — the only match invites a human ever sees (FriendsView's
    /// conflict-review section). Computed rather than a separate persisted
    /// status, so there's no fourth wire-status value to keep in sync with
    /// the schema's 3-value check constraint.
    var matchConflicts: [SharedMatchInvite] {
        guard let myId = UserDefaults.standard.string(forKey: AppStorageKeys.myParticipantId) else { return [] }
        return matchInvites.filter { invite in
            guard invite.status == .pending, invite.toParticipantId == myId else { return false }
            guard !history.contains(where: { $0.sourceMatchId == invite.id }) else { return false }
            guard let mirror = MatchInviteMirror.build(from: invite, myName: myDisplayName, myPlayerId: localPlayerId) else { return false }
            return StatsCalculator.conflictingRecord(for: mirror, in: history) != nil
        }
    }

    /// The pre-existing record `StatsCalculator.conflictingRecord` flagged
    /// against `invite`, for FriendsView's conflict-review row to render
    /// both sides — recomputed rather than cached, matching `matchConflicts`.
    func conflictingRecord(for invite: SharedMatchInvite) -> MatchRecord? {
        guard let mirror = MatchInviteMirror.build(from: invite, myName: myDisplayName, myPlayerId: localPlayerId) else { return nil }
        return StatsCalculator.conflictingRecord(for: mirror, in: history)
    }

    /// This device's own scoring name, read the same way `saveMatch()`
    /// resolves "me" — used only for building a mirrored `MatchRecord`
    /// (`MatchInviteMirror.build`'s `myName` must be the RECIPIENT's own
    /// identity, never copied from the invite).
    private var myDisplayName: String {
        UserDefaults.standard.string(forKey: AppStorageKeys.myName) ?? Player.defaultMyName
    }

    @AppStorage(AppStorageKeys.localPlayerId) private var localPlayerIdString: String = ""

    /// Every outbound sync call goes through this seam rather than a
    /// hardcoded `SupabaseSyncEngine.shared` reference (see SyncEngine.swift).
    /// Mutable — activateSupabaseSync()/
    /// deactivateSupabaseSync() swap it at runtime; only this file may
    /// assign it, so no other call site can bypass those methods' guards.
    private(set) var syncEngine: SyncEngine

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

    private init(syncEngine: SyncEngine) {
        self.syncEngine = syncEngine
        Self.runMigrations()
        let r = UserDefaults.standard.data(forKey: AppStorageKeys.playerRoster) ?? Data()
        let h = UserDefaults.standard.data(forKey: AppStorageKeys.matchHistory) ?? Data()
        let c = UserDefaults.standard.data(forKey: AppStorageKeys.clubs) ?? Data()
        let ch = UserDefaults.standard.data(forKey: AppStorageKeys.challenges) ?? Data()
        let re = UserDefaults.standard.data(forKey: AppStorageKeys.reactions) ?? Data()
        let fr = UserDefaults.standard.data(forKey: AppStorageKeys.friendRequests) ?? Data()
        let mi = UserDefaults.standard.data(forKey: AppStorageKeys.matchInvites) ?? Data()
        let fa = UserDefaults.standard.data(forKey: AppStorageKeys.friendActivity) ?? Data()
        let fi = UserDefaults.standard.data(forKey: AppStorageKeys.friendIdentities) ?? Data()
        let fs = UserDefaults.standard.data(forKey: AppStorageKeys.friendStats) ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
        clubs = PersistenceStore.decodeClubs(c)
        challenges = PersistenceStore.decodeChallenges(ch)
        reactions = PersistenceStore.decodeReactions(re)
        friendRequests = PersistenceStore.decodeFriendRequests(fr)
        matchInvites = PersistenceStore.decodeMatchInvites(mi)
        friendActivity = Dictionary(
            uniqueKeysWithValues: PersistenceStore.decodeFriendActivity(fa).map { ($0.participantId, $0) }
        )
        friendIdentities = Dictionary(
            uniqueKeysWithValues: PersistenceStore.decodeFriendIdentities(fi).map { ($0.participantId, $0) }
        )
        friendStats = Dictionary(
            uniqueKeysWithValues: PersistenceStore.decodeFriendStats(fs).map { ($0.participantId, $0) }
        )
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

    // MARK: - Supabase backend switch

    /// Called once `SupabaseSyncManager.shared.isSignedIn` is true (the
    /// Sync Backend Settings section drives the actual sign-in) — no-ops
    /// otherwise, so this can't flip `syncEngine` to a backend with no live
    /// session. Uploads the device's current personal data as a one-time
    /// migration (reusing the same enqueue* methods a normal save already
    /// uses, seeded with every existing id, batched — see
    /// SupabaseSyncEngine), then makes Supabase the active backend. Does not
    /// set `AppStorageKeys.supabaseAccountLinked` itself; the caller (a
    /// `@AppStorage`-bound Settings toggle) owns that write.
    func activateSupabaseSync() {
        guard SupabaseSyncManager.shared.isSignedIn else { return }
        syncEngine = SupabaseSyncEngine.shared
        syncEngine.enqueueRosterChanges(upsertedIds: roster.map(\.id), deletedIds: [:])
        syncEngine.enqueueHistoryChanges(upsertedIds: history.map(\.id), deletedIds: [:])
        syncEngine.enqueueSettingsChange()
        // Queued after the three pushes above — a fresh activation's
        // migration-on-signin upload finishes before the catch-up pull
        // runs, so a second device signing into an account that already has
        // Supabase data gets it too, not just what this device just
        // uploaded.
        SupabaseSyncEngine.shared.startIfActive()
    }

    /// Reverts to local-only — there's no other backend to fall back to. No
    /// remote Supabase delete — safe/reversible.
    func deactivateSupabaseSync() {
        SupabaseSyncEngine.shared.stopRealtimeSync()
        syncEngine = NoOpSyncEngine()
    }

    /// Settings live as scattered `@AppStorage` scalars, not in AppStore's
    /// own arrays — a single source of truth `SupabaseSyncEngine` reads from
    /// when it needs the full snapshot.
    func currentSettingsSnapshot() -> SettingsSnapshot {
        let defaults = UserDefaults.standard
        return SettingsSnapshot(
            myName: defaults.string(forKey: AppStorageKeys.myName) ?? Player.defaultMyName,
            localPlayerId: localPlayerId.uuidString,
            pointsToWin: defaults.object(forKey: AppStorageKeys.pointsToWin) as? Int ?? 21,
            gamesInMatch: defaults.object(forKey: AppStorageKeys.gamesInMatch) as? Int ?? 3,
            courtTheme: defaults.string(forKey: AppStorageKeys.courtTheme) ?? "Green",
            announceScore: defaults.object(forKey: AppStorageKeys.announceScore) as? Bool ?? true,
            enableSounds: defaults.object(forKey: AppStorageKeys.enableSounds) as? Bool ?? true,
            enableCrownScoring: defaults.object(forKey: AppStorageKeys.enableCrownScoring) as? Bool ?? true,
            timeModeEnabled: defaults.object(forKey: AppStorageKeys.timeModeEnabled) as? Bool ?? false,
            timeLimitMinutes: defaults.object(forKey: AppStorageKeys.timeLimitMinutes) as? Int ?? 10,
            courtChangeRemindersEnabled: defaults.object(forKey: AppStorageKeys.courtChangeRemindersEnabled) as? Bool ?? false,
            clubLastViewedActivity: ClubActivityCodec.decode(defaults.data(forKey: AppStorageKeys.clubLastViewedActivity) ?? Data()),
            gameScreenStyle: defaults.string(forKey: AppStorageKeys.gameScreenStyle) ?? "Depth",
            shareHistoryWithFriends: defaults.object(forKey: AppStorageKeys.shareHistoryWithFriends) as? Bool ?? false,
            shareAvatarWithFriends: defaults.object(forKey: AppStorageKeys.shareAvatarWithFriends) as? Bool ?? false,
            shareGenderWithFriends: defaults.object(forKey: AppStorageKeys.shareGenderWithFriends) as? Bool ?? false,
            shareBirthdayWithFriends: defaults.object(forKey: AppStorageKeys.shareBirthdayWithFriends) as? Bool ?? false,
            shareIntroductionWithFriends: defaults.object(forKey: AppStorageKeys.shareIntroductionWithFriends) as? Bool ?? false,
            shareStatsWithFriends: defaults.object(forKey: AppStorageKeys.shareStatsWithFriends) as? Bool ?? false,
            gender: defaults.string(forKey: AppStorageKeys.gender),
            birthday: defaults.object(forKey: AppStorageKeys.birthday) as? Date,
            introduction: defaults.string(forKey: AppStorageKeys.introduction)
        )
    }

    /// Passthrough so Views can enqueue a settings-only sync without reaching
    /// past AppStore to a concrete sync manager — a View calling the sync
    /// manager directly instead of through this seam is a real bug class
    /// this codebase has hit more than once (see SyncEngine.swift's
    /// `removeFriendStatsRecord()` doc comment for another instance).
    func enqueueSettingsChange() {
        syncEngine.enqueueSettingsChange()
    }

    // Each save updates the local cache + UserDefaults, then enqueues precise
    // per-record upserts/deletes to syncEngine — the only sync path.
    func saveRoster(_ players: [Player]) {
        guard let encoded = PersistenceStore.encodeRoster(players) else { return }
        let diff = PersistenceStore.diffRoster(from: roster, to: players)
        let deletedClubIds = Dictionary(
            roster.filter { oldPlayer in diff.deletedIds.contains(oldPlayer.id) }
                .map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.playerRoster)
        roster = players
        syncEngine.enqueueRosterChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedClubIds)
        syncEngine.enqueueSettingsChange()

        if isSharingHistoryWithFriends {
            let newClubIds = Dictionary(players.map { ($0.id, $0.clubId) }, uniquingKeysWith: { first, _ in first })
            let personalUpserts = personalIds(among: diff.upsertedIds, clubIds: newClubIds)
            let personalDeletes = personalIds(among: diff.deletedIds, clubIds: deletedClubIds)
            if !personalUpserts.isEmpty || !personalDeletes.isEmpty {
                syncEngine.enqueueFriendsRosterChanges(upsertedIds: personalUpserts, deletedIds: personalDeletes)
            }
        }
        // Avatar is the one identity sub-field stored on the roster (the "Me"
        // player) rather than SettingsSnapshot — only re-mirror when that
        // player actually changed, not on every roster edit.
        if diff.upsertedIds.contains(localPlayerId) || diff.deletedIds.contains(localPlayerId) {
            refreshMyIdentitySnapshotIfSharing()
        }
        if isSharingStatsWithFriends {
            syncEngine.enqueueFriendStatsChange()
        }
    }

    func saveHistory(_ records: [MatchRecord]) {
        guard let encoded = PersistenceStore.encodeHistory(records) else { return }
        // Compute both against the OLD `history` before reassigning it.
        let diff = PersistenceStore.diffHistory(from: history, to: records)
        let deletedClubIds = Dictionary(
            history.filter { oldRecord in diff.deletedIds.contains(oldRecord.id) }
                .map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.matchHistory)
        history = records
        syncEngine.enqueueHistoryChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedClubIds)
        syncEngine.enqueueSettingsChange()

        if isSharingHistoryWithFriends {
            let newClubIds = Dictionary(records.map { ($0.id, $0.clubId) }, uniquingKeysWith: { first, _ in first })
            let personalUpserts = personalIds(among: diff.upsertedIds, clubIds: newClubIds)
            let personalDeletes = personalIds(among: diff.deletedIds, clubIds: deletedClubIds)
            if !personalUpserts.isEmpty || !personalDeletes.isEmpty {
                syncEngine.enqueueFriendsHistoryChanges(upsertedIds: personalUpserts, deletedIds: personalDeletes)
            }
        }
        if isSharingStatsWithFriends {
            syncEngine.enqueueFriendStatsChange()
        }

        // Roadmap Phase 10a: push a match invite for every newly-upserted
        // personal singles record tagged with a friend opponent.
        // sourceMatchId == nil is the guard that stops a MIRRORED record
        // (which also carries an opponentParticipantId — pointing back at
        // the original sender) from spawning its own outbound invite chain.
        if !diff.upsertedIds.isEmpty {
            let byId = Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for id in diff.upsertedIds {
                guard let record = byId[id],
                      record.clubId == nil, !record.isDoubles, record.sourceMatchId == nil,
                      let participantId = record.opponentParticipantId else { continue }
                syncEngine.enqueueMatchInvite(recordId: id, opponentParticipantId: participantId)
            }
        }
    }

    func clearHistory() {
        let deletedClubIds = Dictionary(
            history.map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(Data(), forKey: AppStorageKeys.matchHistory)
        history = []
        syncEngine.enqueueHistoryChanges(upsertedIds: [], deletedIds: deletedClubIds)
        syncEngine.enqueueSettingsChange()

        if isSharingHistoryWithFriends {
            let personalDeletes = personalIds(among: Array(deletedClubIds.keys), clubIds: deletedClubIds)
            if !personalDeletes.isEmpty {
                syncEngine.enqueueFriendsHistoryChanges(upsertedIds: [], deletedIds: personalDeletes)
            }
        }
        if isSharingStatsWithFriends {
            syncEngine.enqueueFriendStatsChange()
        }
    }

    /// Erase All My Data (#264): wipes every local + cloud-synced record
    /// this account owns — roster, history, clubs (deletes owned clubs
    /// outright, leaves joined clubs via the existing `saveClubs` diffing),
    /// challenges, reactions, the Friends graph (`friend_requests`/
    /// `profiles` rows plus the friend identity/stats snapshot rows), and
    /// every scalar setting (`AppStorageKeys.eraseAllDataResetKeys`) — so
    /// the app reads back as a fresh install.
    func eraseAllData() async {
        // Reset the share*WithFriends/shareStatsWithFriends toggles (part of
        // eraseAllDataResetKeys) BEFORE calling saveRoster/clearHistory
        // below: those methods re-enqueue a FriendStats/FriendIdentity save
        // whenever sharing is on, which would otherwise race the explicit
        // removeFriendIdentityRecord()/removeFriendStatsRecord() calls a few
        // lines down — both would be pending on the same sync engine with no
        // guaranteed ordering, risking a save "winning" and leaving a stale
        // row behind. Resetting the toggles first makes
        // isSharingHistoryWithFriends/isSharingStatsWithFriends read false,
        // so saveRoster/clearHistory never re-enqueue anything this method
        // is about to delete.
        for key in AppStorageKeys.eraseAllDataResetKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        saveRoster([])
        clearHistory()
        saveClubs([])
        saveChallenges([])
        saveReactions([])

        await syncEngine.deleteAllMyFriendRequests()
        saveFriendRequests([])
        await syncEngine.deleteAllMyMatchInvites()
        saveMatchInvites([])
        await syncEngine.deleteMyFriendProfile()
        await syncEngine.deleteFriendsHistoryZone()
        // Explicit and unconditional, rather than relying on saveRoster's
        // diff-gated refreshMyIdentitySnapshotIfSharing() call above to
        // happen to fire: friend_identity_snapshots/friend_stats_snapshots
        // are ordinary tables with no bulk-delete-by-owner shortcut, so
        // these two calls are the only thing that clears them during an
        // erase.
        syncEngine.removeFriendIdentityRecord()
        syncEngine.removeFriendStatsRecord()

        syncEngine.enqueueSettingsChange()
    }

    private var isSharingHistoryWithFriends: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.shareHistoryWithFriends)
    }

    var isSharingAnyFriendIdentityField: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: AppStorageKeys.shareAvatarWithFriends)
            || defaults.bool(forKey: AppStorageKeys.shareGenderWithFriends)
            || defaults.bool(forKey: AppStorageKeys.shareBirthdayWithFriends)
            || defaults.bool(forKey: AppStorageKeys.shareIntroductionWithFriends)
    }

    var isSharingStatsWithFriends: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.shareStatsWithFriends)
    }

    /// Recomputes and re-enqueues this device's own "FriendIdentity" record
    /// if any identity sub-field toggle is on — call after a SettingsSnapshot
    /// identity field (gender/birthday/introduction) or its toggle changes,
    /// so the mirror stays in sync without duplicating the per-field gating
    /// logic at every call site.
    func refreshMyIdentitySnapshotIfSharing() {
        if isSharingAnyFriendIdentityField {
            syncEngine.enqueueFriendIdentityChange()
        } else {
            syncEngine.removeFriendIdentityRecord()
        }
    }

    /// Ids whose (new, for upserts; old, for deletes) clubId is nil —
    /// personal records are the only ones mirrored into "FriendsHistory".
    private func personalIds(among ids: [UUID], clubIds: [UUID: UUID?]) -> [UUID] {
        ids.filter { clubIds[$0].flatMap { $0 } == nil }
    }

    func saveClubs(_ clubs: [Club]) {
        guard let encoded = PersistenceStore.encodeClubs(clubs) else { return }
        let diff = PersistenceStore.diffClubs(from: self.clubs, to: clubs)
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.clubs)
        let oldClubs = self.clubs
        self.clubs = clubs
        let deletedClubs = Dictionary(
            oldClubs.filter { oldClub in diff.deletedIds.contains(oldClub.id) }
                .map { ($0.id, $0.ownerRecordName) },
            uniquingKeysWith: { first, _ in first }
        )
        syncEngine.enqueueClubChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedClubs)
    }

    // Roadmap Phase 5 backlog (#162): challenges only exist as a club
    // concept (a ping between two real account holders) — no "personal"
    // challenge, so unlike roster/history there's no local-only state to
    // reconcile.
    func saveChallenges(_ challenges: [ChallengeRecord]) {
        guard let encoded = PersistenceStore.encodeChallenges(challenges) else { return }
        let diff = PersistenceStore.diffChallenges(from: self.challenges, to: challenges)
        let deletedChallengeClubIds = Dictionary(
            self.challenges.filter { diff.deletedIds.contains($0.id) }.map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.challenges)
        self.challenges = challenges
        syncEngine.enqueueChallengeChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedChallengeClubIds)
    }

    // Roadmap Phase 5 backlog (#164): reactions follow saveChallenges'
    // club-scoped-only contract.
    func saveReactions(_ reactions: [ReactionRecord]) {
        guard let encoded = PersistenceStore.encodeReactions(reactions) else { return }
        let diff = PersistenceStore.diffReactions(from: self.reactions, to: reactions)
        let deletedReactionClubIds = Dictionary(
            self.reactions.filter { diff.deletedIds.contains($0.id) }.map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.reactions)
        self.reactions = reactions
        syncEngine.enqueueReactionChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedReactionClubIds)
    }

    // Friends v1 (#7c): unlike every other save* method here, this does NOT
    // go through syncEngine's enqueue* path — the actual network write
    // already happened via a direct sendFriendRequest/respondToFriendRequest
    // call (or a refreshFriendRequests() poll/Realtime event); this just
    // reconciles the local cache to match afterward, the same shape as
    // applyRemoteUpsert but driven by a full refetch instead of a diff.
    func saveFriendRequests(_ friendRequests: [FriendRequest]) {
        guard let encoded = PersistenceStore.encodeFriendRequests(friendRequests) else { return }
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.friendRequests)
        self.friendRequests = friendRequests
        pruneFriendActivityToCurrentFriends()
    }

    // Roadmap Phase 10a: same "not through syncEngine's enqueue* diffing"
    // shape as saveFriendRequests, for the same reason — the network
    // mutation (send/respond) already happened via a direct
    // SupabaseSyncManager call before this reconciles the local cache.
    func saveMatchInvites(_ matchInvites: [SharedMatchInvite]) {
        guard let encoded = PersistenceStore.encodeMatchInvites(matchInvites) else { return }
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.matchInvites)
        self.matchInvites = matchInvites
        autoResolvePendingMatchInvites()
    }

    /// For every pending invite addressed to me with no existing mirrored
    /// record (`sourceMatchId` dedup) and no detected conflict, silently
    /// build + save the mirror and mark the invite accepted — the auto-sync
    /// path, no confirmation tap, since being friends already is the trust
    /// boundary (same reasoning `shareHistoryWithFriends` needs no per-record
    /// approval). A conflicting invite is left `pending` for FriendsView's
    /// review UI (`matchConflicts`) instead. Idempotent — re-running against
    /// an already-resolved invite list is a no-op, which is what lets
    /// `SupabaseSyncEngine.handleRemoteChange`'s `match_invites` branch
    /// always do a full refetch-and-reconcile rather than incremental
    /// per-event handling.
    private func autoResolvePendingMatchInvites() {
        guard let myId = UserDefaults.standard.string(forKey: AppStorageKeys.myParticipantId) else { return }
        for invite in matchInvites where invite.status == .pending && invite.toParticipantId == myId {
            guard !history.contains(where: { $0.sourceMatchId == invite.id }) else { continue }
            guard let mirror = MatchInviteMirror.build(from: invite, myName: myDisplayName, myPlayerId: localPlayerId) else { continue }
            guard StatsCalculator.conflictingRecord(for: mirror, in: history) == nil else { continue }
            saveHistory(history + [mirror])
            respondToMatchInvite(invite, accept: true)
        }
    }

    /// The one call path for accepting/declining a match invite — used both
    /// by the silent auto-resolve above and by a human tapping Accept-
    /// anyway/Ignore in FriendsView's conflict-review section.
    func respondToMatchInvite(_ invite: SharedMatchInvite, accept: Bool) {
        syncEngine.enqueueMatchInviteResponse(id: invite.id, accept: accept)
    }

    /// FriendsView's "Accept anyway" action on a conflicting invite
    /// (`matchConflicts`) — same build+save sequence
    /// `autoResolvePendingMatchInvites` runs automatically for the
    /// no-conflict case, but here a human explicitly opted in despite the
    /// flagged conflict, so this deliberately skips re-checking
    /// `StatsCalculator.conflictingRecord`. Creates a second, separate
    /// MatchRecord — no merge/dedup with the pre-existing conflicting one,
    /// same tradeoff baked into 10a (see MatchInviteMirror.swift). Guarded
    /// by the same sourceMatchId dedup as the auto-resolve path so a
    /// double-tap can't create two mirrors.
    func acceptConflictingMatchInvite(_ invite: SharedMatchInvite) {
        guard !history.contains(where: { $0.sourceMatchId == invite.id }) else { return }
        guard let mirror = MatchInviteMirror.build(from: invite, myName: myDisplayName, myPlayerId: localPlayerId) else { return }
        saveHistory(history + [mirror])
        respondToMatchInvite(invite, accept: true)
    }

    /// Drops any cached `friendActivity` entry for a participantId no longer
    /// in the accepted-friends graph (e.g. a declined/no-longer-accepted
    /// request) — a friend's shared history must stop being visible the
    /// moment they're no longer a friend, even before the next remote fetch.
    private func pruneFriendActivityToCurrentFriends() {
        let friendIds = Set(friends.map(\.participantId))
        let staleActivity = friendActivity.keys.filter { !friendIds.contains($0) }
        if !staleActivity.isEmpty {
            for id in staleActivity { friendActivity[id] = nil }
            persist(friendActivity: Array(friendActivity.values))
        }
        let staleIdentities = friendIdentities.keys.filter { !friendIds.contains($0) }
        if !staleIdentities.isEmpty {
            for id in staleIdentities { friendIdentities[id] = nil }
            persist(friendIdentities: Array(friendIdentities.values))
        }
        let staleStats = friendStats.keys.filter { !friendIds.contains($0) }
        if !staleStats.isEmpty {
            for id in staleStats { friendStats[id] = nil }
            persist(friendStats: Array(friendStats.values))
        }
    }

    /// Writes a remotely-fetched settings snapshot straight to UserDefaults.
    /// `@AppStorage` observes external `UserDefaults` writes via KVO, so
    /// every view bound to these keys stays reactive with no further wiring.
    /// Empty/invalid `localPlayerId` is ignored so a device that materializes
    /// Settings before generating an id cannot wipe a valid "Me" identity.
    func applyRemoteSettings(_ snapshot: SettingsSnapshot) {
        let defaults = UserDefaults.standard
        defaults.set(snapshot.myName, forKey: AppStorageKeys.myName)
        if UUID(uuidString: snapshot.localPlayerId) != nil {
            defaults.set(snapshot.localPlayerId, forKey: AppStorageKeys.localPlayerId)
        }
        defaults.set(snapshot.pointsToWin, forKey: AppStorageKeys.pointsToWin)
        defaults.set(snapshot.gamesInMatch, forKey: AppStorageKeys.gamesInMatch)
        defaults.set(snapshot.courtTheme, forKey: AppStorageKeys.courtTheme)
        defaults.set(snapshot.announceScore, forKey: AppStorageKeys.announceScore)
        defaults.set(snapshot.enableSounds, forKey: AppStorageKeys.enableSounds)
        defaults.set(snapshot.enableCrownScoring, forKey: AppStorageKeys.enableCrownScoring)
        defaults.set(snapshot.timeModeEnabled, forKey: AppStorageKeys.timeModeEnabled)
        defaults.set(snapshot.timeLimitMinutes, forKey: AppStorageKeys.timeLimitMinutes)
        defaults.set(snapshot.courtChangeRemindersEnabled, forKey: AppStorageKeys.courtChangeRemindersEnabled)
        defaults.set(snapshot.gameScreenStyle, forKey: AppStorageKeys.gameScreenStyle)
        defaults.set(snapshot.shareHistoryWithFriends, forKey: AppStorageKeys.shareHistoryWithFriends)
        defaults.set(snapshot.shareAvatarWithFriends, forKey: AppStorageKeys.shareAvatarWithFriends)
        defaults.set(snapshot.shareGenderWithFriends, forKey: AppStorageKeys.shareGenderWithFriends)
        defaults.set(snapshot.shareBirthdayWithFriends, forKey: AppStorageKeys.shareBirthdayWithFriends)
        defaults.set(snapshot.shareIntroductionWithFriends, forKey: AppStorageKeys.shareIntroductionWithFriends)
        defaults.set(snapshot.shareStatsWithFriends, forKey: AppStorageKeys.shareStatsWithFriends)
        if let gender = snapshot.gender {
            defaults.set(gender, forKey: AppStorageKeys.gender)
        } else {
            defaults.removeObject(forKey: AppStorageKeys.gender)
        }
        if let birthday = snapshot.birthday {
            defaults.set(birthday, forKey: AppStorageKeys.birthday)
        } else {
            defaults.removeObject(forKey: AppStorageKeys.birthday)
        }
        if let introduction = snapshot.introduction {
            defaults.set(introduction, forKey: AppStorageKeys.introduction)
        } else {
            defaults.removeObject(forKey: AppStorageKeys.introduction)
        }
        // Merge (per-club max), never overwrite: two devices can mark different
        // clubs viewed before their Settings records converge, and a blind
        // overwrite would re-raise an unread dot the user already cleared.
        var merged = ClubActivityCodec.decode(defaults.data(forKey: AppStorageKeys.clubLastViewedActivity) ?? Data())
        for (clubId, remoteDate) in snapshot.clubLastViewedActivity {
            merged[clubId] = max(merged[clubId] ?? .distantPast, remoteDate)
        }
        defaults.set(ClubActivityCodec.encode(merged), forKey: AppStorageKeys.clubLastViewedActivity)
    }

    // MARK: - Apply remote changes (called by SupabaseSyncEngine)

    /// Merge remotely-fetched records into the caches by id and persist to the
    /// UserDefaults cache. Targeted (per id) rather than a full re-decode so a
    /// fetch landing mid-edit doesn't clobber an unrelated local change. History
    /// stays date-sorted; roster keeps its stored order (updates in place,
    /// appends new).
    func applyRemoteUpsert(
        records: [MatchRecord], players: [Player], clubs newClubs: [Club],
        challenges newChallenges: [ChallengeRecord] = [],
        reactions newReactions: [ReactionRecord] = []
    ) {
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
        if !newClubs.isEmpty {
            var updated = clubs
            var indexById = Dictionary(clubs.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for club in newClubs {
                if let idx = indexById[club.id] {
                    updated[idx] = club
                } else {
                    indexById[club.id] = updated.count
                    updated.append(club)
                }
            }
            clubs = updated
            persist(clubs: clubs)
        }
        if !newChallenges.isEmpty {
            var updated = challenges
            var indexById = Dictionary(challenges.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for challenge in newChallenges {
                if let idx = indexById[challenge.id] {
                    updated[idx] = challenge
                } else {
                    indexById[challenge.id] = updated.count
                    updated.append(challenge)
                }
            }
            challenges = updated
            persist(challenges: challenges)
        }
        if !newReactions.isEmpty {
            var updated = reactions
            var indexById = Dictionary(reactions.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for reaction in newReactions {
                if let idx = indexById[reaction.id] {
                    updated[idx] = reaction
                } else {
                    indexById[reaction.id] = updated.count
                    updated.append(reaction)
                }
            }
            reactions = updated
            persist(reactions: reactions)
        }
    }

    /// Remove remotely-deleted records by id from the caches and persist.
    func applyRemoteDeletions(
        recordIds: [UUID], playerIds: [UUID], clubIds: [UUID],
        challengeIds: [UUID] = [], reactionIds: [UUID] = []
    ) {
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
        if !clubIds.isEmpty {
            let removed = Set(clubIds)
            clubs = clubs.filter { !removed.contains($0.id) }
            persist(clubs: clubs)
        }
        if !challengeIds.isEmpty {
            let removed = Set(challengeIds)
            challenges = challenges.filter { !removed.contains($0.id) }
            persist(challenges: challenges)
        }
        if !reactionIds.isEmpty {
            let removed = Set(reactionIds)
            reactions = reactions.filter { !removed.contains($0.id) }
            persist(reactions: reactions)
        }
    }

    /// Merges a friend's shared roster/history into their `friendActivity`
    /// snapshot. Never touches `roster`/`history` — this is someone else's
    /// data (see the `friendActivity` doc comment). `participantId` is the
    /// owning friend's, i.e. the fetched zone's `ownerName`.
    func applyRemoteFriendActivity(participantId: String, matches: [MatchRecord], players: [Player]) {
        guard !matches.isEmpty || !players.isEmpty else { return }
        let displayName = friends.first { $0.participantId == participantId }?.displayName
            ?? friendActivity[participantId]?.displayName
            ?? participantId
        var snapshot = friendActivity[participantId] ?? FriendHistorySnapshot(participantId: participantId, displayName: displayName)
        snapshot.displayName = displayName

        if !matches.isEmpty {
            var byId = Dictionary(snapshot.history.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for match in matches { byId[match.id] = match }
            snapshot.history = byId.values.sorted { $0.date < $1.date }
        }
        if !players.isEmpty {
            var updated = snapshot.roster
            var indexById = Dictionary(snapshot.roster.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for player in players {
                if let idx = indexById[player.id] {
                    updated[idx] = player
                } else {
                    indexById[player.id] = updated.count
                    updated.append(player)
                }
            }
            snapshot.roster = updated
        }

        friendActivity[participantId] = snapshot
        persist(friendActivity: Array(friendActivity.values))
    }

    /// Removes remotely-deleted records from a friend's `friendActivity`
    /// snapshot.
    func applyRemoteFriendActivityDeletions(participantId: String, matchIds: [UUID], playerIds: [UUID]) {
        guard var snapshot = friendActivity[participantId], !matchIds.isEmpty || !playerIds.isEmpty else { return }
        if !matchIds.isEmpty {
            let removed = Set(matchIds)
            snapshot.history = snapshot.history.filter { !removed.contains($0.id) }
        }
        if !playerIds.isEmpty {
            let removed = Set(playerIds)
            snapshot.roster = snapshot.roster.filter { !removed.contains($0.id) }
        }
        friendActivity[participantId] = snapshot
        persist(friendActivity: Array(friendActivity.values))
    }

    /// Replaces a friend's cached identity snapshot wholesale — unlike
    /// `applyRemoteFriendActivity`'s per-record merge, the "FriendIdentity"
    /// record is a single record carrying every field, so the fetched
    /// snapshot always supersedes what's cached.
    func applyRemoteFriendIdentity(participantId: String, snapshot: FriendIdentitySnapshot) {
        friendIdentities[participantId] = snapshot
        persist(friendIdentities: Array(friendIdentities.values))
    }

    /// Removes a friend's cached identity snapshot — the owner deleted their
    /// "FriendIdentity" record (every identity toggle turned off).
    func applyRemoteFriendIdentityDeletion(participantId: String) {
        guard friendIdentities[participantId] != nil else { return }
        friendIdentities[participantId] = nil
        persist(friendIdentities: Array(friendIdentities.values))
    }

    /// Replaces a friend's cached stats snapshot wholesale, same contract as
    /// `applyRemoteFriendIdentity`.
    func applyRemoteFriendStats(participantId: String, snapshot: FriendStatsSnapshot) {
        friendStats[participantId] = snapshot
        persist(friendStats: Array(friendStats.values))
    }

    /// Removes a friend's cached stats snapshot — the owner deleted their
    /// "FriendStats" record (shareStatsWithFriends turned off).
    func applyRemoteFriendStatsDeletion(participantId: String) {
        guard friendStats[participantId] != nil else { return }
        friendStats[participantId] = nil
        persist(friendStats: Array(friendStats.values))
    }

    private func persist(friendActivity snapshots: [FriendHistorySnapshot]) {
        if let encoded = PersistenceStore.encodeFriendActivity(snapshots) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.friendActivity)
        }
    }

    private func persist(friendIdentities snapshots: [FriendIdentitySnapshot]) {
        if let encoded = PersistenceStore.encodeFriendIdentities(snapshots) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.friendIdentities)
        }
    }

    private func persist(friendStats snapshots: [FriendStatsSnapshot]) {
        if let encoded = PersistenceStore.encodeFriendStats(snapshots) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.friendStats)
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

    private func persist(clubs: [Club]) {
        if let encoded = PersistenceStore.encodeClubs(clubs) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.clubs)
        }
    }

    private func persist(challenges: [ChallengeRecord]) {
        if let encoded = PersistenceStore.encodeChallenges(challenges) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.challenges)
        }
    }

    private func persist(reactions: [ReactionRecord]) {
        if let encoded = PersistenceStore.encodeReactions(reactions) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.reactions)
        }
    }
}
