# Backend Migration: CloudKit → Supabase/Postgres — Design

Initiative: replace CloudKit with a Postgres backend (Supabase: Postgres + Auth +
Realtime) as the app's sync/identity layer, on every platform including the
existing Watch/iOS app. This document is the reference for the implementation
phases (Phase 9 in [ROADMAP.md](../ROADMAP.md)).

**Status: 9a-9b done, 9c in progress (9c-1/9c-2/9c-3 done)** — schema + RLS
applied and verified against the Supabase project
([supabase/schema.sql](../supabase/schema.sql), all 10 tables present with
`rowsecurity = true`); the `SyncEngine` protocol
([SyncEngine.swift](../BadmintonCore/Sources/BadmintonCore/SyncEngine.swift))
sits between `AppStore` and `CloudKitSyncManager` on both targets, a pure
refactor with no behavior change; `CloudSyncSpike`'s spike client is now a
real production `SupabaseSyncManager` + per-target `SupabaseSyncEngine`
adapters (9c-1) — the DEBUG-only spike UI that proved the OAuth/WCSession-
relay approach was removed rather than kept alongside the real thing.
`AppStore.syncEngine` is swappable via `activateSupabaseSync()`/
`deactivateSupabaseSync()` (9c-2), and as of 9c-3 both targets' Settings
screens have a real "Sync Backend" section that calls them — iOS drives
Google Sign-In and relays the session to the Watch, the Watch offers its
own explicit activation once a relayed session lands. **A real-account,
two-device verification pass is still owed** (not yet exercised — same
not-CI-provable gate CloudKit sync correctness already has); 9c-4 (routing
~32 View-level `enqueueSettingsChange()` bypass call sites through
`AppStore`) is the only remaining 9c slice.

---

## 1. Goal & why

The user's motivation is to leave room to move beyond Apple devices — a future
Android or web client needs a backend that isn't CloudKit. Two shapes were
considered: keep CloudKit as the Apple app's permanent backend and give a future
non-Apple client its own separate Supabase backend (no data sharing), or do a
**full cutover** so every platform shares one real backend. The user chose full
cutover: eventually retire CloudKit entirely, including on the existing Watch/iOS
app, so a future Android/web client sees the same clubs, friends, and match
history as everyone else — not a fork of the product.

This trades away things CloudKit gave for free: zero server to run, native
offline queuing, push sync, and Apple ID as a ready-made identity with no
account-creation UX. `CloudSyncSpike` (see `CLAUDE.md`) already validated the
two hardest unknowns this trade rests on: Google OAuth → Supabase → Postgres
identity works end-to-end, and a watchOS app with no browser can adopt a
session relayed from the paired iPhone over `WCSession` and make independent,
RLS-scoped Postgres calls afterward (not proxying every request through the
phone).

## 2. Non-goals

- **StoreKit/Entitlements** — already fully decoupled from CloudKit by design
  (`BadmintonCore/Entitlements.swift`: purchase state is per-Apple-ID via
  StoreKit, never synced). No change needed; a non-Apple client will eventually
  need its own payment story (Google Play Billing, Stripe, …), but that's a
  separate future decision, not part of this migration.
- **HealthKit** — unrelated to sync/identity, untouched.
- **Building the actual Android/web client** — unblocked once 9f lands, but is
  its own future phase with its own plan.
- **Running two backends forever** — 9c–9e are per-user opt-in *during* the
  migration window, not a permanent dual-backend feature. 9f's job is to end
  that window, not extend it indefinitely.

## 3. Target identity model

Supabase Auth, Google OAuth as the first provider (matching the spike). Sign
in with Apple is a likely-needed second provider so existing iCloud users
aren't forced through a Google account they may not have — a concrete decision
to make in 9a once Supabase's Apple provider setup is scoped, not assumed here.

`auth.uid()` becomes the new identity primitive, replacing today's chain of
`CKContainer.userRecordID()` → `participantId` → `CKShare.Participant`. Watch
identity has no separate flow: the phone always performs the actual OAuth
handshake and relays the resulting session to the watch over `WCSession`,
exactly as `CloudSyncSpike` proved — promoted from DEBUG-only spike code to a
real, always-available path in 9c.

## 4. Target schema

