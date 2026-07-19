import Combine
import Foundation
import Supabase
#if os(iOS)
import AuthenticationServices
#endif

/// Low-level Supabase transport: auth (Google OAuth on iOS, relayed-session
/// adoption on watchOS) plus typed CRUD against the Phase 9 schema
/// (supabase/schema.sql). Lives in this package — imported by both app
/// targets — rather than in a per-target file, because it has no dependency
/// on AppStore (an app-target type a shared package cannot import).
///
/// Deliberately does NOT conform to BadmintonCore.SyncEngine itself: that
/// conformance needs to read AppStore.shared's live roster/history/settings
/// by id and re-encode via PersistenceStore (the same "materialize fresh
/// from the live cache" pattern CloudKitSyncManager already uses) — AppStore
/// is per-target, so that adapter is a separate per-target
/// SupabaseSyncEngine type that calls into this class, mirroring how
/// CloudKitSyncManager itself is duplicated per target rather than shared.
///
/// Only covers the Phase 9c tier (settings + personal players/match_records)
/// — clubs/challenges/reactions/friends-* CRUD arrives with 9d/9e.
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
        guard let row = PayloadRow(id: id, ownerId: ownerId, clubId: clubId, payloadData: payload) else {
            appendLog("Upsert players failed: payload did not decode as JSON")
            return
        }
        await upsertRow(table: "players", row: row)
    }

    public func deletePlayer(id: UUID) async {
        await deleteRow(table: "players", id: id)
    }

    public func upsertMatchRecord(id: UUID, ownerId: UUID, clubId: UUID?, payload: Data) async {
        guard let row = PayloadRow(id: id, ownerId: ownerId, clubId: clubId, payloadData: payload) else {
            appendLog("Upsert match_records failed: payload did not decode as JSON")
            return
        }
        await upsertRow(table: "match_records", row: row)
    }

    public func deleteMatchRecord(id: UUID) async {
        await deleteRow(table: "match_records", id: id)
    }

    /// `settings` has no `id` column — one row per user, keyed by `owner_id`.
    public func upsertSettings(ownerId: UUID, payload: Data) async {
        guard let row = SettingsRow(ownerId: ownerId, payloadData: payload) else {
            appendLog("Upsert settings failed: payload did not decode as JSON")
            return
        }
        await upsertRow(table: "settings", row: row, onConflict: "owner_id")
    }

    private func upsertRow(table: String, row: some Encodable, onConflict: String? = nil) async {
        do {
            try await client.from(table).upsert(row, onConflict: onConflict).execute()
            appendLog("Upserted \(table) row")
        } catch {
            appendLog("Upsert \(table) failed: \(error.localizedDescription)")
        }
    }

    private func deleteRow(table: String, id: UUID) async {
        do {
            try await client.from(table).delete().eq("id", value: id).execute()
            appendLog("Deleted \(table) row")
        } catch {
            appendLog("Delete \(table) failed: \(error.localizedDescription)")
        }
    }
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
