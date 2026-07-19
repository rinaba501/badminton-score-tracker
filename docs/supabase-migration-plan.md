# Backend Migration: CloudKit → Supabase/Postgres — Design

Initiative: replace CloudKit with a Postgres backend (Supabase: Postgres + Auth +
Realtime) as the app's sync/identity layer, on every platform including the
existing Watch/iOS app. This document is the reference for the implementation
phases (Phase 9 in [ROADMAP.md](../ROADMAP.md)).

**Status: design only — no sub-phase implementation has started. `CloudSyncSpike/`
(merged, DEBUG-only) is the completed feasibility precursor this design builds on.**

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

## 4. Target schema (sketch — refined for real in 9a)

| Table | Replaces | Notes |
|---|---|---|
| `profiles` | `FriendProfile` (public DB) | one row per `auth.uid()` |
| `players` | personal `Player` CKRecords | `owner_id = auth.uid()`, `payload jsonb` (reuse `Codable` shape, like the spike) |
| `match_records` | personal `MatchRecord` CKRecords | same `owner_id`/`payload jsonb` pattern |
| `settings` | fixed `Settings` CKRecord | one row per `auth.uid()` |
| `clubs` | `Club` + its `CKShare` zone | the zone itself goes away — see `club_members` |
| `club_members` | CKShare's participant list | **explicit membership table** — CKShare's zone-sharing makes "is a member" implicit in share participation; Postgres has no equivalent, so this needs a real table + RLS join, not a re-pointed API call |
| `club_invites` | `UICloudSharingController` invite flow | link/code based (mirrors the existing `badminton://addfriend` pattern), which also makes club invites cross-platform for free, unlike today's iOS-only `UICloudSharingController` |
| `challenges` | `ChallengeRecord` | club-scoped, same shape |
| `reactions` | `ReactionRecord` | club-scoped, same shape |
| `friend_requests` | `FriendRequest` (public DB) | graph edge, accepted request = friendship |
| `friend_shares` | FriendsHistory identity-shared zone | **replaces per-user zone sharing with an RLS join**: a friend can read your `players`/`match_records`/identity/stats rows only if a `friend_shares` row (or the equivalent policy over `friend_requests.status = accepted` + your per-field share toggles) grants it |

RLS policy shape per table: `owner_id = auth.uid()` for personal data,
`EXISTS (SELECT 1 FROM club_members WHERE club_id = clubs.id AND user_id =
auth.uid())`-style joins for club data, and a `friend_shares`/accepted-request
join for friend-visible data. Proving these joins can't be tricked into
leaking another user's rows is the direct analogue of the spike's "deliberately
try to violate RLS" verification step, now under real multi-table conditions.

## 5. Sub-phases

Mirrors the slicing convention already used for Phase 5 (Cross-person sharing,
5a–5f) and Phase 7 (Friend graph, 7a–7g): each sub-phase below is its own PR
and its own tracking issue, filed once the prior slice lands.

- **9a — Foundation.** Production Postgres schema + RLS policies (manual SQL
  in the Supabase dashboard, like the spike's setup but for real, covering the
  full table list in §4). No app code changes — a schema can be designed and
  reviewed before any Swift is written against it.
- **9b — `SyncEngine` abstraction.** Extract a `SyncEngine` protocol capturing
  what `AppStore` currently calls directly on `CloudKitSyncManager` today
  (`enqueue*`/`applyRemote*`/the `eraseAllData()` teardown methods).
  `CloudKitSyncManager` conforms to it with no behavior change — a pure
  refactor, reviewable and shippable entirely on its own, that creates the
  seam later sub-phases swap behind instead of forking `AppStore` in place.
- **9c — Personal data cutover.** New `SupabaseSyncManager` conforming to
  `SyncEngine`, covering only the small/isolated tier: `settings` + personal
  (`clubId == nil`) `players`/`match_records`. Real (non-DEBUG) Google
  Sign-In + `WCSession` relay, promoted from `CloudSyncSpike`. One-time
  migration-on-signin that imports a user's existing local data. Opt-in per
  the local-first invariant in `ROADMAP.md` — CloudKit stays the default,
  untouched, for anyone who doesn't switch.
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
