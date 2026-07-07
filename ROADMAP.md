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

### Phase 4 — CloudKit private-database sync (#109)

Replace the single-blob KV-store sync with the CloudKit private database: one `CKRecord` per match and per player, real deletion propagation (retiring the `isHistoryShrink` overwrite heuristic), push-based change notifications, and no practical size ceiling. Scalar settings can stay on the KV store. **Code-complete on both targets** (Watch + iOS `CloudKitSyncManager`/`AppStore` branches, CloudKit container entitlement on both), gated behind a Settings toggle (`cloudKitSyncEnabled`, default off everywhere) — still pending the two-device test before the default flips on.

*Why CloudKit (decision):* free, no server to run, Apple ID is the user identity, native offline/push sync — and it is the only Apple-stack path to sharing between different people (`CKShare` operates on CloudKit records). The trade-off — sharing stays Apple-only — is acceptable for a watchOS/iOS product. Per CLAUDE.md, `CloudSyncManager`/`AppStore` is the highest-risk area of this codebase: this phase needs plan mode, `/code-review`, and a real two-device test pass, not just green CI.

### Phase 5 — Cross-person sharing (via #93; enables #13)

Decided shape (2026-07-06): private "clubs" — a group of N people (not just a pair) share a roster + match history via CloudKit `CKShare` zone-sharing; a person can belong to several clubs at once, plus keep their existing private history untouched. Explicitly out of scope: a public/global leaderboard (that needs CloudKit's *public* database — a different mechanism and privacy model — and is its own future initiative). Sequenced as its own sub-roadmap, mirroring Phase 6's PR-per-slice pattern:

- **5a — Orientation-neutral `MatchRecord`** ✅ done: `winner` changed from a display-name-copy `String` to a viewer-neutral `RecordSide` (`.near`/`.far`), self-migrating via a custom `Codable` init (no schema-version bump). `StatsCalculator`'s existing `nearTeamNames`/`farTeamNames` helpers were already name/id-agnostic, so this was a smaller, more surgical change than initially scoped — no `teamA`/`teamB` struct rename was needed.
- **5b — `Club`/`clubId` data model** ✅ done: new `Club` model (id/name/createdDate, no membership list yet) plus `clubId: UUID?` on `Player`/`MatchRecord` (`nil` = personal, unchanged). `AppStore` on both targets caches a `clubs` array and exposes `saveClubs` — deliberately local-only (no `CloudSyncManager.pushToCloud()` call), since a real shared club only exists once 5c wires a `CKShare` zone; syncing a throwaway local list now would be replaced work. No UI yet (that's 5d).
- **5c — `CKShare` zone-sharing mechanics** ✅ done: `CloudKitSyncManager` (both targets) now runs two `CKSyncEngine` instances — the existing private-DB engine for personal data, plus a shared-DB engine for club zones. `Club` gained `ownerRecordName: String?` (nil = locally-owned) so a club's per-club `Club-<uuid>` zone can be addressed on either the owner's private DB or a member's shared DB. `fetchOrCreateShare(for:)` creates/fetches the zone-wide `CKShare`; `acceptShare(metadata:)` accepts an invitation and triggers a shared-DB fetch. Each target gained an app/scene delegate (`AppDelegate`+`SceneDelegate` on iOS, `WatchAppDelegate` on watchOS) purely to catch the OS's share-acceptance callback and forward it to `acceptShare`. No UI yet to actually create/send an invite — that's 5e; 5d (club management UI) can land independently.
- **5d — Club management UI** ✅ done (#148): create/rename/leave, member list, per-club roster on both targets — pure UI over the existing `AppStore.saveClubs`/`saveRoster`/`saveHistory`, no `CloudKitSyncManager` changes needed (delete and leave are the same local operation, since `enqueueClubChanges` already branches on `Club.ownerRecordName`). Member list reads live from `CloudKitSyncManager.fetchOrCreateShare(for:)`'s `CKShare.participants` when `cloudKitSyncEnabled`, falling back to just "You" when sync is off — never blocks on CloudKit (local-first invariant). Deleting/leaving a club clears `clubId` back to `nil` on its players/matches rather than deleting them. `PlayerEditView` gained an optional club `Picker` (shown only when a non-empty `clubs` list is passed in) — the only mechanism to assign a player to a club. No match-recording (`MatchRecord.clubId`) tagging UI yet — that's a later slice.
- **5e — Invite UI** ✅ done ([#155](https://github.com/rinaba501/badminton-score-tracker/issues/155)): iOS-only (no watchOS equivalent — `UICloudSharingController` is UIKit-only). `ClubDetailView`'s Members section gets an owner-only "Invite…" button (shown only when `cloudKitSyncEnabled`) that calls `fetchOrCreateShare(for:)` and presents the resulting `CKShare` via `CloudSharingView`, a new `UIViewControllerRepresentable` wrapper. The accept-flow half already worked end-to-end before this slice — `acceptShare(metadata:)` → `sharedSyncEngine.fetchChanges()` → `applyFetched(_:)` → `AppStore.applyRemoteUpsert` already surfaced an accepted club's participants; 5e only had to build the send side.
- **5f** — Multi-club polish: club switcher in History/Stats.

5b–5f get concrete GitHub issues once the prior slice lands, same convention as #133–#139. Every slice touching CloudKit sharing carries its own honestly-stated manual test gate — `CKShare` acceptance needs two different Apple ID accounts, strictly more test burden than Phase 4's still-pending two-device (same-account) test.

**Governing invariant for Phase 5 and all social features (user directive, 2026-07-06): local-first, account-optional.** The app must always stay fully usable by one person scoring everyone with zero accounts — the solo-scorekeeper flow (roster of local players + ad-hoc guests, no sign-in, no network) is the default and never regresses or hides behind account/club flows. Everything below is an *additive opt-in* that must degrade to invisible for a solo user (no sign-in prompts, no "invite friends" empty states). This rests on the **player vs. participant** distinction: a `Player` is a local roster entry (name/avatar/UUID, no Apple ID — already true today); a "participant" is a real Apple ID in a shared club. A roster player MAY optionally be linked to a participant, but never has to be — unlinked names still appear in every stat/standing. Personal history (`clubId == nil`) always coexists with any club data. The New Match flow must never require an account or club.

**Social-features backlog (all wanted; each an opt-in per the invariant above; scope/sequence once clubs exist):**
- *Match confirmation* — per-club admin toggle, **default OFF**: a recorded match counts immediately (today's behavior), matching a private club's trust level (people you already know) rather than the stricter anti-cheat need of a public leaderboard. When an admin turns it on, an unconfirmed match doesn't count toward standings until the opponent confirms. Distinct from a lightweight, always-on *awareness* notification ("Ken logged a match: you lost 15–21") — that's just a courtesy nudge, not a gate, and doesn't need the toggle. Invisible for solo matches either way. Reuses the same confirm/accept primitive a future public leaderboard would need for anti-cheat, so still worth designing into the club model from the start even though it defaults off.
- *Club standings / leaderboard, head-to-head, rivalries* — `StatsCalculator` math over the club's shared history instead of personal history; near-free once clubs exist.
- *Activity feed* — chronological view of recent club results with a per-club unread marker.
- *Challenges* — "want to play?" ping between members (small new pending/accepted CKRecord type in the shared zone).
- *Seasons* — time-boxed standings resets (date-filter over history + a stored boundary).
- *Reactions / comments on a match* — 👍/🔥 or a one-line note (CKRecord children of a match).
- *Notifications* — for async interactions (confirmation, challenges); needs `aps-environment` (deliberately left off in Phase 4) — add only once there's async interaction worth announcing.
- *Ambitious / own initiatives (like the public leaderboard):* live spectating, tournament brackets.

### Phase 6 — iOS companion app (#41)

A new iOS target consuming `BadmintonCore`: history/stats/roster with `NavigationStack`, share-sheet export (#13), and — as a follow-up after the browse screens — live scoring on the phone (tap-only; no Digital Crown or HealthKit). **Shipped** across PRs #133–#139 (see the issue map and [docs/ios-companion-app-plan.md](docs/ios-companion-app-plan.md)). Still open for a later pass: an iOS widget and the account/sharing management UI from Phase 5. Two-device sync verification remains deferred on hardware.

### Future initiative — public/global leaderboard (not yet scoped)

Explicitly out of Phase 5's scope (confirmed with the user 2026-07-06), but wanted eventually: a public, discoverable leaderboard beyond private clubs. Would use CloudKit's *public* database — a separate mechanism, schema, and access model from the `CKShare` private-sharing path Phase 5 builds — so it doesn't block or get blocked by Phase 5. Real added cost vs. private sharing: Apple's App Store Guideline 1.2 requires report/block/moderation tooling for any public user-generated content before Apple will approve it (not optional polish), plus anti-cheat/score-validation work since a public leaderboard invites manipulation in a way a trusted private club doesn't. CloudKit's own cost stays low (pricing scales with app users and is free at this app's likely volume) — the cost is almost entirely the moderation + integrity engineering. File a concrete issue and design discussion when ready to scope it; no code exists for this yet.

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
| 5 — Cross-person sharing | design in [#93](https://github.com/rinaba501/badminton-score-tracker/issues/93); enables [#13](https://github.com/rinaba501/badminton-score-tracker/issues/13) | In progress — 5a (orientation-neutral MatchRecord), 5b (Club/clubId data model), 5c (CKShare zone-sharing mechanics), 5d (club management UI, [#148](https://github.com/rinaba501/badminton-score-tracker/issues/148)), and 5e (invite UI, [#155](https://github.com/rinaba501/badminton-score-tracker/issues/155)) done; 5f (multi-club polish) not yet started |
| 6 — iOS companion app | [#41](https://github.com/rinaba501/badminton-score-tracker/issues/41) | Feature-complete — PR1 (#133 shell+CI), PR2 (#135 iCloud KV sync), PR3 (#136 History+Stats), PR4 (#137 Roster), PR5 (#138 Share, closed #13), PR6 (#139 live scoring on iPhone) — see [docs/ios-companion-app-plan.md](docs/ios-companion-app-plan.md). Two-device sync tests still pending (deferred, no hardware). Watch app is no longer WKWatchOnly as of PR1 — archive an earlier commit for a watch-only App Store submission |
| Guardrails | [#110](https://github.com/rinaba501/badminton-score-tracker/issues/110) | Closed by PR [#116](https://github.com/rinaba501/badminton-score-tracker/pull/116) |

Independent feature work (e.g. doubles support, [#8](https://github.com/rinaba501/badminton-score-tracker/issues/8)) is unaffected by this sequencing, though doubles will be cheaper after Phase 3's orientation-neutral groundwork.

## Maintaining this document

Update the Issue map when a phase's issue closes, and revisit the phase ordering if a decision changes (e.g. abandoning CloudKit for a custom backend). Per the repo convention, structural changes made while executing a phase must update CLAUDE.md in the same PR.
