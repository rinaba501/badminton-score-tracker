# Backend Migration: CloudKit → Supabase/Postgres — Design

Initiative: replace CloudKit with a Postgres backend (Supabase: Postgres + Auth +
Realtime) as the app's sync/identity layer, on every platform including the
existing Watch/iOS app. This document is the reference for the implementation
phases (Phase 9 in [ROADMAP.md](../ROADMAP.md)).

**Status: 9a-9e done, 9f not started.** Schema + RLS applied and verified against the
Supabase project ([supabase/schema.sql](../supabase/schema.sql), all 10
tables present with `rowsecurity = true`); the `SyncEngine` protocol
([SyncEngine.swift](../BadmintonCore/Sources/BadmintonCore/SyncEngine.swift))
sits between `AppStore` and `CloudKitSyncManager` on both targets, a pure
refactor with no behavior change; `CloudSyncSpike`'s spike client is now a
real production `SupabaseSyncManager` + per-target `SupabaseSyncEngine`
adapters (9c-1) — the DEBUG-only spike UI that proved the OAuth/WCSession-
relay approach was removed rather than kept alongside the real thing.
`AppStore.syncEngine` is swappable via `activateSupabaseSync()`/
`deactivateSupabaseSync()` (9c-2), both targets' Settings screens have a
real "Sync Backend" section that calls them (9c-3) — iOS drives Google
Sign-In and relays the session to the Watch, the Watch offers its own
explicit activation once a relayed session lands — and every View-level
call site that used to bypass `AppStore` and write settings straight to
CloudKit now routes through `AppStore.enqueueSettingsChange()` instead
(9c-4). While researching 9d it turned out 9c-4 didn't actually finish 9c:
`SupabaseSyncEngine` was push-only, with no mechanism at all to bring
remote changes back into `AppStore` — even two of one's own devices on
Supabase wouldn't have synced with each other. 9c-5 added the pull
transport (`SupabaseSyncManager.startRealtimeSync`/`stopRealtimeSync`,
Postgres Changes via `RealtimeChannelV2`, plus `fetchAllRows`/
`fetchSettings` for a one-time catch-up read) and its own `/code-review`
caught a real correctness bug before merge: the `owner_id` Realtime filter
would have silently dropped every DELETE event on `players`/`match_records`
under Postgres's default `REPLICA IDENTITY` (only primary-key columns are
logged for a delete's old-row image), fixed by adding `REPLICA IDENTITY
FULL` for both tables. 9c-6 wired the transport in — `startIfActive()`
(called after migration-on-signin on activation, and unconditionally but
cheaply at every app launch) does the catch-up pull then opens the Realtime
subscription, decoding each change via `PersistenceStore` and applying it
through the same `AppStore.applyRemote*` methods CloudKit already uses; a
device receiving its own push back as a self-echo is expected and harmless
since those applies merge by id. **Phase 9c (personal data cutover) is now
genuinely complete — push and pull are both real.** A real-account,
two-device verification pass is still owed (not yet exercised — same
not-CI-provable gate CloudKit sync correctness already has) before 9c is
considered fully verified, not just fully built.

**Phase 9d (Clubs cutover) is now complete.** 9d-1 (`clubs`/`challenges`/
`reactions` push + pull sync) — see section 5 below for the full
technical detail, including a Realtime filter bug it exposed and fixed (the
9c-5 client-side `owner_id` filter was already too narrow for club data, and
can't even apply to `challenges`/`reactions`, which have no `owner_id`
column — removed entirely, delivery now relies on RLS alone). 9d-2 (invite
redemption via a new `redeem_club_invite` RPC + `ClubInviteLink`/
`ClubInviteView`, and — since a link needs no CKShare — the Watch's first
invite-sending affordance). 9d-3 (member-list read via `club_members`/
`profiles`, plus `leaveClub`/`removeMember` and an owner-only swipe-to-kick
action) closes it out — see section 5 for detail, including why `profiles`
needed a narrow early population (`upsertMyProfile`) even though it was
deferred to 9e by 9a's own schema comment. A real-account, two-device
verification pass (confirming cross-account club visibility, invite
redemption, and membership changes) is still owed for all of 9d, same
not-CI-provable gate as 9c.

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
  - **9c-4 — Fix the View-bypass gap flagged in 9b's `/code-review`.** ✅ done.
    All 33 call sites across 13 View files on both targets (SettingsView,
    FriendSharingSettingsView, ClubDetailView, FriendsView, ContentView,
    ProfileView, StatsView, HistoryView) that called
    `CloudKitSyncManager.shared.enqueueSettingsChange()` directly — bypassing
    `AppStore`/`syncEngine` entirely, so a Supabase-active device kept
    silently writing settings to CloudKit — now call a new
    `AppStore.enqueueSettingsChange()` passthrough (`syncEngine.
    enqueueSettingsChange()`) instead. Every one of the 33 was a bare
    statement with no other CloudKit-specific logic attached, confirmed by
    inspecting each call site before the swap, so this was a mechanical
    find-and-replace plus the one new passthrough method — no redesign
    needed. (This slice's claim of "Phase 9c is now fully complete" turned
    out to be premature — see 9c-5/9c-6 below, discovered while researching
    9d: `SupabaseSyncEngine` was push-only, so nothing actually completed
    9c until the pull side existed too.)
  - **9c-5 — Supabase pull-side sync transport.** ✅ done. Added to
    `SupabaseSyncManager` (`CloudSyncSpike`): `RemoteChange` (a normalized
    upsert/delete shape), `startRealtimeSync`/`stopRealtimeSync` (Postgres
    Changes via `RealtimeChannelV2`, one channel scoped to the signed-in
    user's own rows via an `owner_id` filter, subscribing on `players`/
    `match_records`/`settings`), and `fetchAllRows`/`fetchSettings` (a
    one-time catch-up read for rows that existed remotely before this
    device ever subscribed). Package-level only, no `AppStore` dependency —
    same risk tier as 9c-1's scaffold, no wiring yet. `/code-review` found
    a real bug before merge: the `owner_id` filter would have silently
    dropped every DELETE event on `players`/`match_records`, since
    Postgres's default `REPLICA IDENTITY` only logs primary-key columns
    (`id`) in a delete's old-row image, and `owner_id` isn't the primary
    key on either table (it is on `settings`, so that one was unaffected).
    Fixed by adding `alter table ... replica identity full` for both
    tables in `supabase/schema.sql`.
  - **9c-6 — Wire pull-side sync into `AppStore` + lifecycle.** ✅ done.
    `SupabaseSyncEngine.startIfActive()` (both targets) does the 9c-5
    catch-up pull then opens the Realtime subscription, routed through the
    same serial `enqueueWork` chain the push methods use so a fresh
    activation's migration-on-signin upload finishes before the catch-up
    pull runs rather than racing it. `handleRemoteChange` decodes each
    change via `PersistenceStore` and applies it through
    `AppStore.applyRemoteUpsert`/`applyRemoteDeletions`/`applyRemoteSettings`
    — the same methods `CloudKitSyncManager` already calls, so a Realtime
    event and a CKSyncEngine fetch land through one shared apply path.
    Deliberately does NOT gate on `SupabaseSyncManager.isSignedIn` (that
    flag is only set by an explicit `signInWithGoogle`/`adoptRelayedSession`
    call, so it's still `false` on a cold relaunch even though the SDK
    auto-restores a persisted session from Keychain on demand) — instead
    every downstream call independently no-ops if `currentUserId()` comes
    back nil, so `startIfActive()` is safe to call unconditionally,
    including at every app launch (guarded there by
    `AppStorageKeys.supabaseAccountLinked` purely to skip the async work
    for the common CloudKit-only device, not for correctness).
    `deactivateSupabaseSync()` now calls `stopRealtimeSync()` before
    swapping back to CloudKit. Self-echoes (a device receiving its own push
    back through the subscription) are expected and harmless — the apply
    methods merge by id, so re-applying an unchanged row is a no-op write,
    the same tolerance CloudKit's own local-echo path already relies on.
    `supabase/schema.sql` also gained `alter publication supabase_realtime
    add table public.players, public.match_records, public.settings` —
    without this, a table's changes never enter the replication stream at
    all, independent of any client-side subscription or filter — which the
    user needs to run in the Supabase SQL editor alongside 9c-5's `REPLICA
    IDENTITY FULL` statements, the same manual-SQL handoff 9a used.
    **Phase 9c (personal data cutover) is genuinely complete now — push
    and pull both real.** Still owed: a real-account, two-device
    verification pass (not CI-provable, same gate CloudKit sync
    correctness already has).
- **9d — Clubs cutover.** `club_members`/`club_invites` replace CKShare
  zone-sharing; migrates `Club` plus club-scoped `players`/`match_records`/
  `challenges`/`reactions`. Got its own dedicated plan-mode pass (unlike
  9c's slices, which shared one pass); sliced into 9d-1/9d-2/9d-3:
  - **9d-1 — Clubs/Challenges/Reactions payload sync.** ✅ done. Extended the
    already-proven `id`+`payload jsonb` machinery from `players`/
    `match_records` to `clubs`/`challenges`/`reactions` — none of the 3
    tables fit the existing `PendingRecord` shape (`clubs` has no `club_id`
    column; `challenges`/`reactions` have no single `owner_id`, using two
    participant ids or an `author_id` instead), so `SupabaseSyncManager`
    gained `ClubPendingRecord`/`ChallengePendingRecord`/
    `ReactionPendingRecord` plus matching batched `upsert*`/`delete*`
    methods. `SupabaseSyncEngine`'s `enqueueClubChanges`/
    `enqueueChallengeChanges`/`enqueueReactionChanges` (no-op stubs since
    9c) are now real, and `pullInitialState`/`handleRemoteChange` gained
    matching cases — `AppStore.applyRemoteUpsert`/`applyRemoteDeletions`
    already fully supported clubs/challenges/reactions parameters since
    9c-1, they just weren't being populated, so **zero `AppStore.swift`
    changes were needed**.

    Two design questions this resolved. `Club.ownerRecordName: String?` reuse
    as a backend-opaque owner id: confirmed by grepping every CloudKit read/
    write site that it's used exclusively as an opaque zone-owner string
    (never parsed as/compared to a CKShare.Participant identity), always
    backfilled from server-side record metadata rather than trusted from the
    payload — the exact shape needed for Supabase (`nil` = self-owned, else
    the owner's `auth.uid()` string). This backfill needs the row's *real*
    `owner_id` column, independent of `payload` — a club's owner always
    encodes their own `ownerRecordName` as `nil` (they ARE the owner), so a
    receiving member decoding the payload as-is would wrongly conclude they
    own it. `RemoteChange` gained an `ownerId: UUID?` field for exactly this
    (nil for `challenges`/`reactions`, which have no single owner column).
    `ChallengeRecord.fromParticipantId`/`toParticipantId`/
    `ReactionRecord.authorParticipantId` needed no model change at all —
    they're already opaque `String` fields never parsed elsewhere, so under
    Supabase they simply hold the `auth.uid()` string instead of a CKShare
    participant record name, same opaque-per-backend-id pattern as
    `ownerRecordName`.

    Also fixed a real Realtime design gap the new tables exposed: 9c-5's
    `startRealtimeSync` filtered every subscribed table uniformly by
    `.eq("owner_id", value: uid)` — already too narrow even for the
    existing personal tier (a club member should see *other* members'
    club-scoped `players`/`match_records` rows too, per RLS, but the filter
    silently dropped them), and outright inapplicable to `challenges`/
    `reactions` (no `owner_id` column to filter on). Removed the filter
    entirely, for every table — Supabase's Postgres Changes feature already
    enforces the same SELECT RLS policy for realtime delivery as for a
    regular query, so this is not a security loosening, just a correctness
    fix (the filter was always defense-in-depth on top of RLS, never the
    sole mechanism). `fetchAllRows`'s equivalent `owner_id` filter was
    removed the same way, for the same reason. **This can't be verified by
    CI** — it depends on the live project actually enforcing RLS on
    Postgres Changes, same class of manual gate as the rest of Supabase
    sync.

    New SQL (external setup, same handoff pattern as every prior addition):
    `alter publication supabase_realtime add table public.clubs,
    public.challenges, public.reactions;`.

    This slice's own `/code-review` caught a repeat of 9c-5's REPLICA
    IDENTITY bug, this time on `challenges`/`reactions`: their RLS SELECT
    policies need `club_id` (reactions' delete policy separately needs
    `author_id`), and neither is a primary-key column, so without `REPLICA
    IDENTITY FULL` a DELETE event's old-row image (default: primary key
    only) can't satisfy RLS for anyone — the event fails closed for every
    subscriber, including the legitimate club member/author, and since
    `fetchAllRows` never reports deletes (see its own doc comment above), a
    deleted challenge or reaction would never sync to another device at
    all. `clubs` genuinely doesn't need the same fix — its
    `is_club_member(id)` RLS branch only needs the row's own primary key,
    which is always present regardless of REPLICA IDENTITY. Fixed before
    merge with `alter table public.challenges replica identity full;` and
    the equivalent for `reactions`, added to `supabase/schema.sql`.

    The original 9d sketch's two open cross-cutting questions are both
    resolved, not deferred: reaction cascade-delete semantics turned out to
    be a non-issue — CloudKit's own club-zone deletion already cascades to
    every record in the zone (reactions included), matching Postgres's
    `reactions.club_id on delete cascade` exactly; `reactions.match_id` has
    no FK at all, so a match-only delete doesn't cascade under either
    backend, also matching.
  - **9d-2 — Invite redemption.** ✅ done. `club_members` has no direct
    INSERT policy (9a's own RLS comment already anticipated this exact
    function) — `redeem_club_invite(invite_id)`, a `SECURITY DEFINER`
    Postgres function, validates a `club_invites` row's expiry/`max_uses`/
    `use_count` (row-locked via `for update` to close a race between two
    concurrent redemptions of the same invite) then inserts the caller
    into `club_members`, mirroring how `handle_new_club()` already
    bypasses the caller's own insert privilege for owners.
    `SupabaseSyncManager` gained `createClubInvite(clubId:expiresAt:maxUses:)`
    (owner-only, RLS-enforced) and `redeemClubInvite(inviteId:)` (wraps the
    RPC). New `BadmintonCore/Sources/BadmintonCore/ClubInviteLink.swift` —
    a byte-shape mirror of `FriendInviteLink.swift`
    (`badminton://joinclub?id=<inviteId>&name=<clubName>`) — and iOS-only
    `ClubInviteView.swift` mirroring `FriendInviteView.swift`, wired into
    `ContentView`'s `onOpenURL` as a second parse attempt when
    `FriendInviteLink.parse` misses (the two invite links share one scheme
    but different hosts). `ClubDetailView`'s owner-only Invite button (both
    targets) now branches on `supabaseAccountLinked`: CloudKit-active
    devices keep `CloudSharingView`/`UICloudSharingController` completely
    unchanged; Supabase-active devices call `createClubInvite` then present
    a `ShareLink` over the resulting `ClubInviteLink` URL — no CKShare
    involved, so this is the **Watch's first invite-sending affordance**;
    CKShare invites were always iOS-only (`UICloudSharingController` is
    UIKit-only), so Watch's `ClubDetailView` never had one before this.
    New SQL (external setup, flagged to user): the `redeem_club_invite`
    function itself.
  - **9d-3 — Member-list read + leave/kick.** ✅ done. `SupabaseSyncManager.
    fetchClubMembers(clubId:)` resolves `club_members` against `profiles`
    for display names via two client-side queries, not a PostgREST embed —
    `club_members` and `profiles` both reference `auth.users`, not each
    other, so there's no FK for PostgREST to embed across. Resolved as a
    View-level backend branch on `ClubDetailView.loadParticipants()`, not a
    `SyncEngine` protocol addition — the protocol stays outbound/push-only
    as originally scoped in 9b. Real gap found during implementation: `9a`'s
    own schema comment deferred populating `profiles` to 9e (Friends), but
    a club member list needs *a* name sooner than that — fixed with a
    narrow `SupabaseSyncManager.upsertMyProfile(displayName:)`, called from
    `SupabaseSyncEngine.startIfActive()` (already the per-target hook for
    activation + every app launch) rather than adding a new call site.
    `leaveClub`/`removeMember` are simple deletes, both already covered by
    the existing `club_members_delete` RLS policy (self or owner) — no new
    SQL needed, unlike 9d-2's RPC. Wired into `removeClub()`: a non-owner's
    "leave" now explicitly calls `leaveClub` alongside the existing
    `saveClubs` diffing, since that diffing's implicit `clubs` delete
    silently no-ops for a non-owner under Supabase's owner-only
    `clubs_delete` RLS (the owner's real delete still cascades to
    `club_members` via the FK, unchanged from 9d-1). Both targets also
    gained an owner-only swipe-to-kick action on the member list, gated to
    Supabase-active only — the CloudKit path never needed one, since
    `UICloudSharingController`'s system share sheet already offers
    participant management for free. `ClubParticipant.isFriend` is
    hardcoded `false` for Supabase-active members (not computed against
    `AppStore.friends`, unlike the CloudKit path) — Friends stays
    CloudKit-only until 9e, so there's no Supabase-side friend graph yet to
    cross-reference a member's `auth.uid()` against. Participant-id
    resolution at Challenge/Reaction creation sites needed no separate
    work: both already read `myParticipantId`/`myDisplayName` as plain
    values threaded down from `ClubDetailView`, so fixing
    `loadParticipants()` to populate those correctly for Supabase-active
    covers them automatically.
