import Combine
import Foundation
import Supabase
#if os(iOS)
import AuthenticationServices
#endif

/// Low-level Supabase transport: auth (Google OAuth on iOS, relayed-session
/// adoption on watchOS), typed push CRUD against the Phase 9 schema
/// (supabase/schema.sql), and (Phase 9c-5) the pull-side counterpart —
/// `fetchAllRows`/`fetchSettings` for a one-time catch-up read plus
/// `startRealtimeSync`/`stopRealtimeSync` for ongoing Postgres Changes
/// delivery. Lives in this package — imported by both app targets — rather
/// than in a per-target file, because it has no dependency on AppStore (an
/// app-target type a shared package cannot import).
///
/// Deliberately does NOT conform to BadmintonCore.SyncEngine itself: that
/// conformance needs to read AppStore.shared's live roster/history/settings
/// by id and re-encode via PersistenceStore (the same "materialize fresh
/// from the live cache" pattern CloudKitSyncManager already uses) — AppStore
/// is per-target, so that adapter is a separate per-target
/// SupabaseSyncEngine type that calls into this class, mirroring how
/// CloudKitSyncManager itself is duplicated per target rather than shared.
///
/// Covers the Phase 9c tier (settings + personal players/match_records) and,
/// as of Phase 9d, clubs/challenges/reactions. Phase 9e-1 adds
/// friend_requests push (`sendFriendRequest`/`respondToFriendRequest`) and
/// discoverable-profile lookup (`fetchProfileDisplayName`, reusing the
/// `profiles` table 9d-3 already populates) — the pull side needs no new
/// method since `friend_requests` fits the existing id-keyed
/// `fetchAllRows`/Realtime machinery unchanged. Phase 9e-2 adds
/// friend_identity_snapshots/friend_stats_snapshots upsert/remove — both
/// also id+payload, so they too reuse `fetchAllRows`/Realtime unchanged.
///
/// A `players`/`match_records` row awaiting upsert — a named type rather
/// than a 4-element tuple so SwiftLint's large_tuple rule (max 2 members)
/// doesn't fire at every call site building a batch.
public struct PendingRecord: Sendable {
    public let id: UUID
    public let ownerId: UUID
    public let clubId: UUID?
    public let payload: Data

    public init(id: UUID, ownerId: UUID, clubId: UUID?, payload: Data) {
        self.id = id
        self.ownerId = ownerId
        self.clubId = clubId
        self.payload = payload
    }
}

/// A `clubs` row awaiting upsert — `clubs` has no `club_id` column (a club
/// isn't itself scoped to a club), so `PendingRecord`'s shape doesn't fit.
public struct ClubPendingRecord: Sendable {
    public let id: UUID
    public let ownerId: UUID
    public let payload: Data

    public init(id: UUID, ownerId: UUID, payload: Data) {
        self.id = id
        self.ownerId = ownerId
        self.payload = payload
    }
}

/// A `challenges` row awaiting upsert — no single `owner_id` column, two
/// participant ids instead, and `club_id` is required (not optional).
public struct ChallengePendingRecord: Sendable {
    public let id: UUID
    public let clubId: UUID
    public let fromParticipantId: UUID
    public let toParticipantId: UUID
    public let payload: Data

    public init(id: UUID, clubId: UUID, fromParticipantId: UUID, toParticipantId: UUID, payload: Data) {
        self.id = id
        self.clubId = clubId
        self.fromParticipantId = fromParticipantId
        self.toParticipantId = toParticipantId
        self.payload = payload
    }
}

/// A `reactions` row awaiting upsert — `author_id` instead of `owner_id`,
/// plus a required `match_id`.
public struct ReactionPendingRecord: Sendable {
    public let id: UUID
    public let clubId: UUID
    public let matchId: UUID
    public let authorId: UUID
    public let payload: Data

    public init(id: UUID, clubId: UUID, matchId: UUID, authorId: UUID, payload: Data) {
        self.id = id
        self.clubId = clubId
        self.matchId = matchId
        self.authorId = authorId
        self.payload = payload
    }
}

@MainActor
public final class SupabaseSyncManager: ObservableObject {
    public static let shared = SupabaseSyncManager()

    @Published public private(set) var isSignedIn = false
    @Published public private(set) var statusMessage = "Not signed in"
    @Published public private(set) var log: [String] = []