Implemented in [supabase/schema.sql](../supabase/schema.sql) (9a) — the
tracked, reviewable source of truth, applied manually via the Supabase SQL
editor (no migration-runner tooling yet; that's a fine later addition, not a
9a blocker). Reuses the existing `CloudSyncSpike` project rather than
standing up a second one — the file opens by dropping the spike's throwaway
`match_records`/`players`/`profiles` scaffolding (disposable test rows only)
before creating the real tables.

| Table | Replaces | Notes |
|---|---|---|
| `profiles` | `FriendProfile` (public DB) | one row per `auth.uid()`, readable by any signed-in user (needed for code-based friend lookup with no prior relationship) |
| `players` | personal `Player` CKRecords | `owner_id`, nullable `club_id`, `payload jsonb` (reuse `Codable` shape, like the spike) |
| `match_records` | personal `MatchRecord` CKRecords | same `owner_id`/`club_id`/`payload jsonb` pattern |
| `settings` | fixed `Settings` CKRecord | one row per `auth.uid()`, strictly personal |
| `clubs` | `Club` + its `CKShare` zone | the zone itself goes away — see `club_members`; a trigger auto-adds the creator as `role = 'owner'` in `club_members`, mirroring CloudKit's implicit "creating a zone makes you its first participant" |
| `club_members` | CKShare's participant list | **explicit membership table** — CKShare's zone-sharing makes "is a member" implicit in share participation; Postgres has no equivalent, so this needs a real table + RLS join, not a re-pointed API call. Membership reads use a `SECURITY DEFINER` `is_club_member()` helper to avoid the table's RLS policy recursively referencing itself |
| `club_invites` | `UICloudSharingController` invite flow | schema only in 9a (owner-gated CRUD); the actual link/code redemption flow (mirroring `badminton://addfriend`) is 9d work, which also makes club invites cross-platform for free unlike today's iOS-only `UICloudSharingController` |
| `challenges` | `ChallengeRecord` | club-scoped; zone-wide write access for any member, matching CloudKit's current documented behavior (`ROADMAP.md` Phase 5: "any club participant can already write any field of any record in a shared zone") — not a new decision |
| `reactions` | `ReactionRecord` | club-scoped reads, but writes are author-only (`author_id = auth.uid()`) — unlike players/challenges, each reaction has a real author to scope to, so it doesn't need the zone-wide-write carryover |
| `friend_requests` | `FriendRequest` (public DB) | graph edge, accepted request = friendship; sender-only insert, either side can update (accept/decline/cancel) |