- **9e — Friends graph cutover**, split 9e-1/9e-2/9e-3/9e-4 (its own
  plan-mode pass this session, superseding this bullet's original one-line
  sketch — the "`friend_shares`-scoped RLS"/"Edge Function + APNs" wording
  below predates that pass and is resolved differently, kept struck-through
  for history rather than deleted):
  - ~~`FriendProfile`/`FriendRequest` move from CloudKit's public database to
    Postgres; the FriendsHistory identity-shared zone becomes
    `friend_shares`-scoped RLS; push notifications move from
    `CKQuerySubscription` to Supabase Realtime or an Edge Function + APNs.~~
  - **9e-1** ✅ done: `FriendProfile`/`FriendRequest` reuse `profiles` (9d-3)
    and `friend_requests` (9a) directly — no new tables, no `friend_shares`
    junction table, no APNs/Edge Function (Realtime alone, same as every
    other table since 9c-5). `profiles.id`/`friend_requests.
    from_participant_id`/`to_participant_id` are already `auth.uid()`
    itself, simpler than the opaque-CKShare-id parsing challenges/reactions
    needed in 9d-1. `SupabaseSyncManager` gained
    `fetchProfileDisplayName`/`sendFriendRequest`/`respondToFriendRequest` —
    all primitives-only (`UUID`/`String`/`Data`), since this package still
    has no `BadmintonCore` dependency and so can never construct a
    `FriendRequest`/`FriendProfile` itself; every target's View builds the
    model, encodes it via `PersistenceStore`, and passes the raw pieces in,
    same split every other method in this file already follows. The pull
    side needed no new manager method at all: `friend_requests` is
    id-primary-keyed like every other table, so it just joined `pullTables`
    and reuses the existing `fetchAllRows`/Realtime subscription unchanged.
    New `SupabaseSyncEngine.refreshFriendRequests()` does a full
    refetch-and-reconcile into `AppStore.saveFriendRequests` (not a per-id
    merge — matches that method's existing "here is the complete current
    list" contract, and the CloudKit path already refetches the whole set
    after every mutation too) on both the initial pull and every Realtime
    event for that table, regardless of insert/update/delete — simpler than
    branching per change kind for a table this small. A real correctness
    gap was found (not anticipated by the plan-mode pass): `AppStore.
    friends` reads `AppStorageKeys.myParticipantId` from `UserDefaults`
    directly rather than through `SyncEngine`, and that key was previously
    only ever written by CloudKit's `resolveMyParticipantId()` — a
    Supabase-active device never called that, so `AppStore.friends` would
    have silently stayed empty forever. Fixed by caching `currentUserId()`
    into the same key from `SupabaseSyncEngine.startIfActive()` (already the
    per-target hook for "activation + every app launch" side effects, same
    place 9d-3's `upsertMyProfile` call landed). Also two SQL changes:
    widened `friend_requests_delete` RLS from sender-only to either-party
    (symmetric with `club_members_delete`'s self-or-owner shape, needed so a
    future full-teardown delete can clean up requests where this account is
    only ever the recipient), and the by-now-familiar `REPLICA IDENTITY
    FULL` fix (third occurrence — 9c-5, 9d-1, 9e-1 — `friend_requests_select`/
    `_delete` read `from_participant_id`/`to_participant_id`, neither the
    primary key). Every `CloudKitSyncManager.shared.ensureMyProfileExists`/
    `fetchProfile`/`sendFriendRequest`/`respondToFriendRequest`/
    `fetchMyFriendRequests` call site across both targets now branches on
    `supabaseAccountLinked`.
  - **9e-2 — Friend identity + stats sharing.** ✅ done. New
    `friend_identity_snapshots`/`friend_stats_snapshots` tables, one row per
    owner. Deliberately NOT a live RLS grant on `settings` itself — that
    table's single `payload jsonb` blob holds every unrelated scalar setting
    alongside the four/six shareable fields, and RLS can only grant or deny
    a whole row, not individual jsonb keys, so a friend granted `SELECT`
    there would see everything. Shipped shape differs from the original
    sketch in one way: `id`+`payload jsonb` (like every other Phase 9
    table) rather than discrete typed columns — that reuses
    `SupabaseSyncManager.fetchAllRows`/`startRealtimeSync`/`upsertRows`
    completely unchanged instead of needing bespoke per-column Decodable
    types, discovered mid-implementation once it became clear the discrete-
    column design would silently break the generic Realtime decoder (which
    only knows how to read a `payload` key). The payload itself still
    mirrors CloudKit's own `currentFriendIdentitySnapshot()`/
    `currentFriendStatsSnapshot()` shape: derived, precomputed, and each
    field left `null` client-side (never written at all, not just
    RLS-hidden) whenever its toggle is off — ported verbatim into
    `SupabaseSyncEngine`. New `is_accepted_friend` RLS helper; neither table
    needs `REPLICA IDENTITY FULL` (RLS reads only the row's own PK, same
    exemption `clubs` already had). Since the tables carry no display name
    of their own, `SupabaseSyncEngine` resolves one from the already-synced
    friend graph (`AppStore.friends`, populated by 9e-1) rather than
    duplicating it into a third place; pull/Realtime handling also filters
    out a device's own row (`id == currentUserId()`) before applying it,
    mirroring CloudKit's `zoneID.ownerName != CKCurrentUserDefaultName`
    self-echo guard — RLS legitimately returns the caller's own row too
    (`id = auth.uid() or is_accepted_friend(id)`), and without the filter a
    user would see themselves listed as their own friend.
    `enqueueFriendsRosterChanges`/`enqueueFriendsHistoryChanges` become
    permanent no-ops under Supabase (documented as such, not left as "not
    yet migrated") — CloudKit needs them to mirror a copy into the
    FriendsHistory zone, but Supabase grants friend visibility via RLS on
    the *same* `players`/`match_records` row a personal save already pushes
    unconditionally (9e-3). **Real pre-existing gap found and fixed**:
    `FriendSharingSettingsView.toggleStatsSharing` (and its iOS
    `ProfileView`/`StatsView`/`HistoryView` duplicates of the identity/
    history toggle handlers) called `CloudKitSyncManager.shared.
    enqueueFriendStatsChange`/`.removeFriendStatsRecord` directly rather
    than through `AppStore.syncEngine` — the exact View-bypass shape 9c-4
    already fixed once for `enqueueSettingsChange`, invisible here until now
    because `CloudKitSyncManager.shared` and `AppStore.syncEngine` were
    always the same object before Supabase existed. Fixed by adding
    `removeFriendStatsRecord()` to the `SyncEngine` protocol itself (parity
    with the already-protocol `removeFriendIdentityRecord()`) and routing
    every call site through `AppStore.shared.syncEngine` instead of
    `CloudKitSyncManager.shared`; the CKShare-participant-list calls
    (`syncFriendsHistoryParticipants`/`revokeFriendsHistoryAccess`) stay
    CloudKit-only, now explicitly gated on `!supabaseAccountLinked`.
  - **9e-3 — Friend history sharing.** ✅ done. New `friend_can_view_history`
    helper (`is_accepted_friend(target_owner) and` that owner's `settings`
    row has `shareHistoryWithFriends` true), added as one more `or` branch on
    `players_select`/`match_records_select` — no mirrored copy of the data
    needed at all (a genuine simplification over CloudKit's separate
    "FriendsHistory" zone, which only existed because a `CKShare` grants
    access at zone granularity, not per-row; Postgres RLS is row-level
    natively). Since `fetchAllRows`/`startRealtimeSync` already apply no
    client-side owner filter, the already-running `players`/`match_records`
    sync started returning friend-shared rows the moment this RLS landed —
    no new manager method needed. The real work, and the highest-risk piece
    of 9e (touches already-live RLS + sync routing logic): `SupabaseSyncEngine`'s
    pull (`pullInitialState`) and Realtime (`handleRemoteChange`) now decode
    every `players`/`match_records` row and branch on
    `(clubId, ownerId vs currentUserId())` via a new `isPersonalOrClubRow`
    helper — `clubId != nil` (club-shared) or `ownerId == nil`/`ownerId ==
    self` (personal, including the push-echo case) keeps going through the
    existing `applyRemoteUpsert`/`applyRemoteDeletions` merge-into-my-own
    path unchanged; everything else — a friend's now-RLS-visible personal
    row — routes to `AppStore.applyRemoteFriendActivity`/
    `applyRemoteFriendActivityDeletions` instead, so it never merges into
    this device's own roster/history. `RemoteChange` gained a
    `clubId: UUID?` field (same reasoning as its existing `ownerId`): a
    `.delete` Realtime event carries no `payload`, so a decoded model's own
    `clubId` isn't available to route on — `players`/`match_records` already
    have `REPLICA IDENTITY FULL` (9c-5), so the old-row image already
    carried `club_id`, it just wasn't being read into `RemoteChange` before
    now. `/code-review` before merge, called out specifically for the
    routing-logic risk, per the plan.
  - **9e-4 — Erase-all-data teardown.** ✅ done. `deleteMyFriendProfile()`/
    `deleteAllMyFriendRequests()` (both targets' `SupabaseSyncEngine`) were
    still 9b-era no-op stubs — now call new `SupabaseSyncManager.
    deleteMyProfile()`/`deleteAllFriendRequests()`. `deleteMyProfile()`
    needed a new `profiles_delete` RLS policy (`schema.sql`) — 9a never
    added one, since nothing called for a profile delete until this slice.
    `deleteAllFriendRequests()` deletes every `friend_requests` row the
    caller is party to via an explicit `.or("from_participant_id.eq.<uid>,
    to_participant_id.eq.<uid>")` filter, mirroring CloudKit's own
    bidirectional `deleteAllMyFriendRequests()` intent — RLS (widened
    either-party in 9e-1) already scopes it correctly on its own, the filter
    just keeps the query's intent readable. `deleteFriendsHistoryZone()`
    stays a documented permanent no-op — there's no zone concept under
    Supabase, and friend history access is pure RLS gated by
    `shareHistoryWithFriends` (already reset to `false` earlier in
    `eraseAllData()`) over rows `saveRoster([])`/`clearHistory()` delete
    outright in that same method, same "documented no-op" precedent 9e-2
    set for the roster/history mirror methods.

    **Real backend-agnostic gap found and fixed**, not anticipated by the
    plan-mode pass: `AppStore.eraseAllData()` never unconditionally cleared
    the FriendIdentity/FriendStats snapshot — under CloudKit this was
    invisible, since deleting the whole FriendsHistory *zone* implicitly
    wipes both records regardless of whether `saveRoster`'s roster-diff-
    gated `refreshMyIdentitySnapshotIfSharing()` call happens to fire for
    this erase. Supabase's `friend_identity_snapshots`/
    `friend_stats_snapshots` are ordinary tables with no zone-wide delete,
    so `eraseAllData()` (both targets) now calls
    `syncEngine.removeFriendIdentityRecord()`/`removeFriendStatsRecord()`
    explicitly and unconditionally (both already real since 9e-2) —
    harmless/idempotent under CloudKit, the only thing that reliably clears
    these two rows under Supabase. **New SQL owed to the user**: the
    `profiles_delete` policy, same "merged but inert without this" handoff
    as every prior schema addition. **Phase 9e (Friends graph cutover) is
    now complete.**
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
