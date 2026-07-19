import Foundation

/// Real project URL + anon key, hardcoded rather than injected via env var
/// (the CloudSyncSpike-era pattern this replaces — see git history). The
/// anon/publishable key is designed to be client-embeddable (RLS-gated, not
/// a secret), same practice as shipping a Firebase config — Phase 9c needs
/// this to work in every build type, including TestFlight/App Store, where
/// no Xcode scheme environment variable exists.
public enum SupabaseConfig {
    public static let projectURL = URL(string: "https://ebfjhkexmefpbflilvwa.supabase.co")!
    public static let anonKey = "sb_publishable_Gt4HQEimdaWV7Xb8zR_7KA_RsubOdGh"

    /// Must match a URL scheme registered in both targets' Info.plist and the
    /// redirect URL allow-list in the Supabase Auth dashboard.
    public static let authCallbackURL = URL(string: "badminton://auth-callback")!
}
