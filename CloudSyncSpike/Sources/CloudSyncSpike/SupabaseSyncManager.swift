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
/// as of Phase 9d, clubs/challenges/reactions — friends-* CRUD arrives
/// with 9e.
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
        guard kind == .upsert else {
            return RemoteChange(table: table, id: id, kind: kind, payload: nil, ownerId: ownerId)
        }
        guard let payload = record["payload"], let payloadData = try? JSONEncoder().encode(payload) else { return nil }
        return RemoteChange(table: table, id: id, kind: kind, payload: payloadData, ownerId: ownerId)
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
                return RemoteChange(table: table, id: row.id, kind: .upsert, payload: payload, ownerId: row.ownerId)
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
            return RemoteChange(table: "settings", id: uid, kind: .upsert, payload: payload, ownerId: uid)
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
}

private struct SelectedRow: Decodable {
    let id: UUID
    let payload: AnyJSON
    let ownerId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case payload
        case ownerId = "owner_id"
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
