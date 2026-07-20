# Architecture Roadmap

Long-term technical roadmap for the badminton score tracker, based on a full codebase review (July 2026). It answers three questions:

1. What is missing to keep this project healthy **long-term**?
2. What groundwork is needed for **players sharing and interacting across devices and between different people**?
3. What is the path to a **mobile (iOS) companion app**?

This complements [SPEC.md](SPEC.md) (what the app does) and [CLAUDE.md](CLAUDE.md) (structure and conventions). SPEC.md's Open Issues table tracks *features*; this file sequences the *architectural* work and explains why each step exists. Issue #93 holds the original product/strategy discussion this roadmap concretizes.

---

## Where the codebase stands

### Strengths (preserve these)

- **`BadmintonMatch` is a pure, Foundation-only scoring engine** (`MatchModel.swift`) — no UI, no timers, well covered by unit tests. This is the single most valuable structural asset; every phase below is designed to protect it.
- **Serialization is centralized** (`PersistenceStore`), the in-memory cache is centralized (`AppStore`), and both are Foundation-only.
- **Docs are genuinely maintained** (SPEC.md / CLAUDE.md living-doc convention), CI gates every PR (SwiftLint + unit tests), and 6-locale localization plus VoiceOver accessibility are already in place.

### Gaps (what this roadmap fixes)

