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

Replace the single-blob KV-store sync with the CloudKit private database: one `CKRecord` per match and per player, real deletion propagation (retiring the `isHistoryShrink` overwrite heuristic), push-based change notifications, and no practical size ceiling. Scalar settings can stay on the KV store. Requires the CloudKit container entitlement (today the app has only the KV-store entitlement).

*Why CloudKit (decision):* free, no server to run, Apple ID is the user identity, native offline/push sync — and it is the only Apple-stack path to sharing between different people (`CKShare` operates on CloudKit records). The trade-off — sharing stays Apple-only — is acceptable for a watchOS/iOS product. Per CLAUDE.md, `CloudSyncManager`/`AppStore` is the highest-risk area of this codebase: this phase needs plan mode, `/code-review`, and a real two-device test pass, not just green CI.

### Phase 5 — Cross-person sharing (via #93; enables #13)

With matches as CloudKit records and identity locale-independent, sharing becomes incremental: a `CKShare` on a match (or a shared "club" zone/roster), Apple ID–backed participants, and a data-model change making `MatchRecord` orientation-neutral (playerA/playerB with a per-viewer perspective mapping, replacing the "me"-centric record). File the concrete implementation issue once Phase 4 lands and the record schema is real; #93 holds the design discussion until then.

### Phase 6 — iOS companion app (#41)

A new iOS target consuming `BadmintonCore`: history/stats/roster-first with `NavigationStack` (the watch stays the scoring device), share-sheet export (#13), an iOS widget, and account/sharing management UI from Phase 5. Feasible any time after Phases 1–2; substantially richer after 4–5.

### Guardrails track (#110) — do anytime

Cheap, independent CI hardening: a localization key-sync check across the 6 locales, code-coverage reporting on the test job, a build job for the Complication target, deployment-target alignment (Complication 26.5 vs app 11.4), and eventually a lightweight release process (semver tags + changelog).

---

## Issue map

| Phase | Issue(s) | Status |
|-------|----------|--------|
| 1 — BadmintonCore package | [#106](https://github.com/rinaba501/badminton-score-tracker/issues/106) | Closed by PR [#112](https://github.com/rinaba501/badminton-score-tracker/pull/112) |
| 2 — De-view business logic | [#96](https://github.com/rinaba501/badminton-score-tracker/issues/96) | Closed by PR [#113](https://github.com/rinaba501/badminton-score-tracker/pull/113) |
| 3 — Schema versioning / identity | [#107](https://github.com/rinaba501/badminton-score-tracker/issues/107) closed by PR [#114](https://github.com/rinaba501/badminton-score-tracker/pull/114); [#108](https://github.com/rinaba501/badminton-score-tracker/issues/108) closed by PR [#115](https://github.com/rinaba501/badminton-score-tracker/pull/115) (`MatchRecord.winner` type change deferred — see PR notes); KV quota stopgap: [#87](https://github.com/rinaba501/badminton-score-tracker/issues/87) closed by PR [#117](https://github.com/rinaba501/badminton-score-tracker/pull/117) | Done |
| 4 — CloudKit sync | [#109](https://github.com/rinaba501/badminton-score-tracker/issues/109) | In progress — pure core helpers landed (PR [#129](https://github.com/rinaba501/badminton-score-tracker/pull/129)); inert `CKSyncEngine` path behind `cloudKitSyncEnabled` (default off) landing next. Cutover (CloudKit entitlement + flag-on) gated on a two-device iCloud test — not CI-provable |
| 5 — Cross-person sharing | design in [#93](https://github.com/rinaba501/badminton-score-tracker/issues/93); enables [#13](https://github.com/rinaba501/badminton-score-tracker/issues/13) | Deferred until Phase 4 |
| 6 — iOS companion app | [#41](https://github.com/rinaba501/badminton-score-tracker/issues/41) | In progress — PR1 (target restructure + shell + CI) done; remaining: KV sync layer, History/Stats, Roster, Share (#13), then live scoring. Watch app is no longer WKWatchOnly as of PR1 — archive an earlier commit for a watch-only App Store submission |
| Guardrails | [#110](https://github.com/rinaba501/badminton-score-tracker/issues/110) | Closed by PR [#116](https://github.com/rinaba501/badminton-score-tracker/pull/116) |

Independent feature work (e.g. doubles support, [#8](https://github.com/rinaba501/badminton-score-tracker/issues/8)) is unaffected by this sequencing, though doubles will be cheaper after Phase 3's orientation-neutral groundwork.

## Maintaining this document

Update the Issue map when a phase's issue closes, and revisit the phase ordering if a decision changes (e.g. abandoning CloudKit for a custom backend). Per the repo convention, structural changes made while executing a phase must update CLAUDE.md in the same PR.
