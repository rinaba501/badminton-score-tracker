import Combine
import Foundation
import Supabase
#if os(iOS)
import AuthenticationServices
#endif

/// A test row written/read by the spike UI — deliberately separate from
/// BadmintonCore.MatchRecord. This client never touches real app data.
public struct SpikeTestRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let ownerId: UUID
    public let note: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case note
        case createdAt = "created_at"
    }
}

/// Thin wrapper around supabase-swift for the Postgres/Google-OAuth feasibility
/// spike (see CloudSyncSpikeView). iOS performs the actual OAuth handshake;
/// watchOS never does — it only ever adopts a session relayed over WCSession
/// from the paired iPhone, since watchOS has no in-app browser.
@MainActor
public final class SupabaseSpikeClient: ObservableObject {
    public static let shared = SupabaseSpikeClient()

    @Published public private(set) var isSignedIn = false
    @Published public private(set) var statusMessage = "Not signed in"
    @Published public private(set) var log: [String] = []

    private let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseSpikeConfig.projectURL,
            supabaseKey: SupabaseSpikeConfig.anonKey
        )
    }

    /// Public hook so AppDelegate/WatchAppDelegate (outside this client) can
    /// surface WCSession diagnostics into the same on-screen log, since the
    /// log files this spike's build tooling captures turned out to be empty.
    public func logDiagnostic(_ message: String) {
        appendLog(message)
    }

    private func appendLog(_ message: String) {
        log.append(message)
    }

    #if os(iOS)
    /// Drives the Google OAuth handshake via `ASWebAuthenticationSession`
    /// (wrapped internally by supabase-swift's `signInWithOAuth`). Only
    /// meaningful on iOS — watchOS has no in-app browser to present.
    public func signInWithGoogle(presentationAnchor: ASPresentationAnchor) async {
        do {
            try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: SupabaseSpikeConfig.authCallbackURL
            ) { session in
                session.presentationContextProvider = SpikePresentationContextProvider(anchor: presentationAnchor)
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
    /// paired watch. Returns nil until a session exists.
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

    public func insertTestRecord(note: String) async {
        do {
            guard let userId = try? await client.auth.session.user.id else {
                appendLog("Insert failed: no signed-in user")
                return
            }
            let record = SpikeTestRecord(id: UUID(), ownerId: userId, note: note, createdAt: Date())
            try await client.from("match_records")
                .insert(record)
                .execute()
            appendLog("Inserted test record: \(note)")
        } catch {
            appendLog("Insert failed: \(error.localizedDescription)")
        }
    }

    public func fetchTestRecords() async -> [SpikeTestRecord] {
        do {
            let records: [SpikeTestRecord] = try await client.from("match_records")
                .select()
                .execute()
                .value
            appendLog("Fetched \(records.count) record(s)")
            return records
        } catch {
            appendLog("Fetch failed: \(error.localizedDescription)")
            return []
        }
    }
}

#if os(iOS)
private final class SpikePresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
#endif