**No separate `friend_shares` table** (a deviation from this doc's original
sketch): friend-visibility policies on `players`/`match_records`/`settings`/
`profiles` are deferred to 9e, when the Friends graph itself is cut over.
They'll be additional `SELECT` policies keyed off `friend_requests.status =
'accepted'` plus the per-field share toggles already present in a user's
`settings.payload` (`shareHistoryWithFriends`, etc.) — no junction table
needed, since that data already fully describes who-shares-what-with-whom.

Proving these RLS policies can't be tricked into leaking another user's rows
is the direct analogue of the spike's "deliberately try to violate RLS"
verification step, now under real multi-table, multi-policy conditions —
see `docs/supabase-migration-plan.md` §5's 9c-onward multi-account test gate.

## 5. Sub-phases

Mirrors the slicing convention already used for Phase 5 (Cross-person sharing,
5a–5f) and Phase 7 (Friend graph, 7a–7g): each sub-phase below is its own PR
and its own tracking issue, filed once the prior slice lands.

- **9a — Foundation.** ✅ done. Production Postgres schema + RLS policies,
  tracked in [supabase/schema.sql](../supabase/schema.sql), applied via the
  Supabase SQL editor to the existing `CloudSyncSpike` project and verified
  (all 10 tables present, RLS enabled on every one) — see §4. No app code
  changes — the schema is designed and reviewed before any Swift is written
  against it.
- **9b — `SyncEngine` abstraction.** ✅ done. `SyncEngine` protocol
  ([SyncEngine.swift](../BadmintonCore/Sources/BadmintonCore/SyncEngine.swift))
  capturing the 14 methods `AppStore` calls to push local changes out
  (`enqueue*` plus the three `eraseAllData()` teardown methods).
  `CloudKitSyncManager` (both targets) conforms to it with no behavior
  change; `AppStore` now holds an injected `syncEngine: SyncEngine`, set to
  `CloudKitSyncManager.shared` at `static let shared` (not a default
  parameter — a defaulted `@MainActor`-isolated static property triggers a
  Swift 6 nonisolated-context warning at the call site) instead of 20
  hardcoded call sites — a pure
  refactor that creates the seam 9c swaps behind instead of forking
  `AppStore` in place. The reverse direction (`applyRemote*` callbacks) stays
  outside the protocol on purpose — `AppStore` remains a concrete singleton
  any backend calls into directly, only the outbound direction needed
  polymorphism.
- **9c — Personal data cutover.** Covers only the small/isolated tier:
  `settings` + personal (`clubId == nil`) `players`/`match_records`. Real
  (non-DEBUG) Google Sign-In + `WCSession` relay, promoted from
  `CloudSyncSpike`. One-time migration-on-signin that imports a user's
  existing local data. Opt-in per the local-first invariant in `ROADMAP.md` —
  CloudKit stays the default, untouched, for anyone who doesn't switch. Not
  dual-write: a device is either CloudKit-only or Supabase-only for this
  tier — dual-run validation is 9f's job, not 9c's. Sliced further:
  - **9c-1 — `SupabaseSyncManager` production scaffold.** ✅ done.
    `CloudSyncSpike`'s spike client promoted in place: `SupabaseConfig`
    (hardcoded real project URL/anon key — anon keys are designed to be
    client-embeddable, same practice as a Firebase config) and
    `SupabaseSyncManager` (auth methods kept as-is; the stale
    `SpikeTestRecord`/`insertTestRecord`/`fetchTestRecords` — which targeted
    a throwaway table 9a's `schema.sql` already dropped — replaced with real
    `players`/`match_records`/`settings` CRUD, `payload jsonb` built via
    supabase-swift's `AnyJSON` decoded from `PersistenceStore.encode*`
    output). Discovered during implementation: a shared package can't import
    `AppStore` (an app-target type), so `SupabaseSyncManager` does **not**
    conform to `SyncEngine` itself — each target gained its own thin
    `SupabaseSyncEngine.swift` that does, reading `AppStore.shared`'s live
    roster/history/settings by id (same "materialize fresh from the live
    cache" pattern `CloudKitSyncManager` already uses) and calling into the
    package's manager. Not yet wired into `AppStore` (that's 9c-2) or
    reachable from any UI (that's 9c-3). The stale DEBUG-only
    `CloudSyncSpikeView`/Settings row (targeting the old spike schema, would
    no longer compile) were removed as part of this slice.
  - **9c-2 — `AppStore` backend-switch plumbing.** ✅ done. `syncEngine` is
    now `private(set) var` (was `let`); `static let shared` reads
    `AppStorageKeys.supabaseAccountLinked` from `UserDefaults` directly
    (can't use `@AppStorage` in a static initializer) so a relaunch after
    activation stays on Supabase instead of reverting to CloudKit. New
    `AppStore.activateSupabaseSync()` (no-ops unless
    `SupabaseSyncManager.shared.isSignedIn`, then swaps `syncEngine` and
    re-enqueues every existing roster/history/settings id — migration-on-
    signin is just that reuse, no bespoke upload code) and
    `deactivateSupabaseSync()` (swaps back to CloudKit, no remote delete).
    Neither touches the `supabaseAccountLinked` flag itself — the caller (a
    `@AppStorage`-bound Settings toggle, 9c-3) owns that write, same pattern
    as `accountLinked`'s existing `linkAccount()`/`unlinkAccount()`.
    Also closed all three things 9c-1's `/code-review` flagged as becoming
    live here: `SupabaseSyncEngine` now chains every `enqueue*` through a
    private serial `Task` (writes apply in call order, no more races between
    quick successive saves); `SupabaseSyncManager` gained batched
    `upsertPlayers`/`upsertMatchRecords`/`deletePlayers`/`deleteMatchRecords`
    (one request for N rows, not N requests) built around a new
    `PendingRecord` type — a plain tuple tripped SwiftLint's `large_tuple`
    rule at 4 members; and `currentSettingsSnapshot()` moved onto `AppStore`
    itself, so `CloudKitSyncManager` and `SupabaseSyncEngine` share one copy
    per target instead of one each (4 copies → 2).
  - **9c-3 — Production UI.** ✅ done. A real "Sync Backend" Settings section
    on both targets, reusing the `accountLinked` link/unlink UX pattern —
    gated by its own `AppStorageKeys.supabaseAccountLinked` flag rather than
    `accountLinked` itself. iOS performs Google Sign-In
    (`SupabaseSyncManager.shared.signInWithGoogle(presentationAnchor:)`, an
    `ASWebAuthenticationSession` under the hood) then relays the session to
    the Watch (`AppDelegate.relaySessionToWatch(tokens:)`, already promoted
    to production in 9c-1) before calling
    `AppStore.shared.activateSupabaseSync()`. The Watch never performs OAuth
    itself: its row shows an informational "sign in on your iPhone first"
    message until `SupabaseSyncManager.shared.isSignedIn` flips true from a
    received relay, then offers its own explicit activation button — the
    relay makes activation *available*, it never auto-activates, so a
    phone-side sign-in can't silently switch the Watch's transport without a
    Watch-side confirmation. Turned out the WCSession relay promotion
    originally scoped for this slice was already done in 9c-1, so 9c-3
    ended up UI-only.
  - **9c-4 — Fix the View-bypass gap flagged in 9b's `/code-review`.** ~32
    call sites across 9 View files on both targets (SettingsView,
    FriendSharingSettingsView, ClubDetailView, FriendsView, ContentView,
    ProfileView, StatsView, HistoryView) call
    `CloudKitSyncManager.shared.enqueueSettingsChange()` directly, bypassing
    `AppStore`/`syncEngine` entirely — route these through `AppStore` instead,
    since swapping `AppStore`'s `syncEngine` alone won't redirect them.
- **9d — Clubs cutover.** `club_members`/`club_invites` replace CKShare
  zone-sharing; migrates `Club` plus club-scoped `players`/`match_records`/
  `challenges`/`reactions`.
- **9e — Friends graph cutover.** `FriendProfile`/`FriendRequest` move from
  CloudKit's public database to Postgres; the FriendsHistory identity-shared
  zone becomes `friend_shares`-scoped RLS; push notifications move from
  `CKQuerySubscription` to Supabase Realtime or an Edge Function + APNs.
- **9f — Dual-run validation & cutover.** Run both backends live for opted-in
  users during a validation window, compare data for drift, then flip the
  default identity provider and retire the CloudKit code paths and
  entitlements. This is the point a non-Apple client becomes buildable against
  the same backend everyone else uses.

Each sub-phase carries its own manual test gate. RLS bugs mean cross-user data
leaks — a strictly higher-stakes failure mode than a CKShare bug, since a
mis-scoped CKShare at least stays within Apple's ACL model. 9c onward needs
real multi-account verification before merge, not just green CI, in the same
spirit as Phase 4/5's two-device gate but with sharper teeth. Per `CLAUDE.md`,
any sub-phase touching `AppStore`/the sync layer goes through plan mode first.

## 6. Open risks

- **`transferUserInfo` vs `sendMessage`**: the spike found `sendMessage`
  delivered reliably Simulator-to-Simulator while `transferUserInfo` alone did
  not — flagged there as possibly Simulator-specific. Needs re-verification on
  real hardware before 9c leans on either path as primary.
- **RLS correctness under concurrent writes** — the spike validated RLS
  isolation between two accounts on a single test table; the real schema's
  join-based policies (`club_members`, `friend_shares`) are more complex and
  need their own adversarial test pass in 9a/9d/9e.
- **Token refresh/expiry UX on watchOS** — the watch has no browser to
  re-authenticate through if a relayed session's refresh token itself expires
  or is revoked; 9c needs a defined re-relay path, not just initial handoff.
  Reference: [CloudSyncSpikeView.swift](../badminton%20score%20tracker%20Watch%20App/CloudSyncSpikeView.swift)
  for the flow that would need to be reachable.
- **Migration-on-signin conflicts** — a user who already has CloudKit history
  and, independently, some partial Supabase data (e.g. from re-running 9c's
  import after an interrupted first attempt) needs a defined merge/dedupe
  rule, not just naive re-import.
