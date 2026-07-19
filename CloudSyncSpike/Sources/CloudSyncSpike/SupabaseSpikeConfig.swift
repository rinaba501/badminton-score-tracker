import Foundation

/// Real values live in `SupabaseSpikeSecrets.swift`, a gitignored file not
/// checked into the repo — copy `SupabaseSpikeSecrets.swift.example` to
/// `SupabaseSpikeSecrets.swift` and fill in your own Supabase project's
/// values (Project Settings → API) to build the spike. Split out even though
/// the publishable key itself is meant to be client-embeddable (RLS-gated,
/// not a secret) — still no reason to put it in git history.
public enum SupabaseSpikeConfig {}