    private let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.projectURL,
            supabaseKey: SupabaseConfig.anonKey
        )
    }

    /// Public hook so AppDelegate/WatchAppDelegate (outside this client) can
    /// surface WCSession relay diagnostics into the same log.
    public func logDiagnostic(_ message: String) {
        appendLog(message)
    }

    private func appendLog(_ message: String) {
        log.append(message)
    }

    // MARK: - Auth

    #if os(iOS)
    /// Drives the Google OAuth handshake via `ASWebAuthenticationSession`
    /// (wrapped internally by supabase-swift's `signInWithOAuth`). Only
    /// meaningful on iOS — watchOS has no in-app browser to present.
    public func signInWithGoogle(presentationAnchor: ASPresentationAnchor) async {
        do {
            try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: SupabaseConfig.authCallbackURL
            ) { session in
                session.presentationContextProvider = SyncPresentationContextProvider(anchor: presentationAnchor)
            }
            isSignedIn = true
            statusMessage = "Signed in"
            appendLog("Signed in with Google")
        } catch {
            statusMessage = "Sign-in failed: \(error.localizedDescription)"
            appendLog(statusMessage)
        }
    }

    /// Call after `signInWithGoogle` succeeds, to hand the session to the
    /// paired watch over WCSession.
    public func relayableSessionTokens() async -> [String: Any]? {
        guard let session = try? await client.auth.session else { return nil }
        return [
            "accessToken": session.accessToken,
            "refreshToken": session.refreshToken
        ]
    }
    #endif

    /// Watch-side entry point: adopt a session relayed from the iPhone over
    /// WCSession rather than performing OAuth locally.
    public func adoptRelayedSession(accessToken: String, refreshToken: String) async {
        do {
            try await client.auth.setSession(accessToken: accessToken, refreshToken: refreshToken)
            isSignedIn = true
            statusMessage = "Adopted relayed session"
            appendLog("Adopted session relayed from iPhone")
        } catch {
            statusMessage = "Failed to adopt relayed session: \(error.localizedDescription)"
            appendLog(statusMessage)
        }
    }

    /// The signed-in user's id — the `owner_id` for every personal row this
    /// device writes. Nil until signed in (or if the session has expired).
    public func currentUserId() async -> UUID? {
        try? await client.auth.session.user.id
    }

    // MARK: - Personal data CRUD (players / match_records / settings)

    public func upsertPlayer(id: UUID, ownerId: UUID, clubId: UUID?, payload: Data) async {
        await upsertPlayers([PendingRecord(id: id, ownerId: ownerId, clubId: clubId, payload: payload)])
    }

    public func deletePlayer(id: UUID) async {
        await deletePlayers(ids: [id])
    }

    /// Batched upsert — a single request for N rows rather than N requests,
    /// used both by a normal multi-record save and by migration-on-signin's
    /// one-time upload of a user's full existing roster.
    public func upsertPlayers(_ items: [PendingRecord]) async {
        let rows = items.compactMap { PayloadRow(id: $0.id, ownerId: $0.ownerId, clubId: $0.clubId, payloadData: $0.payload) }
        guard rows.count == items.count else {
            appendLog("Upsert players failed: a payload did not decode as JSON")
            return
        }
        await upsertRows(table: "players", rows: rows)
    }

    public func deletePlayers(ids: [UUID]) async {
        await deleteRows(table: "players", ids: ids)
    }

    public func upsertMatchRecord(id: UUID, ownerId: UUID, clubId: UUID?, payload: Data) async {
        await upsertMatchRecords([PendingRecord(id: id, ownerId: ownerId, clubId: clubId, payload: payload)])
    }

    public func deleteMatchRecord(id: UUID) async {
        await deleteMatchRecords(ids: [id])
    }

    public func upsertMatchRecords(_ items: [PendingRecord]) async {
        let rows = items.compactMap { PayloadRow(id: $0.id, ownerId: $0.ownerId, clubId: $0.clubId, payloadData: $0.payload) }
        guard rows.count == items.count else {
            appendLog("Upsert match_records failed: a payload did not decode as JSON")
            return
        }
        await upsertRows(table: "match_records", rows: rows)
    }

    public func deleteMatchRecords(ids: [UUID]) async {
        await deleteRows(table: "match_records", ids: ids)
    }

    /// `settings` has no `id` column — one row per user, keyed by `owner_id`.
    public func upsertSettings(ownerId: UUID, payload: Data) async {
        guard let row = SettingsRow(ownerId: ownerId, payloadData: payload) else {
            appendLog("Upsert settings failed: payload did not decode as JSON")
            return
        }
        await upsertRows(table: "settings", rows: [row], onConflict: "owner_id")
    }

    // MARK: - Club data CRUD (clubs / challenges / reactions, Phase 9d)

    public func upsertClubs(_ items: [ClubPendingRecord]) async {
        let rows = items.compactMap { ClubRow(id: $0.id, ownerId: $0.ownerId, payloadData: $0.payload) }
        guard rows.count == items.count else {
            appendLog("Upsert clubs failed: a payload did not decode as JSON")
            return
        }
        await upsertRows(table: "clubs", rows: rows)
    }

    public func deleteClubs(ids: [UUID]) async {
        await deleteRows(table: "clubs", ids: ids)
    }

    public func upsertChallenges(_ items: [ChallengePendingRecord]) async {
        let rows = items.compactMap {
            ChallengeRow(
                id: $0.id, clubId: $0.clubId,
                fromParticipantId: $0.fromParticipantId, toParticipantId: $0.toParticipantId,
                payloadData: $0.payload
            )
        }
        guard rows.count == items.count else {
            appendLog("Upsert challenges failed: a payload did not decode as JSON")
            return
        }
        await upsertRows(table: "challenges", rows: rows)
    }

    public func deleteChallenges(ids: [UUID]) async {
        await deleteRows(table: "challenges", ids: ids)
    }

    public func upsertReactions(_ items: [ReactionPendingRecord]) async {
        let rows = items.compactMap {
            ReactionRow(id: $0.id, clubId: $0.clubId, matchId: $0.matchId, authorId: $0.authorId, payloadData: $0.payload)
        }
        guard rows.count == items.count else {
            appendLog("Upsert reactions failed: a payload did not decode as JSON")
            return
        }
        await upsertRows(table: "reactions", rows: rows)
    }

    public func deleteReactions(ids: [UUID]) async {
        await deleteRows(table: "reactions", ids: ids)
    }

    // MARK: - Club invites (Phase 9d-2)
    //
    // The Supabase-active alternative to CloudKit's CKShare invite
    // (UICloudSharingController, iOS-only): a club owner creates a
    // `club_invites` row and shares its id as a `ClubInviteLink` URL;
    // anyone who opens it redeems it through `redeem_club_invite`, a
    // SECURITY DEFINER Postgres function (supabase/schema.sql) — club_
    // members has no direct INSERT policy, so this RPC is the only way to
    // join a club you don't own, mirroring how handle_new_club() already
    // bypasses the caller's own (nonexistent) insert privilege for owners.

    /// Owner-only (RLS: `club_invites_insert` requires `is_club_owner`).
    /// Returns the new invite's id for building a `ClubInviteLink.url`, or
    /// nil on failure (not signed in, or the request itself errored).
    public func createClubInvite(clubId: UUID, expiresAt: Date? = nil, maxUses: Int? = nil) async -> UUID? {
        guard let uid = await currentUserId() else { return nil }
        let row = NewClubInviteRow(clubId: clubId, createdBy: uid, expiresAt: expiresAt, maxUses: maxUses)
        do {
            let inserted: InsertedClubInvite = try await client
                .from("club_invites")
                .insert(row)
                .select()
                .single()
                .execute()
                .value
            appendLog("Created club invite")
            return inserted.id
        } catch {
            appendLog("Create club invite failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Validates and redeems an invite via the `redeem_club_invite` RPC,
    /// returning the joined club's id on success. Fails (returns nil) if
    /// the invite doesn't exist, is expired, or has hit `max_uses` — the
    /// function raises a Postgres exception in each of those cases, which
    /// surfaces here as a thrown error and is logged, not distinguished by
    /// case (the caller only needs to know join-succeeded vs. join-failed).
    public func redeemClubInvite(inviteId: UUID) async -> UUID? {
        do {
            let clubId: UUID = try await client
                .rpc("redeem_club_invite", params: RedeemClubInviteParams(inviteId: inviteId))
                .execute()
                .value
            appendLog("Redeemed club invite")
            return clubId
        } catch {
            appendLog("Redeem club invite failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Club membership (Phase 9d-3)
    //
    // The Supabase-active alternative to reading a live CKShare's
    // `participants` list: `club_members` rows joined against `profiles` for
    // a display name. `club_members_select`/`_delete` RLS (schema.sql)
    // already allows a member to read their club's roster and remove
    // themselves, and the owner to remove anyone — no new SQL needed here,
    // unlike 9d-2's invite RPC.

    /// Upserts this signed-in user's own `profiles` row — the thing
    /// `fetchClubMembers` joins against for a display name. `profiles` was
    /// created by 9a but deliberately left unpopulated until now (schema.sql
    /// deferred it to "9e Friends"); club membership needs *a* name to show
    /// sooner than that, so this narrow slice populates just the caller's own
    /// row. Safe to call repeatedly (upsert, keyed by `id`).
    public func upsertMyProfile(displayName: String) async {
        guard let uid = await currentUserId() else { return }
        do {
            try await client.from("profiles").upsert(ProfileRow(id: uid, displayName: displayName)).execute()
            appendLog("Upserted profile")
        } catch {
            appendLog("Upsert profile failed: \(error.localizedDescription)")
        }
    }

    /// One row per club member, resolved with a display name where a
    /// `profiles` row exists (falls back to the raw id string otherwise —
    /// e.g. a member who joined before ever calling `upsertMyProfile`, which
    /// only happens for a fresh Supabase activation, not a steady-state gap).
    /// Two queries rather than a PostgREST embed: `club_members`/`profiles`
    /// both reference `auth.users`, not each other, so there's no FK for
    /// PostgREST to embed across.
    public func fetchClubMembers(clubId: UUID) async -> [ClubMemberSummary] {
        do {
            let memberRows: [ClubMemberRow] = try await client
                .from("club_members")
                .select()
                .eq("club_id", value: clubId)
                .execute()
                .value
            guard !memberRows.isEmpty else { return [] }
            let profileRows: [ProfileRow] = try await client
                .from("profiles")
                .select()
                .in("id", values: memberRows.map { $0.userId as any PostgrestFilterValue })
                .execute()
                .value
            let namesById = Dictionary(uniqueKeysWithValues: profileRows.map { ($0.id, $0.displayName) })
            return memberRows.map { row in
                ClubMemberSummary(userId: row.userId, role: row.role, displayName: namesById[row.userId] ?? row.userId.uuidString)
            }
        } catch {
            appendLog("Fetch club members failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Removes the caller's own membership row (RLS: `user_id = auth.uid()`).
    public func leaveClub(clubId: UUID) async {
        guard let uid = await currentUserId() else { return }
        do {
            try await client.from("club_members").delete().eq("club_id", value: clubId).eq("user_id", value: uid).execute()
            appendLog("Left club")
        } catch {
            appendLog("Leave club failed: \(error.localizedDescription)")
        }
    }

    /// Owner-only kick (RLS: `club_members_delete` also allows `is_club_owner`).
    /// A non-owner caller's request simply matches zero rows under RLS rather
    /// than erroring, same fail-closed shape as every other owner-gated write.
    public func removeMember(clubId: UUID, userId: UUID) async {
        do {
            try await client.from("club_members").delete().eq("club_id", value: clubId).eq("user_id", value: userId).execute()
            appendLog("Removed club member")
        } catch {
            appendLog("Remove club member failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Friend requests / profile lookup (Phase 9e-1)
    //
    // This package has no BadmintonCore dependency (see file header), so
    // these methods work in raw ids/strings/Data rather than
    // BadmintonCore.FriendProfile/FriendRequest — each target's View or
    // SupabaseSyncEngine builds/decodes the real model around these calls,
    // same "primitives here, models per-target" split every other method in
    // this file already follows. `friend_requests` itself is id-primary-keyed
    // like players/match_records/clubs/challenges/reactions, so the pull side
    // needs no bespoke fetch method at all — `fetchAllRows(table:
    // "friend_requests")` (below) already covers it, RLS-scoped like every
    // other table.

    public enum FriendRequestError: Error {
        case selfRequest
        case alreadyPending
    }

    /// Resolves a display name for a discoverable `profiles` row — the
    /// Supabase-active equivalent of CloudKit's `fetchProfile`, used to show
    /// "X wants to add you" when consuming an invite link/code. Fails soft
    /// (nil) rather than throwing, same as the CloudKit method.
    public func fetchProfileDisplayName(participantId: UUID) async -> String? {
        do {
            let rows: [ProfileRow] = try await client
                .from("profiles")
                .select()
                .eq("id", value: participantId)
                .execute()
                .value
            return rows.first?.displayName
        } catch {
            appendLog("Fetch profile failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Guards against a self-request and an existing pending request in
    /// either direction (mirrors CloudKit's `sendFriendRequest`'s bidirectional
    /// check — the DB's own `unique (from_participant_id, to_participant_id)`
    /// constraint is directional and only a backstop, not the primary guard),
    /// then inserts a new `friend_requests` row. `payload` is the caller's
    /// already-`PersistenceStore.encodeFriendRequest`-encoded FriendRequest.
    public func sendFriendRequest(id: UUID, fromParticipantId: UUID, toParticipantId: UUID, payload: Data) async throws {
        guard fromParticipantId != toParticipantId else { throw FriendRequestError.selfRequest }
        let existing: [FriendRequestStatusRow] = (try? await client
            .from("friend_requests")
            .select("from_participant_id, to_participant_id, status")
            .execute()
            .value) ?? []
        let alreadyPending = existing.contains { row in
            row.status == "pending" &&
            ((row.fromParticipantId == fromParticipantId && row.toParticipantId == toParticipantId) ||
             (row.fromParticipantId == toParticipantId && row.toParticipantId == fromParticipantId))
        }
        guard !alreadyPending else { throw FriendRequestError.alreadyPending }
        guard let row = NewFriendRequestRow(
            id: id, fromParticipantId: fromParticipantId, toParticipantId: toParticipantId, payloadData: payload
        ) else {
            appendLog("Send friend request failed: payload did not decode as JSON")
            return
        }
        do {
            try await client.from("friend_requests").insert(row).execute()
            appendLog("Sent friend request")
        } catch {
            appendLog("Send friend request failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Flips `status` and re-saves the full payload in one write — same
    /// mutate-don't-delete convention as CloudKit's `respondToFriendRequest`.
    /// `status`/`payload` are both the caller's responsibility to keep in
    /// sync (the caller flips `FriendRequest.status` then re-encodes).
    public func respondToFriendRequest(id: UUID, status: String, payload: Data) async {
        guard let row = FriendRequestUpdateRow(status: status, payloadData: payload) else {
            appendLog("Respond to friend request failed: payload did not decode as JSON")
            return
        }
        do {
            try await client.from("friend_requests").update(row).eq("id", value: id).execute()
            appendLog("Responded to friend request")
        } catch {
            appendLog("Respond to friend request failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Erase All My Data teardown (Phase 9e-4)
    //
    // The Supabase-active counterpart to CloudKitSyncManager's
    // deleteMyFriendProfile()/deleteAllMyFriendRequests(), called from
    // AppStore.eraseAllData() via SupabaseSyncEngine. There is no zone
    // concept here (unlike CloudKit's FriendsHistory CKShare zone), so
    // there's no third teardown method to add — see SupabaseSyncEngine's
    // deleteFriendsHistoryZone() doc comment for why that one stays a
    // documented no-op.

    /// Deletes the caller's own `profiles` row (schema.sql's `profiles_delete`
    /// policy, added in this same slice — nothing needed a profile delete
    /// until now).
    public func deleteMyProfile() async {
        guard let uid = await currentUserId() else { return }
        do {
            try await client.from("profiles").delete().eq("id", value: uid).execute()
            appendLog("Deleted profile")
        } catch {
            appendLog("Delete profile failed: \(error.localizedDescription)")
        }
    }

    /// Deletes every `friend_requests` row the caller is party to, on either
    /// side — mirrors `fetchMyFriendRequests`'s/CloudKit's own bidirectional
    /// intent. `friend_requests_delete` RLS (widened to either-party in 9e-1)
    /// already scopes this correctly on its own, but the explicit `.or()`
    /// filter keeps the query's intent readable rather than leaning on RLS
    /// alone to narrow an unfiltered delete.
    public func deleteAllFriendRequests() async {
        guard let uid = await currentUserId() else { return }
        do {
            try await client
                .from("friend_requests")
                .delete()
                .or("from_participant_id.eq.\(uid),to_participant_id.eq.\(uid)")
                .execute()
            appendLog("Deleted all friend requests")
        } catch {
            appendLog("Delete all friend requests failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Friend identity / stats sharing (Phase 9e-2)
    //
    // `friend_identity_snapshots`/`friend_stats_snapshots` are id+payload
    // like every other table (see schema.sql's comment on why — NOT RLS
    // granted directly on `settings`), so these reuse `upsertRows`/
    // `deleteRows`/`fetchAllRows`/Realtime unchanged; no bespoke row types
    // needed beyond `IdPayloadRow` below.

    public func upsertFriendIdentitySnapshot(id: UUID, payload: Data) async {
        guard let row = IdPayloadRow(id: id, payloadData: payload) else {
            appendLog("Upsert friend identity snapshot failed: payload did not decode as JSON")
            return
        }
        await upsertRows(table: "friend_identity_snapshots", rows: [row])
    }

    public func removeFriendIdentitySnapshot(id: UUID) async {
        await deleteRows(table: "friend_identity_snapshots", ids: [id])
    }

    public func upsertFriendStatsSnapshot(id: UUID, payload: Data) async {
        guard let row = IdPayloadRow(id: id, payloadData: payload) else {
            appendLog("Upsert friend stats snapshot failed: payload did not decode as JSON")
            return
        }
        await upsertRows(table: "friend_stats_snapshots", rows: [row])
    }

    public func removeFriendStatsSnapshot(id: UUID) async {
        await deleteRows(table: "friend_stats_snapshots", ids: [id])
    }

    private func upsertRows(table: String, rows: some Encodable, onConflict: String? = nil) async {
        do {
            try await client.from(table).upsert(rows, onConflict: onConflict).execute()
            appendLog("Upserted \(table) row(s)")
        } catch {
            appendLog("Upsert \(table) failed: \(error.localizedDescription)")
        }
    }

    private func deleteRows(table: String, ids: [UUID]) async {
        guard !ids.isEmpty else { return }
        do {
            try await client.from(table).delete().in("id", values: ids.map { $0 as any PostgrestFilterValue }).execute()
            appendLog("Deleted \(ids.count) \(table) row(s)")
        } catch {
            appendLog("Delete \(table) failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Pull-side sync (Phase 9c-5/9c-6: initial fetch + Realtime)
    //
    // Everything above this point only pushes local changes out. These
    // methods are the read-back half: an initial catch-up fetch (for data
    // that already existed remotely before this device subscribed) plus an
    // ongoing Realtime subscription (for anything that changes afterward) —
    // the same two-part shape CKSyncEngine already uses (fetchChanges() on
    // reconnect, push notifications for what comes after). Decoding the
    // returned payloads into concrete models and applying them to AppStore
    // is the per-target SupabaseSyncEngine's job, not this package's — see
    // the file header on why this class has no PersistenceStore/AppStore
    // dependency.

    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeSubscriptions: [RealtimeSubscription] = []

    /// Subscribes to INSERT/UPDATE/DELETE events on each listed table.
    /// Relies entirely on RLS to scope delivery to rows this user can
    /// actually see (own rows, plus any row visible via club membership) —
    /// Supabase's Postgres Changes feature enforces the same SELECT RLS
    /// policy for Realtime delivery as for a regular query, so this doesn't
    /// need (and, once `clubs`/`challenges`/`reactions` joined the
    /// subscription list, can't uniformly apply) a client-side `owner_id`
    /// filter: `challenges`/`reactions` don't even have an `owner_id`
    /// column, and a blanket `owner_id = this user` filter would wrongly
    /// drop legitimate updates from other members of a shared club. This is
    /// unverified by CI — it depends on the live project actually enforcing
    /// RLS on Realtime, which needs a real multi-account check (see the
    /// Phase 9d plan's manual verification section).
    ///
    /// Safe to call repeatedly: always tears down any existing subscription
    /// first, so re-activating after a sign-out/sign-in doesn't leak a
    /// stale channel.
    public func startRealtimeSync(tables: [String], onChange: @escaping @Sendable (RemoteChange) -> Void) async {
        await stopRealtimeSync()
        guard let uid = await currentUserId() else {
            appendLog("Realtime sync not started: not signed in")
            return
        }
        let channel = client.channel("personal-sync-\(uid.uuidString)")
        var subscriptions: [RealtimeSubscription] = []
        for table in tables {
            let subscription = channel.onPostgresChange(
                AnyAction.self,
                schema: "public",
                table: table
            ) { [weak self] action in
                guard let change = Self.remoteChange(table: table, action: action) else { return }
                Task { @MainActor in
                    self?.appendLog("Realtime \(table) change received")
                }
                onChange(change)
            }
            subscriptions.append(subscription)
        }
        do {
            try await channel.subscribeWithError()
            realtimeChannel = channel
            realtimeSubscriptions = subscriptions
            appendLog("Realtime sync subscribed: \(tables.joined(separator: ", "))")
        } catch {
            appendLog("Realtime sync failed to subscribe: \(error.localizedDescription)")
        }
    }

    /// Idempotent — safe to call even if no subscription is active (e.g.
    /// `deactivateSupabaseSync()` running before any sign-in ever happened).
    public func stopRealtimeSync() async {
        guard let channel = realtimeChannel else { return }
        await channel.unsubscribe()
        realtimeChannel = nil
        realtimeSubscriptions = []
        appendLog("Realtime sync unsubscribed")
    }

    // `nonisolated` — the Realtime SDK invokes this callback off the main
    // actor, and this pure decode has no instance/static mutable state to
    // protect, so it doesn't need to hop actors just to run.
    private nonisolated static func remoteChange(table: String, action: AnyAction) -> RemoteChange? {
        switch action {
        case .insert(let insert):
            return remoteChange(table: table, kind: .upsert, record: insert.record)
        case .update(let update):
            return remoteChange(table: table, kind: .upsert, record: update.record)
        case .delete(let delete):
            return remoteChange(table: table, kind: .delete, record: delete.oldRecord)
        }
    }

    private nonisolated static func remoteChange(table: String, kind: RemoteChange.Kind, record: [String: AnyJSON]) -> RemoteChange? {
        // `settings` has no `id` column (see `upsertSettings`) — its only
        // key is `owner_id`, so that's what identifies its one row here too.
        let idKey = table == "settings" ? "owner_id" : "id"
        guard let idString = record[idKey]?.stringValue, let id = UUID(uuidString: idString) else { return nil }
        // Present on players/match_records/clubs/settings; absent on
        // challenges/reactions (see `RemoteChange.ownerId`'s doc comment).
        let ownerId = record["owner_id"]?.stringValue.flatMap { UUID(uuidString: $0) }
        // Present on players/match_records/challenges/reactions; absent
        // elsewhere.
        let clubId = record["club_id"]?.stringValue.flatMap { UUID(uuidString: $0) }
        guard kind == .upsert else {
            return RemoteChange(table: table, id: id, kind: kind, payload: nil, ownerId: ownerId, clubId: clubId)
        }
        guard let payload = record["payload"], let payloadData = try? JSONEncoder().encode(payload) else { return nil }
        return RemoteChange(table: table, id: id, kind: kind, payload: payloadData, ownerId: ownerId, clubId: clubId)
    }

    /// One-time catch-up read of every row this user can see in `table`
    /// (own rows, plus — for club-visible tables — any row visible via club
    /// membership), used at Supabase activation/launch to backfill data
    /// that already existed remotely (written by another device or user, or
    /// from before this device ever subscribed) before the Realtime
    /// subscription above takes over for anything that happens next. Relies
    /// on RLS alone to scope the result, same reasoning as
    /// `startRealtimeSync` — no client-side `owner_id` filter, since that
    /// would wrongly exclude club rows owned by someone else. Never reports
    /// `.delete` — a full fetch only sees what currently exists, so it has
    /// no way to know about a row that was deleted before this device ever
    /// saw it; the caller isn't expected to diff against local state for
    /// tombstones here.
    public func fetchAllRows(table: String) async -> [RemoteChange] {
        guard await currentUserId() != nil else { return [] }
        do {
            let rows: [SelectedRow] = try await client
                .from(table)
                .select()
                .execute()
                .value
            return rows.compactMap { row in
                guard let payload = try? JSONEncoder().encode(row.payload) else { return nil }
                return RemoteChange(table: table, id: row.id, kind: .upsert, payload: payload, ownerId: row.ownerId, clubId: row.clubId)
            }
        } catch {
            appendLog("Fetch \(table) failed: \(error.localizedDescription)")
            return []
        }
    }

    /// `settings`-specific counterpart to `fetchAllRows` — the row is keyed
    /// by `owner_id` rather than `id` (mirroring why `upsertSettings`
    /// doesn't reuse `upsertRows(table:rows:)`'s generic `id`-keyed shape),
    /// so the returned `RemoteChange.id` is the user's own id, not a row id.
    public func fetchSettings() async -> RemoteChange? {
        guard let uid = await currentUserId() else { return nil }
        do {
            let rows: [SelectedSettingsRow] = try await client
                .from("settings")
                .select()
                .eq("owner_id", value: uid)
                .execute()
                .value
            guard let row = rows.first, let payload = try? JSONEncoder().encode(row.payload) else { return nil }
            return RemoteChange(table: "settings", id: uid, kind: .upsert, payload: payload, ownerId: uid, clubId: nil)
        } catch {
            appendLog("Fetch settings failed: \(error.localizedDescription)")
            return nil
        }
    }
}

/// A change to a row on a subscribed table, normalized from either a
/// Realtime `postgres_changes` event or a `fetchAllRows`/`fetchSettings`
/// catch-up read. Carries only raw identifiers/bytes — decoding `payload`
/// into a concrete model is the per-target SupabaseSyncEngine's job.
public struct RemoteChange: Sendable {
    public enum Kind: Sendable {
        case upsert
        case delete
    }

    public let table: String
    public let id: UUID
    public let kind: Kind
    /// The row's `payload jsonb` column re-encoded as `Data`, matching the
    /// shape `PersistenceStore.encode*(_:)` produces. Present for `.upsert`,
    /// nil for `.delete` (a delete event carries no payload left to decode).
    public let payload: Data?
    /// The row's raw `owner_id` column, when the table has one
    /// (`players`/`match_records`/`clubs`/`settings`) — nil for
    /// `challenges`/`reactions`, which have no single owner column. Exists
    /// so a receiving device can determine real ownership from
    /// server-supplied row data rather than trusting a payload field the
    /// pushing device encoded from its own point of view — e.g.
    /// `Club.ownerRecordName`, which the owner always encodes as `nil`
    /// (they ARE the owner); a receiving member must not adopt that as-is.
    public let ownerId: UUID?
    /// The row's raw `club_id` column, when the table has one
    /// (`players`/`match_records`/`challenges`/`reactions`) — nil otherwise.
    /// Exists so a `.delete` event (no `payload` to decode a model's own
    /// `clubId` from) can still be routed correctly — see
    /// `SupabaseSyncEngine`'s personal-vs-club-vs-friend routing (Phase
    /// 9e-3).
    public let clubId: UUID?
}

/// One resolved club member, returned by `SupabaseSyncManager.fetchClubMembers`.
public struct ClubMemberSummary: Sendable, Identifiable {
    public var id: UUID { userId }
    public let userId: UUID
    public let role: String
    public let displayName: String
}

private struct ProfileRow: Codable {
    let id: UUID
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

private struct ClubMemberRow: Decodable {
    let userId: UUID
    let role: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case role
    }
}

private struct FriendRequestStatusRow: Decodable {
    let fromParticipantId: UUID
    let toParticipantId: UUID
    let status: String

    enum CodingKeys: String, CodingKey {
        case fromParticipantId = "from_participant_id"
        case toParticipantId = "to_participant_id"
        case status
    }
}

private struct NewFriendRequestRow: Encodable {
    let id: UUID
    let fromParticipantId: UUID
    let toParticipantId: UUID
    let payload: AnyJSON

    enum CodingKeys: String, CodingKey {
        case id
        case fromParticipantId = "from_participant_id"
        case toParticipantId = "to_participant_id"
        case payload
    }

    init?(id: UUID, fromParticipantId: UUID, toParticipantId: UUID, payloadData: Data) {
        guard let payload = try? JSONDecoder().decode(AnyJSON.self, from: payloadData) else { return nil }
        self.id = id
        self.fromParticipantId = fromParticipantId
        self.toParticipantId = toParticipantId
        self.payload = payload
    }
}

private struct FriendRequestUpdateRow: Encodable {
    let status: String
    let payload: AnyJSON

    init?(status: String, payloadData: Data) {
        guard let payload = try? JSONDecoder().decode(AnyJSON.self, from: payloadData) else { return nil }
        self.status = status
        self.payload = payload
    }
}

/// A generic `id`+`payload` row for tables that need nothing else —
/// `friend_identity_snapshots`/`friend_stats_snapshots` (Phase 9e-2), where
/// `id` is the owning participant's `auth.uid()` and RLS reads only that PK.
private struct IdPayloadRow: Encodable {
    let id: UUID
    let payload: AnyJSON

    init?(id: UUID, payloadData: Data) {
        guard let payload = try? JSONDecoder().decode(AnyJSON.self, from: payloadData) else { return nil }
        self.id = id
        self.payload = payload
    }
}

private struct SelectedRow: Decodable {
    let id: UUID
    let payload: AnyJSON
    let ownerId: UUID?
    let clubId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case payload
        case ownerId = "owner_id"
        case clubId = "club_id"
    }
}

private struct SelectedSettingsRow: Decodable {
    let payload: AnyJSON
}

/// `payload jsonb` needs an `AnyJSON`-typed field, not raw `Data` — `Data`
/// would encode as a base64 string instead of a nested JSON value. The
/// initializer decodes each PersistenceStore.encode*(_:) Data blob into one.
private struct PayloadRow: Encodable {
    let id: UUID
    let ownerId: UUID
    let clubId: UUID?
    let payload: AnyJSON

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case clubId = "club_id"
        case payload
    }

    init?(id: UUID, ownerId: UUID, clubId: UUID?, payloadData: Data) {
        guard let payload = try? JSONDecoder().decode(AnyJSON.self, from: payloadData) else { return nil }
        self.id = id
        self.ownerId = ownerId
        self.clubId = clubId
        self.payload = payload
    }
}

private struct SettingsRow: Encodable {
    let ownerId: UUID
    let payload: AnyJSON

    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
        case payload
    }

    init?(ownerId: UUID, payloadData: Data) {
        guard let payload = try? JSONDecoder().decode(AnyJSON.self, from: payloadData) else { return nil }
        self.ownerId = ownerId
        self.payload = payload
    }
}

private struct ClubRow: Encodable {
    let id: UUID
    let ownerId: UUID
    let payload: AnyJSON

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case payload
    }

    init?(id: UUID, ownerId: UUID, payloadData: Data) {
        guard let payload = try? JSONDecoder().decode(AnyJSON.self, from: payloadData) else { return nil }
        self.id = id
        self.ownerId = ownerId
        self.payload = payload
    }
}

private struct ChallengeRow: Encodable {
    let id: UUID
    let clubId: UUID
    let fromParticipantId: UUID
    let toParticipantId: UUID
    let payload: AnyJSON

    enum CodingKeys: String, CodingKey {
        case id
        case clubId = "club_id"
        case fromParticipantId = "from_participant_id"
        case toParticipantId = "to_participant_id"
        case payload
    }

    init?(id: UUID, clubId: UUID, fromParticipantId: UUID, toParticipantId: UUID, payloadData: Data) {
        guard let payload = try? JSONDecoder().decode(AnyJSON.self, from: payloadData) else { return nil }
        self.id = id
        self.clubId = clubId
        self.fromParticipantId = fromParticipantId
        self.toParticipantId = toParticipantId
        self.payload = payload
    }
}

private struct ReactionRow: Encodable {
    let id: UUID
    let clubId: UUID
    let matchId: UUID
    let authorId: UUID
    let payload: AnyJSON

    enum CodingKeys: String, CodingKey {
        case id
        case clubId = "club_id"
        case matchId = "match_id"
        case authorId = "author_id"
        case payload
    }

    init?(id: UUID, clubId: UUID, matchId: UUID, authorId: UUID, payloadData: Data) {
        guard let payload = try? JSONDecoder().decode(AnyJSON.self, from: payloadData) else { return nil }
        self.id = id
        self.clubId = clubId
        self.matchId = matchId
        self.authorId = authorId
        self.payload = payload
    }
}

private struct NewClubInviteRow: Encodable {
    let clubId: UUID
    let createdBy: UUID
    let expiresAt: Date?
    let maxUses: Int?

    enum CodingKeys: String, CodingKey {
        case clubId = "club_id"
        case createdBy = "created_by"
        case expiresAt = "expires_at"
        case maxUses = "max_uses"
    }
}

private struct InsertedClubInvite: Decodable {
    let id: UUID
}

private struct RedeemClubInviteParams: Encodable {
    let inviteId: UUID

    enum CodingKeys: String, CodingKey {
        case inviteId = "invite_id"
    }
}

#if os(iOS)
private final class SyncPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
#endif