| # | Gap | Evidence | Why it matters long-term |
|---|-----|----------|--------------------------|
| 1 | **No shared module** — everything lives in the Watch App target; no Swift package | No `Package.swift`; `Player` model fused with SwiftUI (`Color`/`AvatarView` in `Player.swift`) | An iOS app (#41) can reuse nothing; portable core is trapped |
| 2 | **Sync API dead-ends the sharing goal** | `NSUbiquitousKeyValueStore` is per-Apple-ID with a ~1 MB quota; history is one unbounded blob under one key; quota-exceeded now surfaces a warning (#87) but the ceiling itself is structural | Sync will still eventually hit the ceiling, and the API structurally cannot share between different people (#93) |
| 3 | **Identity is display-text based** | `Player.recordReferences` falls back to name equality; guest/"Me" sentinels are localized strings used in identity checks | Renames orphan history; guests break across locales; two people cannot agree on "who is this player" — blocks sharing |
| 4 | **No schema versioning or migration** | No version fields; `decodeHistory` returns `[]` on any error — one malformed record drops the whole history in memory | You cannot safely evolve a schema you cannot version; a prerequisite for CloudKit and an iOS app decoding the same data |
| 5 | **Business logic lives in views** | `GameView.swift` (751 lines) mixes match-saving, sudden-death rules, a score-announcement engine, and 15 inline `WKInterfaceDevice` haptic calls; the whole stats engine is computed inside `StatsView`; helpers duplicated across 4+ views | Untestable, watchOS-locked, and the site of both real bugs so far (#96) |
| 6 | **Guardrails rely on discipline** | No localization key-sync check, no coverage reporting, Complication target never compiled in CI, deployment-target mismatch (26.5 vs 11.4), no release/versioning process | Regressions that CI cannot see (#110) |

---

## Roadmap

Dependency-ordered phases. Each phase is independently shippable and maps to a GitHub issue.

```
Phase 1 (#106)  Extract BadmintonCore package
     │
Phase 2 (#96)   De-view business logic (GameView view model, haptics protocol)
     │
Phase 3 (#107, #108)  Schema versioning + stable identity      ← backend-agnostic
     │
Phase 4 (#109)  CloudKit private-database sync                  ← removes 1 MB cap
     │
Phase 5 (#13, via #93)  Cross-person sharing (CKShare)
     │
Phase 6 (#41)   iOS companion app        ← unblocked by Phases 1–2; richer after 4–5

Guardrails track (#110) — independent, cheap, do anytime
```

### Phase 1 — Extract a shared `BadmintonCore` Swift package (#106)

Move the platform-free core into a local Swift package: `MatchModel`, `PersistenceStore`, a de-SwiftUI'd `Player` (the `AvatarView`/`Color` mapping stays in the app target), a new `StatsCalculator` absorbing the derivations currently computed inside `StatsView`/`PreMatchView`/`HistoryView`, the duplicated helpers (`durationString`, head-to-head, `allPlayers`, roster-save), and an `AppSettings` type centralizing every `@AppStorage` key and default. Unit tests move into the package and become runnable on macOS (seconds instead of the ~3-minute watchOS simulator job).

*Why first:* every later phase either adds code that needs a shared home (Phases 2–3) or a second consumer of the core (Phases 4–6).

### Phase 2 — De-view the business logic (#96)

Slim `GameView` into layout-only code: extract match-state orchestration and `saveMatch()` into a testable view model, the score-announcement formatting (ja/zh/en phrase tables) into a pure `ScoreCallFormatter`, sudden-death/time-mode resolution toward `BadmintonMatch`, and haptics behind a `HapticsProvider` protocol (watch implementation wraps `WKInterfaceDevice`). Issue #96 already scopes this; Phase 1 gives the extractions a home.

*Why second:* this is the precondition for any iOS UI (the 15 inline `WKInterfaceDevice` calls are compile errors on iOS) and puts the app's riskiest untested logic under test.

### Phase 3 — Data durability & identity groundwork (#107, #108)

Backend-agnostic changes required no matter which sync/sharing backend wins:

- **#107** — schema-version field on persisted payloads, per-record tolerant decoding (one corrupt record no longer wipes the list), and a launch-time migration hook.
- **#108** — ID-first player matching everywhere (names become display-only), locale-independent sentinel tokens for guest/"Me" identity, winner stored as `Side` rather than a display string, and a one-time backfill via the migration hook.
- Stopgap while still on the KV store: surface (don't swallow) quota-exceeded, warn before the 1 MB ceiling — **#87**, done.

### Phase 4 — CloudKit private-database sync (#109) ✅ cut over

Replace the single-blob KV-store sync with the CloudKit private database: one `CKRecord` per match and per player, real deletion propagation (retiring the `isHistoryShrink` overwrite heuristic), push-based change notifications, and no practical size ceiling. **Done on both targets** — `CloudSyncManager` / `NSUbiquitousKeyValueStore` / the `cloudKitSyncEnabled` flag are removed; CloudKit is the only sync path and starts on launch. Every scalar setting (`myName`, `localPlayerId`, `pointsToWin`, `gamesInMatch`, `courtTheme`, `announceScore`, `enableSounds`, `enableCrownScoring`, `timeModeEnabled`, `timeLimitMinutes`) lives in a fixed personal-zone `Settings` record (`SettingsSnapshot` in BadmintonCore). Two-device iCloud verification remains the merge gate for behavioral confidence (not CI-provable).

*Why CloudKit (decision):* free, no server to run, Apple ID is the user identity, native offline/push sync — and it is the only Apple-stack path to sharing between different people (`CKShare` operates on CloudKit records). The trade-off — sharing stays Apple-only — is acceptable for a watchOS/iOS product. Per CLAUDE.md, `CloudKitSyncManager`/`AppStore` is the highest-risk area of this codebase: this phase needs plan mode, `/code-review`, and a real two-device test pass, not just green CI.

### Phase 5 — Cross-person sharing (via #93; enables #13)

Decided shape (2026-07-06): private "clubs" — a group of N people (not just a pair) share a roster + match history via CloudKit `CKShare` zone-sharing; a person can belong to several clubs at once, plus keep their existing private history untouched. Explicitly out of scope: a public/global leaderboard (that needs CloudKit's *public* database — a different mechanism and privacy model — and is its own future initiative). Sequenced as its own sub-roadmap, mirroring Phase 6's PR-per-slice pattern:

- **5a — Orientation-neutral `MatchRecord`** ✅ done: `winner` changed from a display-name-copy `String` to a viewer-neutral `RecordSide` (`.near`/`.far`), self-migrating via a custom `Codable` init (no schema-version bump). `StatsCalculator`'s existing `nearTeamNames`/`farTeamNames` helpers were already name/id-agnostic, so this was a smaller, more surgical change than initially scoped — no `teamA`/`teamB` struct rename was needed.
- **5b — `Club`/`clubId` data model** ✅ done: new `Club` model (id/name/createdDate, no membership list yet) plus `clubId: UUID?` on `Player`/`MatchRecord` (`nil` = personal, unchanged). `AppStore` on both targets caches a `clubs` array and exposes `saveClubs` — deliberately local-only (no `CloudSyncManager.pushToCloud()` call), since a real shared club only exists once 5c wires a `CKShare` zone; syncing a throwaway local list now would be replaced work. No UI yet (that's 5d).
- **5c — `CKShare` zone-sharing mechanics** ✅ done: `CloudKitSyncManager` (both targets) now runs two `CKSyncEngine` instances — the existing private-DB engine for personal data, plus a shared-DB engine for club zones. `Club` gained `ownerRecordName: String?` (nil = locally-owned) so a club's per-club `Club-<uuid>` zone can be addressed on either the owner's private DB or a member's shared DB. `fetchOrCreateShare(for:)` creates/fetches the zone-wide `CKShare`; `acceptShare(metadata:)` accepts an invitation and triggers a shared-DB fetch. Each target gained an app/scene delegate (`AppDelegate`+`SceneDelegate` on iOS, `WatchAppDelegate` on watchOS) purely to catch the OS's share-acceptance callback and forward it to `acceptShare`. No UI yet to actually create/send an invite — that's 5e; 5d (club management UI) can land independently.
- **5d — Club management UI** ✅ done (#148): create/rename/leave, member list, per-club roster on both targets — pure UI over the existing `AppStore.saveClubs`/`saveRoster`/`saveHistory`, no `CloudKitSyncManager` changes needed (delete and leave are the same local operation, since `enqueueClubChanges` already branches on `Club.ownerRecordName`). Member list reads live from `CloudKitSyncManager.fetchOrCreateShare(for:)`'s `CKShare.participants`, falling back to just "You" if the share fetch fails — never blocks on CloudKit (local-first invariant). Deleting/leaving a club clears `clubId` back to `nil` on its players/matches rather than deleting them. `PlayerEditView` gained an optional club `Picker` (shown only when a non-empty `clubs` list is passed in) — the only mechanism to assign a player to a club. No match-recording (`MatchRecord.clubId`) tagging UI yet — that's a later slice.
- **5e — Invite UI** ✅ done ([#155](https://github.com/rinaba501/badminton-score-tracker/issues/155)): iOS-only (no watchOS equivalent — `UICloudSharingController` is UIKit-only). `ClubDetailView`'s Members section gets an owner-only "Invite…" button that calls `fetchOrCreateShare(for:)` and presents the resulting `CKShare` via `CloudSharingView`, a new `UIViewControllerRepresentable` wrapper. The accept-flow half already worked end-to-end before this slice — `acceptShare(metadata:)` → `sharedSyncEngine.fetchChanges()` → `applyFetched(_:)` → `AppStore.applyRemoteUpsert` already surfaced an accepted club's participants; 5e only had to build the send side.
- **5f — Multi-club polish** ✅ done ([#157](https://github.com/rinaba501/badminton-score-tracker/issues/157)): club switcher in History/Stats on both targets. Each screen filters `history`/`roster` by `clubId` (Personal + each joined club) before calling into `StatsCalculator` — pure UI filtering, no `StatsCalculator` changes needed. Selection is ephemeral `@State` (not persisted), and the picker is hidden entirely for solo users with no clubs, per the local-first invariant. `Menu` is unavailable on watchOS, so the Watch's `HistoryView` uses a filter button + `.sheet` (matching its existing player-filter pattern) and `StatsView` uses an inline `Picker`; iOS uses a toolbar `Menu` on both screens.

5b–5f get concrete GitHub issues once the prior slice lands, same convention as #133–#139. Every slice touching CloudKit sharing carries its own honestly-stated manual test gate — `CKShare` acceptance needs two different Apple ID accounts, strictly more test burden than Phase 4's still-pending two-device (same-account) test.

**Governing invariant for Phase 5 and all social features (user directive, 2026-07-06): local-first, account-optional.** The app must always stay fully usable by one person scoring everyone with zero accounts — the solo-scorekeeper flow (roster of local players + ad-hoc guests, no sign-in, no network) is the default and never regresses or hides behind account/club flows. Everything below is an *additive opt-in* that must degrade to invisible for a solo user (no sign-in prompts, no "invite friends" empty states). This rests on the **player vs. participant** distinction: a `Player` is a local roster entry (name/avatar/UUID, no Apple ID — already true today); a "participant" is a real Apple ID in a shared club. A roster player MAY optionally be linked to a participant, but never has to be — unlinked names still appear in every stat/standing. Personal history (`clubId == nil`) always coexists with any club data. The New Match flow must never require an account or club.

**Social-features backlog (all wanted; each an opt-in per the invariant above; scope/sequence once clubs exist). Each item below now has a tracking issue:**
- *Match confirmation* ([#160](https://github.com/rinaba501/badminton-score-tracker/issues/160)) ✅ done — `MatchRecord.isConfirmed` (default `true`) and `Club.requireMatchConfirmation` (default `nil`/off) gate a club's matches out of `StatsCalculator.standings` until confirmed, via a call-site filter on `ClubDetailView` (both targets) — same convention as clubId-scoping, `StatsCalculator` itself is unchanged. Owner-only toggle plus a Pending Confirmation section (Confirm/Decline, any club member) on `ClubDetailView`. Decline clears `clubId` back to personal, same as leaving/deleting a club. Anti-cheat caveat: any club participant can already write any field of any record in a shared zone (CloudKit's zone-wide `.readWrite` share has no per-record ACL), so confirm/decline isn't restricted to "the opponent" specifically — an acceptable v1 simplification, since the codebase has no per-record participant-identity tracking today. **Known gap surfacing from this work, fixed via [#169](https://github.com/rinaba501/badminton-score-tracker/issues/169)**: `GameViewModel.saveMatch()` didn't actually set a new match's `clubId` — there was no club picker in `PreMatchView` on either target — so no match recorded through normal play ever landed in a club, leaving both this feature and #159's standings unreachable. `PreMatchView` (both targets) now offers a "Club" picker on its near-side step (hidden if the user has no clubs), threading the selection through to `saveMatch()`'s `MatchRecord(clubId:)`.
- *Club standings / leaderboard, head-to-head, rivalries* ([#159](https://github.com/rinaba501/badminton-score-tracker/issues/159)) ✅ done — `StatsCalculator.standings(history:)` aggregates wins/losses/win-rate per name over an already club-scoped history slice (same `clubId`-filter-before-`StatsCalculator` convention as Phase 5f), sorted by win rate then wins; surfaced as a new Standings section on `ClubDetailView` (both targets). Head-to-head/rivalry drill-down not built yet — this ships the base leaderboard only.
- *Club picker in PreMatchView* ([#169](https://github.com/rinaba501/badminton-score-tracker/issues/169)) ✅ done — see the note above; the prerequisite fix that makes #159 and #160 reachable through normal play.
- *Activity feed* ([#161](https://github.com/rinaba501/badminton-score-tracker/issues/161)) ✅ done — `StatsCalculator.activityFeed(history:)` reverses an already club-scoped, confirmation-filtered slice into newest-first `ActivityFeedEntry` rows (same convention as `standings(history:)` and `filteredHistory`'s reversal), surfaced as a new Activity section on `ClubDetailView` (both targets), placed right after Pending Confirmation. The unread marker is a small dot on `ClubsView`'s club rows, backed by a new local-only `AppStorageKeys.clubLastViewedActivity` (`[String: Date]` JSON dict, club id → last-viewed date, decoded/encoded via the new `ClubActivityCodec` in `AppStorageKeys.swift`) — deliberately excluded from `CloudSyncManager.SyncKeys` since it's per-device read state, not data. Opening `ClubDetailView` marks that club viewed (`onAppear`, alongside `loadParticipants()`); no separate "mark as read" control.
- *Challenges* ([#162](https://github.com/rinaba501/badminton-score-tracker/issues/162)) ✅ done — new `ChallengeRecord` CKRecord type (`BadmintonCore/ChallengeRecord.swift`) synced through the same per-record `CKSyncEngine` path as history/roster (a challenge always belongs to a club zone, never the personal one). Unlike Club/Player/MatchRecord, the two parties are real CKShare participants rather than roster `Player`s — a `Player` has no Apple ID link — so `fromParticipantId`/`toParticipantId` are each a `CKShare.Participant.userIdentity.userRecordID.recordName`, with `CKShare.currentUserParticipant` resolving "me" (no new CloudKit API needed). `ClubDetailView` (both targets) gained a "Challenge" button per member row and a Challenges section (accept/decline/cancel), placed after Pending Confirmation. Challenges are CloudKit-only with no KV-store fallback — the feature is simply invisible when CloudKit sync is off. Known pre-existing limitation this doesn't fix: `fetchOrCreateShare(for:)` only works for the club's owner, so — like the 5e invite button — challenges work reliably for owners today.
- *Seasons* ([#163](https://github.com/rinaba501/badminton-score-tracker/issues/163)) — time-boxed standings resets (date-filter over history + a stored boundary).
- *Reactions / comments on a match* ([#164](https://github.com/rinaba501/badminton-score-tracker/issues/164)) — 👍/🔥 or a one-line note (CKRecord children of a match).
- *Notifications* ([#165](https://github.com/rinaba501/badminton-score-tracker/issues/165)) — for async interactions (confirmation, challenges); needs `aps-environment` (deliberately left off in Phase 4) — add only once there's async interaction worth announcing.
- *Ambitious / own initiatives (like the public leaderboard):* live spectating, tournament brackets.

### Phase 6 — iOS companion app (#41)

A new iOS target consuming `BadmintonCore`: history/stats/roster with `NavigationStack`, share-sheet export (#13), and — as a follow-up after the browse screens — live scoring on the phone (tap-only; no Digital Crown or HealthKit). **Shipped** across PRs #133–#139 (see the issue map and [docs/ios-companion-app-plan.md](docs/ios-companion-app-plan.md)). Still open for a later pass: an iOS widget and the account/sharing management UI from Phase 5. Two-device sync verification remains deferred on hardware.

### Phase 7 — Friend graph (v1, graph-only; not yet issue-tracked)

Decided shape (confirmed with the user 2026-07-10): a real, club-independent friend graph — `FriendRequest`/`FriendProfile` records in CloudKit's **public** database (the first public-DB usage in this codebase; `CKSyncEngine` only drives private/shared DB), found via out-of-band invite link/code exchange, not a searchable directory or Contacts-based discovery. V1 is explicitly **graph-only**: request/accept/decline + a friends list. It does **not** wire up shared match history/a CKShare zone per friendship — that's a deliberate future phase, mirroring how Club itself was sliced (5b data model → 5c sharing mechanics → 5d UI). Friends stays free (not Pro-gated), consistent with `Entitlements.swift`'s "scoring, history, roster, clubs stay free" invariant. Sequenced as its own sub-roadmap, same slicing convention as Phase 5:

- **7a — Data model** ✅ done: `FriendProfile.swift` (public-DB discoverable profile, keyed by `participantId` = `CKContainer.fetchUserRecordID()`, not a `CKShare.Participant` id) and `FriendRequest.swift` (mirrors `ChallengeRecord`'s shape minus `clubId`; an accepted request *is* the friendship edge, no separate `Friendship` record) in `BadmintonCore`, plus the matching `PersistenceStore` codecs/diff and `AppStorageKeys` (`friendRequests`, `myParticipantId`, `myFriendsDisplayName`). Pure model + unit tests, no CloudKit, no UI.
- **7b — Public-DB plumbing** ✅ done: `CloudKitSyncManager` (both targets) gains a `publicDatabase` property and direct `CKDatabase` calls (`resolveMyParticipantId`, `ensureMyProfileExists`, `fetchProfile`, `sendFriendRequest`, `respondToFriendRequest`, `fetchMyFriendRequests`) — public DB isn't `CKSyncEngine`-managed, so these are plain async calls, not sync-engine events. No push/subscription in v1; incoming requests are found by polling on Friends-screen appear + pull-to-refresh (a `CKQuerySubscription` upgrade is a named, non-blocking follow-up). Callable but unreached — no AppStore wiring or UI yet (7c/7e). Needs CloudKit Dashboard schema changes (public-DB `FriendProfile`/`FriendRequest` record types, `fromParticipantId`/`toParticipantId` marked Queryable, `_world`/`_icloud` Read+Write security role) — not an Xcode entitlements change; not yet CI-provable, gated on a manual two-Apple-ID sandbox test once 7e lands.
- **7c — AppStore integration** ✅ done: `@Published friendRequests`, `saveFriendRequests` (CloudKit-only, no KV fallback, same convention as `saveChallenges`/`saveReactions` — but note the asymmetry that friend-request writes go straight to the public DB rather than through an `enqueue*`/CKSyncEngine round-trip), and a `friends` computed property derived from accepted requests (no independent synced array). Callable but unreached — no UI yet (7d/7e).
- **7d — Invite link + deep link consumption** ✅ done: `badminton://addfriend?id=<participantId>&name=<name>` alongside the existing `badminton://newmatch` scheme — `FriendInviteLink` in `BadmintonCore` (pure build/parse; the embedded name is editable UGC, so it's trimmed + capped at 50 chars on both sides; unit-tested) plus iOS-only consumption: the `badminton` scheme registered in the iOS Info.plist and `ContentView.onOpenURL` presenting `FriendInviteView`, a confirmation sheet that never writes to CloudKit until the user confirms. Confirming upserts my `FriendProfile` (roster "Me" name as the display-name fallback until 7e's prompt), then `sendFriendRequest` → `fetchMyFriendRequests` → `AppStore.saveFriendRequests`. No CKShare/share-metadata plumbing involved. `ShareLink` *generation* moved to 7e — it needs the FriendsView entry point that doesn't exist yet; Watch-side consumption is likewise deferred into 7e's watch-usability decision.
- **7e — Friends UI** ✅ done: `FriendsView.swift` on both targets (incoming/outgoing pending requests with accept/decline/cancel, friends list, add-friend `ShareLink`), entry-point rows in iOS `ContentView.swift` (with a numeric pending-request badge) and Watch `SettingsView.swift` next to the existing Clubs row, plus a one-time display-name prompt (a sheet shown when `myFriendsDisplayName` is empty, replacing `FriendInviteView`'s silent roster-name fallback — that fallback stays as a backstop for a deep link opened before `FriendsView` is ever visited). Resolved open question: unlike Phase 5e's club invite (`UICloudSharingController`, UIKit-only, hence iOS-only), a friend invite is just a `URL` (`FriendInviteLink.url`) — `ShareLink(item:)` works natively on watchOS and needs no keyboard, so invite *generation* shipped on both targets, symmetric with `ClubsView`. `respondToFriendRequest`/`fetchMyFriendRequests` calls follow the same `Task { @MainActor in ... }` pattern `FriendInviteView.send()` established.
- **7f — code-entry fallback** ✅ done: `FriendsView` on both targets gains a second "Enter a Code" row alongside the `ShareLink` invite. Accepts either a full `badminton://addfriend?...` link (via `FriendInviteLink.parse`) or a bare pasted `participantId`; validates it with `CloudKitSyncManager.fetchProfile(participantId:)` (fails soft to a "no player found" error) before calling `ensureMyProfileExists`/`sendFriendRequest`, reusing the same `FriendRequestError.selfRequest`/`.alreadyPending` handling `FriendInviteView.send()` established.
- **7f — push subscription upgrade** ✅ done, **unverified**: `CloudKitSyncManager.ensureFriendRequestSubscriptionExists()` (both targets) registers a best-effort `CKQuerySubscription` on the public-DB `FriendRequest` type (predicate `toParticipantId == me`, silent/`shouldSendContentAvailable` push), called from each app delegate's `didRegisterForRemoteNotifications` callback. `WatchAppDelegate`/iOS `AppDelegate` now call `registerForRemoteNotifications()` on launch and handle the resulting silent push by re-running `fetchMyFriendRequests()` → `AppStore.saveFriendRequests`. Fixed the iOS entitlements asymmetry along the way — `aps-environment` existed on the Watch target only, now added to iOS too. Every step fails soft: if the subscription never registers or the push never arrives, `FriendsView`'s existing poll-on-appear/pull-to-refresh is completely unaffected. **Not CI-provable, no simulator smoke test possible either** — needs a real two-device, two-Apple-ID push test before this can be trusted (worse than the two-device `CKShare` caveat already carried by 5c/7b, since not even a single-device smoke test is possible here).
- **7g — Link local identity to one account** ✅ done: a new `SettingsSnapshot.accountLinked` `Bool` (blind-overwrite on apply, like the other plain Bool settings — no destructive-merge guard needed since old payloads decode it to `false` via the usual `decodeIfPresent` migration) is the explicit "zero or one linked CloudKit account" gate the user asked for, distinct from today's implicit linking (opening Friends already calls `ensureMyProfileExists` once a display name is set). `FriendsView` (both targets) gains an "Account" section: unlinked shows a "Link This Device" button (reusing the existing display-name prompt sheet if no name is set yet), linked shows "Linked as `<name>`" + an "Unlink" button. Unlinking is non-destructive — it only clears the local flag, never the `FriendProfile`/friends list/club membership. `ClubDetailView` (both targets) reads `accountLinked` to show `myFriendsDisplayName` on the "You" row instead of the generic fallback, and — since `CKShare.Participant.userIdentity.userRecordID` and `FriendProfile.participantId` (`CKContainer.fetchUserRecordID()`) resolve to the same underlying CloudKit account id for a given Apple ID, a fact never previously exploited in this codebase — cross-references each fetched club member's id against `AppStore.friends` to show a friend badge. No new CloudKit schema, no new API calls: a local `Set`-based lookup over data already being fetched.

Known open risk carried into 7b: a `FriendProfile` display name is public-DB UGC, reachable only via link/code (not searchable), which is materially lower-exposure than the public leaderboard below but still warrants a fresh App Store Guideline 1.2 sign-off rather than inheriting that initiative's "deferred" verdict — mitigate cheaply with client-side length/content validation before publish.

### Future initiative — public/global leaderboard (not yet scoped)

Explicitly out of Phase 5's scope (confirmed with the user 2026-07-06), but wanted eventually: a public, discoverable leaderboard beyond private clubs. Would use CloudKit's *public* database — a separate mechanism, schema, and access model from the `CKShare` private-sharing path Phase 5 builds — so it doesn't block or get blocked by Phase 5. Real added cost vs. private sharing: Apple's App Store Guideline 1.2 requires report/block/moderation tooling for any public user-generated content before Apple will approve it (not optional polish), plus anti-cheat/score-validation work since a public leaderboard invites manipulation in a way a trusted private club doesn't. CloudKit's own cost stays low (pricing scales with app users and is free at this app's likely volume) — the cost is almost entirely the moderation + integrity engineering. File a concrete issue and design discussion when ready to scope it; no code exists for this yet.

### Phase 8 — Feathers & Gacha (design complete, not yet implemented)

An earned soft currency ("Feathers") + cosmetic gacha with real-money paid pulls.
Economy model deliberately avoids stored paid value (paid pulls are consumables that
execute immediately) to stay clear of Japan's prepaid-instrument law and refund/sync
hazards; prize pool is new code-drawable cosmetics, disjoint from the existing
Pro/pack IAPs, so `Entitlements.swift` is untouched. Full design — economy, odds,
ledger data model, StoreKit redemption, phase slicing 8a–8f — in
[docs/gacha-design.md](docs/gacha-design.md) (confirmed with the user 2026-07-17).

### Phase 9 — Backend migration to Supabase/Postgres (9a-9c done, 9d in progress)

Full cutover: eventually replace CloudKit with a Postgres backend (Supabase:
Postgres + Auth + Realtime) on every platform, including the existing Watch/iOS
app — not a permanent dual-backend, and not a separate non-syncing backend for
a future non-Apple client. Decided shape (confirmed with the user 2026-07-19),
motivated by keeping the door open to Android/web clients that share real data
with the existing app rather than forking the product. Builds on `CloudSyncSpike`
(merged, DEBUG-only — see `CLAUDE.md`), which validated the two hardest unknowns:
Google OAuth → Supabase → Postgres identity works end-to-end, and a watchOS app
with no browser can adopt a session relayed from the paired iPhone over
`WCSession` and make independent, RLS-scoped Postgres calls afterward. Full
design — target schema, identity model, sub-phase slicing 9a–9f, open risks —
in [docs/supabase-migration-plan.md](docs/supabase-migration-plan.md).

Sequenced as its own sub-roadmap, same slicing convention as Phase 5/7:

- **9a — Foundation** ✅ done: production Postgres schema + RLS policies,
  tracked in [supabase/schema.sql](supabase/schema.sql) and applied to the
  existing `CloudSyncSpike` project (all 10 tables verified with RLS
  enabled). No app code changes yet.
- **9b — `SyncEngine` abstraction** ✅ done: a protocol
  ([BadmintonCore/Sources/BadmintonCore/SyncEngine.swift](BadmintonCore/Sources/BadmintonCore/SyncEngine.swift))
  capturing the 14 methods `AppStore` calls to push local changes out;
  `CloudKitSyncManager` (both targets) conforms unchanged, and `AppStore` now
  holds an injected `syncEngine: SyncEngine`, set to `CloudKitSyncManager.shared`
  at `static let shared`
  instead of 20 hardcoded call sites — a pure, behavior-preserving refactor
  that creates the seam 9c swaps behind. The reverse direction
  (`applyRemote*` callbacks) stays outside the protocol; `AppStore` is still a
  concrete singleton any backend calls into directly.
- **9c — Personal data cutover**: Settings + personal (`clubId == nil`)
  Player/MatchRecord move to Supabase; real Google Sign-In + `WCSession`
  relay promoted from the spike; opt-in, CloudKit stays default for everyone
  else per the local-first invariant. Sliced further (own PRs each):
  - **9c-1** ✅ done: `CloudSyncSpike`'s spike client promoted to production —
    `SupabaseConfig` (hardcoded real project URL/anon key, replacing the
    env-var/placeholder pattern) and `SupabaseSyncManager` (auth methods kept,
    stale test-record CRUD replaced with real `players`/`match_records`/
    `settings` CRUD against the Phase 9a schema). Since a shared package can't
    import `AppStore`, each target gained its own thin `SupabaseSyncEngine.swift`
    adapter that actually conforms to `SyncEngine` — mirrors how
    `CloudKitSyncManager` itself is duplicated per target rather than shared.
    The stale `CloudSyncSpikeView`/DEBUG Settings row (targeting the old spike
    schema) were removed as part of this slice rather than left broken.
  - **9c-2** ✅ done: `AppStore.syncEngine` → `private(set) var`,
    `static let shared` reads `AppStorageKeys.supabaseAccountLinked` so a
    relaunch stays on whichever backend was last active. New
    `activateSupabaseSync()`/`deactivateSupabaseSync()` (the flag write
    itself stays the caller's job, same as `accountLinked`'s existing
    `linkAccount()`/`unlinkAccount()`) — migration-on-signin is just those
    methods re-enqueueing every existing id, no bespoke code. Also closed
    the three things 9c-1's `/code-review` flagged as becoming live here:
    a private serial task chain in `SupabaseSyncEngine` (writes now apply
    in call order instead of racing), batched upsert/delete (`PendingRecord`
    replacing a 4-element tuple `SwiftLint`'s `large_tuple` rule rejected)
    instead of one request per record, and `currentSettingsSnapshot()`
    moved onto `AppStore` itself so `CloudKitSyncManager` and
    `SupabaseSyncEngine` share one copy per target instead of one each.
  - **9c-3** ✅ done: a real "Sync Backend" Settings section on both targets,
    reusing the `accountLinked` link/unlink pattern. iOS performs Google
    Sign-In (`SupabaseSyncManager.shared.signInWithGoogle(presentationAnchor:)`)
    then relays the session to the Watch (`AppDelegate.relaySessionToWatch`)
    before calling `AppStore.shared.activateSupabaseSync()`; the Watch never
    signs in itself — its row stays informational ("sign in on your iPhone
    first") until a relayed session arrives, then offers its own explicit
    activate button, so receiving a relay never silently flips the Watch's
    transport without a Watch-side confirmation. Turned out the WCSession
    relay promotion originally scoped for this slice was already done in
    9c-1 (it referenced the production `SupabaseSyncManager`, not stale spike
    code), so this slice ended up UI-only. Still owed: a real-account,
    two-device verification pass (same not-CI-provable gate CloudKit sync
    correctness already has).
  - **9c-4** ✅ done: all 33 View-level
    `CloudKitSyncManager.shared.enqueueSettingsChange()` direct calls
    (flagged in 9b's `/code-review`) now go through a new
    `AppStore.enqueueSettingsChange()` passthrough (`syncEngine.
    enqueueSettingsChange()`) instead — a Supabase-active device no longer
    silently keeps writing settings to CloudKit. Purely mechanical: every
    call site was a bare statement with no other CloudKit-specific logic, so
    this was a mass find-and-replace plus the one new passthrough method,
    not a redesign.
  - **9c-5/9c-6** ✅ done, and these — not 9c-4 — are what actually closes
    out 9c. While researching 9d it turned out `SupabaseSyncEngine` was
    push-only: nothing pulled remote changes back into `AppStore`, so two
    of a user's own devices on Supabase wouldn't see each other's writes
    (the earlier "9c-4 closes out 9c" note above was written before this
    was discovered). 9c-5 added the transport
    (`SupabaseSyncManager.startRealtimeSync`/`stopRealtimeSync` via
    `RealtimeChannelV2` Postgres Changes, plus `fetchAllRows`/`fetchSettings`
    for a one-time catch-up read) — its own `/code-review` caught that the
    `owner_id` Realtime filter would silently drop DELETE events on
    `players`/`match_records` under Postgres's default `REPLICA IDENTITY`
    (only primary-key columns are logged for a delete's old-row image, and
    `owner_id` isn't the primary key on either table), fixed by adding
    `REPLICA IDENTITY FULL` for both in `supabase/schema.sql`. 9c-6 wired it
    in: `SupabaseSyncEngine.startIfActive()` (called from
    `activateSupabaseSync()` after the existing migration-on-signin push,
    and unconditionally — cheaply, since it's a no-op for anyone
    unlinked — at app launch on both targets) does the catch-up pull then
    opens the Realtime subscription; `handleRemoteChange` decodes each
    change via `PersistenceStore` and applies it through the same
    `AppStore.applyRemoteUpsert`/`applyRemoteDeletions`/`applyRemoteSettings`
    CloudKit already uses. Self-echoes (a device receiving its own push
    back) are expected and harmless since those applies merge by id.
    `supabase/schema.sql` also gained `alter publication supabase_realtime
    add table public.players, public.match_records, public.settings` — a
    table's changes never enter the replication stream at all without it,
    independent of any client-side subscription — which the user needs to
    run in the Supabase SQL editor alongside the `REPLICA IDENTITY FULL`
    statements above, same manual-SQL pattern as 9a. **Phase 9c (personal
    data cutover) is genuinely complete now — push and pull both real** —
    still pending a real-account, two-device verification pass (not
    CI-provable, same gate CloudKit sync correctness already has).
- **9d — Clubs cutover**: an explicit `club_members`/`club_invites` model
  replaces CKShare's implicit "share = membership" zone-sharing. Sliced into
  its own dedicated plan-mode pass (see `docs/supabase-migration-plan.md`),
  further split into 9d-1/9d-2/9d-3:
  - **9d-1** ✅ done: `clubs`/`challenges`/`reactions` push + pull sync, using
    the same `id`+`payload jsonb` shape `players`/`match_records` already use
    — `SupabaseSyncManager` gained `ClubPendingRecord`/`ChallengePendingRecord`/
    `ReactionPendingRecord` (none of the 3 tables fit the existing
    `PendingRecord` shape: `clubs` has no `club_id`, `challenges`/`reactions`
    have no single `owner_id`) plus matching batched `upsert*`/`delete*`
    methods; `SupabaseSyncEngine`'s `enqueueClubChanges`/
    `enqueueChallengeChanges`/`enqueueReactionChanges` are now real (were
    no-op stubs since 9c), and `pullInitialState`/`handleRemoteChange` gained
    matching cases. `Club.ownerRecordName` is reused as a backend-opaque
    owner id under Supabase (`nil` = self-owned, same semantics CloudKit
    already gives it) — `RemoteChange` gained an `ownerId: UUID?` field so a
    receiving device backfills it from the row's real `owner_id` column
    rather than trusting the payload (a club's owner always encodes their
    own `ownerRecordName` as `nil`, which a receiving member must not adopt
    as-is). `ChallengeRecord`/`ReactionRecord`'s opaque participant-id
    `String` fields hold this account's `auth.uid()` string when
    Supabase-active, same opaque-per-backend-id pattern. Also fixed a
    Realtime design gap exposed by adding these tables: the existing
    `owner_id=eq.<uid>` client-side filter (9c-5) was already too narrow —
    it silently dropped other club members' updates to `players`/
    `match_records` — and can't even apply to `challenges`/`reactions`
    (no `owner_id` column). Removed the filter entirely; delivery now relies
    on RLS alone, which Supabase's Postgres Changes feature already enforces
    per-row for realtime the same as for a regular query. New SQL:
    `alter publication supabase_realtime add table public.clubs,
    public.challenges, public.reactions;` — same "user must run this in the
    SQL editor" handoff as every prior schema addition. This slice's own
    `/code-review` caught a repeat of 9c-5's REPLICA IDENTITY bug, this time
    on `challenges`/`reactions`: their RLS policies need `club_id`/
    `author_id`, neither a primary-key column, so without `REPLICA IDENTITY
    FULL` a DELETE's old-row image can't satisfy RLS for anyone — the event
    fails closed for every subscriber (including the legitimate club
    member), and since `fetchAllRows` never reports deletes, a deleted
    challenge/reaction would never sync at all. `clubs` genuinely doesn't
    need it (its `is_club_member(id)` policy branch only needs the row's
    own primary key). Fixed before merge by adding `REPLICA IDENTITY FULL`
    for both tables. Both cross-cutting
    design questions the original 9d sketch left open are resolved, not
    deferred: participant-id remapping needed no model change (see above),
    and `reactions.club_id`'s Postgres cascade-delete turned out to already
    match CloudKit's own zone-delete cascade — not a divergence.
  - **9d-2** ✅ done: `club_members` has no direct INSERT policy (9a's own
    RLS comment already anticipated this) — a new `SECURITY DEFINER`
    Postgres function, `redeem_club_invite(invite_id)`, validates a
    `club_invites` row's expiry/`max_uses`/`use_count` (row-locked via
    `for update` to close a race between two concurrent redemptions) then
    inserts the caller into `club_members`, mirroring how `handle_new_club()`
    already bypasses the caller's own insert privilege for owners. `SupabaseSyncManager`
    gained `createClubInvite`/`redeemClubInvite`; new `ClubInviteLink.swift`
    (`BadmintonCore`, byte-shape mirror of `FriendInviteLink.swift`,
    `badminton://joinclub?id=<inviteId>&name=<clubName>`) and iOS-only
    `ClubInviteView.swift` (mirrors `FriendInviteView.swift`), wired into
    `ContentView`'s `onOpenURL` as a second parse attempt after
    `FriendInviteLink.parse` misses. `ClubDetailView`'s owner-only Invite
    button (both targets) now branches on `supabaseAccountLinked`:
    CloudKit-active keeps `CloudSharingView` completely unchanged;
    Supabase-active creates an invite then presents a `ShareLink` over the
    `ClubInviteLink` URL — no CKShare involved, so this is the **Watch's
    first invite-sending affordance** (CKShare invites were always iOS-only,
    `UICloudSharingController` being UIKit-only). New SQL (external setup,
    flagged to user): the `redeem_club_invite` function itself.
  - **9d-3** ✅ done: `SupabaseSyncManager.fetchClubMembers(clubId:)` (joins
    `club_members` against `profiles` for display names — two client-side
    queries, not a PostgREST embed, since both tables reference `auth.users`
    and not each other) as the Supabase-active branch of `ClubDetailView.
    loadParticipants()`. `profiles` was left unpopulated through 9d-1/9d-2
    (deferred to 9e by 9a's own schema comment); this slice adds a narrow
    `upsertMyProfile(displayName:)`, called from `SupabaseSyncEngine.
    startIfActive()` on every activation/launch, so club membership has *a*
    name to show sooner than 9e lands. New `leaveClub`/`removeMember` (both
    covered by the existing `club_members_delete` RLS policy — self or
    owner — no new SQL needed): a non-owner's "leave" now explicitly calls
    `leaveClub` alongside the existing `saveClubs` diffing, since Supabase's
    owner-only `clubs_delete` RLS means that diffing's implicit delete alone
    silently no-ops for a non-owner (the owner's real delete still cascades
    to `club_members` via the FK, unchanged). Both targets also gained an
    owner-only swipe-to-kick action on the member list, gated to
    Supabase-active — CloudKit never needed one, since
    `UICloudSharingController`'s own system UI already offers participant
    management. `isFriend` is hardcoded false for Supabase-active members:
    Friends stays CloudKit-only until 9e, so there's no cross-backend id to
    match against yet. **Phase 9d (Clubs cutover) is now complete.**
- **9e — Friends graph cutover**, split into 9e-1/9e-2/9e-3/9e-4:
  - **9e-1** ✅ done: `FriendProfile`/`FriendRequest` push + pull, reusing
    `profiles` (9d-3) and `friend_requests` (9a) with no new tables —
    `profiles.id`/`friend_requests.from_participant_id`/`to_participant_id`
    already are `auth.uid()` directly, simpler than the CKShare-participant-id
    parsing challenges/reactions needed. `SupabaseSyncManager` gained
    `fetchProfileDisplayName`/`sendFriendRequest`/`respondToFriendRequest`
    (all primitives-only — this package has no `BadmintonCore` dependency, so
    it never builds a `FriendRequest`/`FriendProfile` itself, unlike every
    other method here view/engine callers build the model and pass
    id/participant-ids/an already-encoded payload). No new pull method
    needed: `friend_requests` is id-keyed like every other table, so the
    existing `fetchAllRows`/Realtime machinery covers it — `friend_requests`
    just joined `pullTables`, with a new `SupabaseSyncEngine.
    refreshFriendRequests()` doing a full refetch-and-reconcile (not a
    per-id merge, matching `saveFriendRequests`'s existing "here is the
    complete current list" contract) on the initial pull and on every
    Realtime event regardless of kind. Real correctness gap found and fixed:
    `AppStore.friends` reads `AppStorageKeys.myParticipantId` directly,
    populated only by CloudKit's `resolveMyParticipantId()` — a
    Supabase-active device never called that, so `AppStore.friends` would
    have silently stayed empty forever; fixed by caching `currentUserId()`
    into the same key from `SupabaseSyncEngine.startIfActive()`. Also
    widened `friend_requests_delete` RLS from sender-only to either-party
    (symmetric with `club_members_delete`), needed so a full teardown can
    clean up requests where this account is only the recipient; added the
    same `REPLICA IDENTITY FULL` fix now applied three times (9c-5, 9d-1,
    9e-1) since `friend_requests`' RLS reads non-PK columns. Every
    `CloudKitSyncManager.shared.ensureMyProfileExists`/`fetchProfile`/
    `sendFriendRequest`/`respondToFriendRequest`/`fetchMyFriendRequests`
    call site (both targets' `FriendsView.swift`/`ContentView.swift`/
    `ClubDetailView.swift`, iOS `ProfileView.swift`/`FriendInviteView.swift`)
    branches on `supabaseAccountLinked`.
  - **9e-2** ✅ done: new `friend_identity_snapshots`/`friend_stats_snapshots`
    tables — `id`+`payload jsonb` like every other Phase 9 table (not the
    discrete-column shape originally sketched; reusing the generic
    `fetchAllRows`/Realtime machinery unchanged beat bespoke per-column
    decode logic), one row per owner, each field populated only when its
    share toggle is on — never a live RLS grant on `settings`, which would
    leak every unrelated scalar setting to any accepted friend. New
    `is_accepted_friend` RLS helper (mirrors `is_club_member`); neither
    table needs `REPLICA IDENTITY FULL` (RLS only reads the row's own PK).
    `SupabaseSyncEngine.enqueueFriendIdentityChange`/
    `removeFriendIdentityRecord`/`enqueueFriendStatsChange` (ports
    `CloudKitSyncManager.currentFriendIdentitySnapshot`/
    `currentFriendStatsSnapshot`'s toggle-gating verbatim) plus a new
    `removeFriendStatsRecord` — added to the `SyncEngine` protocol itself,
    closing a real pre-existing gap: `FriendSharingSettingsView.
    toggleStatsSharing` (and its iOS `ProfileView`/`StatsView`/`HistoryView`
    duplicates) called `CloudKitSyncManager.shared.enqueueFriendStatsChange`/
    `.removeFriendStatsRecord` directly instead of through `AppStore.
    syncEngine`, the same View-bypass pattern 9c-4 fixed for
    `enqueueSettingsChange` — invisible before Supabase existed since
    `CloudKitSyncManager.shared` and `AppStore.syncEngine` were always the
    same object. `enqueueFriendsRosterChanges`/`enqueueFriendsHistoryChanges`
    stay permanent no-ops under Supabase (not "not yet migrated" — a
    personal record already pushes unconditionally via
    `enqueueRosterChanges`/`enqueueHistoryChanges`; 9e-3 grants friend
    visibility via RLS on that same row, no mirrored copy needed).
  - **9e-3 — Friend history sharing**: extends already-live
    `players_select`/`match_records_select` RLS with a friend-visibility
    branch — no mirrored copy needed (unlike CloudKit's separate
    "FriendsHistory" zone), since Postgres RLS grants row-level access to
    the *original* rows directly; the real work is teaching
    `SupabaseSyncEngine`'s pull/Realtime routing not to merge a friend's
    now-visible personal rows into this device's own roster/history.
  - **9e-4 — Erase-all-data teardown + any remaining UI wiring** left over
    from 9e-2/9e-3.
- **9f — Dual-run validation & cutover**: both backends live for opted-in users
  during a validation window, then flip the default and retire CloudKit —
  the point a non-Apple client becomes buildable against the same backend.

9a–9f get concrete GitHub issues once the prior slice lands, same convention as
#133–#139 and Phase 5b–5f. RLS bugs mean cross-user data leaks — a strictly
higher-stakes failure mode than a CKShare bug — so every slice from 9c onward
needs real multi-account verification before merge, not just green CI, sharper
than Phase 4/5's two-device gate. Per CLAUDE.md, any slice touching
`AppStore`/the sync layer goes through plan mode first.

### Guardrails track (#110) — do anytime

Cheap, independent CI hardening: a localization key-sync check across the 6 locales, code-coverage reporting on the test job, a build job for the Complication target, deployment-target alignment (Complication 26.5 vs app 11.4), and eventually a lightweight release process (semver tags + changelog).

---

## Issue map

| Phase | Issue(s) | Status |
|-------|----------|--------|
| 1 — BadmintonCore package | [#106](https://github.com/rinaba501/badminton-score-tracker/issues/106) | Closed by PR [#112](https://github.com/rinaba501/badminton-score-tracker/pull/112) |
| 2 — De-view business logic | [#96](https://github.com/rinaba501/badminton-score-tracker/issues/96) | Closed by PR [#113](https://github.com/rinaba501/badminton-score-tracker/pull/113) |
| 3 — Schema versioning / identity | [#107](https://github.com/rinaba501/badminton-score-tracker/issues/107) closed by PR [#114](https://github.com/rinaba501/badminton-score-tracker/pull/114); [#108](https://github.com/rinaba501/badminton-score-tracker/issues/108) closed by PR [#115](https://github.com/rinaba501/badminton-score-tracker/pull/115) (`MatchRecord.winner` type change deferred — see PR notes); KV quota stopgap: [#87](https://github.com/rinaba501/badminton-score-tracker/issues/87) closed by PR [#117](https://github.com/rinaba501/badminton-score-tracker/pull/117) | Done |
| 4 — CloudKit sync | [#109](https://github.com/rinaba501/badminton-score-tracker/issues/109) | Code-complete on both targets — pure core helpers (PR [#129](https://github.com/rinaba501/badminton-score-tracker/pull/129)), inert `CKSyncEngine` path on the Watch, and the iOS port + Settings toggle on both targets (this PR). Default stays off pending a real two-device iCloud test — not CI-provable |
| 5 — Cross-person sharing | design in [#93](https://github.com/rinaba501/badminton-score-tracker/issues/93); enables [#13](https://github.com/rinaba501/badminton-score-tracker/issues/13) | 5a (orientation-neutral MatchRecord), 5b (Club/clubId data model), 5c (CKShare zone-sharing mechanics), 5d (club management UI, [#148](https://github.com/rinaba501/badminton-score-tracker/issues/148)), 5e (invite UI, [#155](https://github.com/rinaba501/badminton-score-tracker/issues/155)), and 5f (multi-club polish, [#157](https://github.com/rinaba501/badminton-score-tracker/issues/157)) done — Phase 5 complete except the future social-features backlog |
| 6 — iOS companion app | [#41](https://github.com/rinaba501/badminton-score-tracker/issues/41) | Feature-complete — PR1 (#133 shell+CI), PR2 (#135 iCloud KV sync), PR3 (#136 History+Stats), PR4 (#137 Roster), PR5 (#138 Share, closed #13), PR6 (#139 live scoring on iPhone) — see [docs/ios-companion-app-plan.md](docs/ios-companion-app-plan.md). Two-device sync tests still pending (deferred, no hardware). Watch app is no longer WKWatchOnly as of PR1 — archive an earlier commit for a watch-only App Store submission |
| 7 — Friend graph (v1, graph-only) | not yet issue-tracked | 7a-7g done (data model, public-DB plumbing, AppStore integration, invite link + deep-link consumption, Friends UI, code-entry fallback, push subscription, link-to-one-account) — the push-subscription half is unverified, needs a real two-device test |
| 8 — Feathers & Gacha | [#244](https://github.com/rinaba501/badminton-score-tracker/issues/244) | Design complete ([docs/gacha-design.md](docs/gacha-design.md)); 8a–8f not started |
| 9 — Backend migration (Supabase/Postgres) | not yet issue-tracked | Design in [docs/supabase-migration-plan.md](docs/supabase-migration-plan.md); 9a done ([supabase/schema.sql](supabase/schema.sql)), 9b done ([SyncEngine.swift](BadmintonCore/Sources/BadmintonCore/SyncEngine.swift)), 9c done (9c-1–9c-6: production SupabaseSyncManager, AppStore backend-switch plumbing, Sync Backend Settings UI, View-bypass fix, Realtime pull-side sync transport + wiring — push AND pull now both real), **9d done** (9d-1: clubs/challenges/reactions push+pull sync + Realtime filter fix; 9d-2: redeem_club_invite RPC + ClubInviteLink/ClubInviteView, Watch's first invite-sending affordance; 9d-3: member-list read via club_members/profiles + leave/kick), 9e in progress (9e-1 done: FriendProfile/FriendRequest push+pull, reusing profiles/friend_requests with no new tables; 9e-2 done: friend identity/stats sharing via two new snapshot tables + a View-bypass fix for stats toggling; 9e-3/9e-4 next), 9f not started |
| Guardrails | [#110](https://github.com/rinaba501/badminton-score-tracker/issues/110) | Closed by PR [#116](https://github.com/rinaba501/badminton-score-tracker/pull/116) |

Independent feature work (e.g. doubles support, [#8](https://github.com/rinaba501/badminton-score-tracker/issues/8)) is unaffected by this sequencing, though doubles will be cheaper after Phase 3's orientation-neutral groundwork.

## Maintaining this document

Update the Issue map when a phase's issue closes, and revisit the phase ordering if a decision changes. Per the repo convention, structural changes made while executing a phase must update CLAUDE.md in the same PR.
