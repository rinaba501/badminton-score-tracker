import Foundation

/// projectURL/anonKey resolve from environment variables so CI (which never
/// sets them) compiles cleanly against the placeholder fallback, and a real
/// Supabase project's values never have to touch a git-tracked file. Set them
/// locally via Xcode: Product > Scheme > Edit Scheme > Run > Arguments >
/// Environment Variables (SUPABASE_SPIKE_URL / SUPABASE_SPIKE_ANON_KEY) —
/// keep that scheme edit unshared (User state, not Shared) so it never lands
/// in git. The publishable key itself is meant to be client-embeddable
/// (RLS-gated, not a secret) — still no reason to put it in git history.
public enum SupabaseSpikeConfig {
    public static let projectURL = URL(
        string: ProcessInfo.processInfo.environment["SUPABASE_SPIKE_URL"] ?? "https://YOUR-PROJECT-REF.supabase.co"
    )!
    public static let anonKey = ProcessInfo.processInfo.environment["SUPABASE_SPIKE_ANON_KEY"] ?? "YOUR-PUBLISHABLE-KEY"

    /// Must match a URL scheme registered in both targets' Info.plist and the
    /// redirect URL allow-list in the Supabase Auth dashboard.
    public static let authCallbackURL = URL(string: "badminton://auth-callback")!
}
