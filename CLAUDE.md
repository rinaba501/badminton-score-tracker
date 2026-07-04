# Badminton Score Tracker

A **watchOS app** built with SwiftUI for tracking badminton match scores in real time.

> **For the full feature specification, see [SPEC.md](SPEC.md).**
> CLAUDE.md covers project structure, architecture, and working conventions.
> SPEC.md covers what the app does and why.

---

## Tech Stack
- **Platform:** watchOS (Apple Watch)
- **Language:** Swift
- **UI Framework:** SwiftUI
- **Shared code:** local Swift package `BadmintonCore` (models, persistence codecs, stats derivations, storage-key constants). Package sources are Foundation-only — no SwiftUI/WatchKit — so a future iOS target (and `swift test` on macOS) can consume them unchanged
- **Audio:** `AVAudioEngine` + `AVAudioPlayerNode` for programmatic sine-wave tones; `AVSpeechSynthesizer` for score announcements — no audio files required
- **Persistence:** `@AppStorage` (UserDefaults) with JSON-encoded structs (`[Player]`, `[MatchRecord]`)
- **Sync:** `NSUbiquitousKeyValueStore` (iCloud key-value store) — mirrors `playerRoster`, `matchHistory`, and settings across devices; requires `com.apple.developer.ubiquity-kvstore-identifier` entitlement
- **Health:** `HealthKit` — `HKWorkoutSession` + `HKLiveWorkoutBuilder` for badminton workout tracking; requires HealthKit capability in Xcode + `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` in Info.plist

---

## Project Structure

```
BadmintonCore/                 — local Swift package; the platform-free core (linked into the Watch App via the Xcode project's package reference)
  Package.swift               — swift-tools 5.9; platforms watchOS 11 / iOS 17 / macOS 14; no dependencies
  Sources/BadmintonCore/
    MatchModel.swift          — BadmintonMatch, GameScore, MatchRecord, Side (all public)
    PersistenceStore.swift    — centralized JSON encode/decode for [Player] and [MatchRecord]; versioned envelope + migration hook
    Player.swift              — Player model + sentinel names + SortOrder + sortedPlayers (no SwiftUI; presentation lives in the app's PlayerAvatar.swift)
    StatsCalculator.swift     — pure stats/history derivations extracted from StatsView/HistoryView/PreMatchView
    AppStorageKeys.swift      — the single source of truth for every UserDefaults/@AppStorage key string
    ScoreCallFormatter.swift  — pure locale-aware score announcement formatting (en/ja/zh); injectable `strings` closure for testing without Bundle.main
  Tests/BadmintonCoreTests/   — all core unit tests (Swift Testing); run with `swift test --package-path BadmintonCore`

badminton score tracker Watch App/
  ContentView.swift          — root view + state-driven navigation only
  MenuView.swift             — main menu
  PreMatchView.swift         — two-step player selection before a match
  GameView.swift             — live scoring screen (layout only): OnboardingView, GamesWonHeader, ScoreView, MatchOverOverlay; delegates all logic to GameViewModel
  GameViewModel.swift        — @MainActor ObservableObject; owns all GameView business logic: scoring, undo, time mode, haptics coordination, match persistence, spoken announcements
  HapticsProvider.swift      — HapticsProvider protocol + WatchHapticsProvider (wraps WKInterfaceDevice) + NoOpHapticsProvider (for tests)
  SettingsView.swift         — match format, audio, theme, timer, roster management
  HistoryView.swift          — saved match list + filters; also MatchHistoryRow
  StatsView.swift            — per-player stats + head-to-head; also StatRow (delegates the math to StatsCalculator)
  PlayerEditView.swift       — single-player editor sheet (name, color, avatar, icon)
  PlayerAvatar.swift         — SwiftUI presentation of Player: avatarColors/avatarImageNames/sportIcons + AvatarView
  AudioFeedback.swift        — ScoreAnnouncer (AVSpeechSynthesizer) + SoundPlayer (AVAudioEngine)
  CourtTheme.swift           — CourtTheme enum
  AppStore.swift             — @MainActor ObservableObject singleton; caches decoded [Player] and [MatchRecord]; all views read from here instead of decoding JSON on every render
  WorkoutManager.swift       — HKWorkoutSession lifecycle; started on match begin, ended on save or discard
  CloudSyncManager.swift     — NSUbiquitousKeyValueStore sync; pushes on data change, pulls on launch and external update. Match history is merged by record id (union via PersistenceStore.mergeHistory) for appends/edits, not last-write-wins; a deletion (detected via PersistenceStore.isHistoryShrink) instead pushes as an authoritative overwrite, since merging would resurrect what was just deleted. Other keys are last-write-wins
  badminton_score_trackerApp.swift — app entry point; starts CloudSyncManager, handles badminton://newmatch deep link
  badminton_score_tracker_Watch_App.entitlements — iCloud KV store entitlement
  Assets.xcassets/           — app icon, racket animation asset, 15 avatar images
  *.lproj/Localizable.strings — en, ja, zh-Hans, ko, id, hi

badminton score tracker Watch AppTests/
  badminton_score_tracker_Watch_AppTests.swift — GameViewModel tests (compile in CI via build-for-testing; run locally against a watchOS simulator). Core logic tests live in the package.

badminton score tracker Complication/
  BadmintonComplication.swift — WidgetKit extension; circular, corner, inline, rectangular families
```

### Key Models

**`BadmintonCore` package — `MatchModel.swift`**
- `Side` — `.me` / `.opponent`
- `GameScore` — `my: Int`, `opponent: Int` for one completed game
- `BadmintonMatch` — pure scoring engine; no UI, no timers. Tracks scores, games won, serve side, win conditions
- `MatchRecord` — persisted match result; stores player names + optional `UUID` player IDs for name-change tracking
- All package API the app consumes is `public` (explicit inits included) — a new member that stays `internal` will fail the Watch App build

**`BadmintonCore` package — `Player.swift`**
- `Player` — `id: UUID`, `name`, `colorIndex`, `iconName?`; stored as JSON in `@AppStorage("playerRoster")`
- `Player.SortOrder` + `Player.sortedPlayers(_:order:history:)` — roster sorting (created/name/nameDescending/mostPlayed/recentlyUsed)
- `Player.defaultMyName` / `.guestNearLabel` / `.guestFarLabel` — localized *display* strings via `NSLocalizedString`, shown to the user (button labels, tiles). `Player.guestNearToken` / `.guestFarToken` are fixed, non-localized literals — what's actually *stored* in `matchMyName`/`matchOpponentName` and `MatchRecord.myName`/`opponentName` for a guest selection, so guest identity doesn't depend on which locale was active when the record was saved or is later read. `Player.isGuestName(_:)` recognizes both the tokens and (for pre-#108 records) the legacy localized labels under the current locale. `Player.displayName(for:)` maps a stored value back to display text (a token → its label; anything else passes through) — every screen that renders a stored name/token wraps it with this before putting it in a `Text` or speaking it. The strings tables stay in the app bundle (`Bundle.main`); under `swift test` the label getters resolve to their raw keys, which remain distinct/non-empty — the identity checks don't care
- `PersistenceStore` — namespace of static `encodeRoster`/`decodeRoster` (`[Player]`) and `encodeHistory`/`decodeHistory` (`[MatchRecord]`) helpers, plus `mergeHistory`/`isHistoryShrink` for iCloud reconciliation. All view code goes through these instead of calling `JSONEncoder`/`JSONDecoder` inline. On-disk data is a versioned envelope (`{"schemaVersion": N, "records": [...]}`, current version 1); the legacy unversioned bare-array format (implicit version 0) still decodes. Decoding is per-record tolerant — a single corrupt record is dropped, not fatal to the rest of the list — and only returns `[]` when the outer structure itself is unparsable. `migratedRosterData(from:)`/`migratedHistoryData(from:)` return upgraded `Data` (or `nil` if no migration is needed); `AppStore.init` calls these via `runMigrations()` before the first decode — the designated place for future schema changes (e.g. #108's player-identity backfill)
- `StatsCalculator` — pure static derivations over `[MatchRecord]`: participants, per-player history, win rate/streak/averages, head-to-head, history filtering, duration formatting. It deliberately carries **two** participants functions (`allPlayers` hoists the main player and keeps empty names — StatsView semantics; `participants` drops empties — HistoryView semantics) and **two** head-to-head functions (`headToHead` returns (0,0) on no data — StatsView; `headToHeadIfAny` returns nil and counts wins from the near side only — PreMatchView). They preserve each screen's original behavior; don't unify them without a product decision
- `AppStorageKeys` — every persisted key string as a constant. New `@AppStorage`/UserDefaults keys must be added here, never inline as string literals. Typed defaults stay at the `@AppStorage` declaration sites (some reference app-only types like `CourtTheme`)
- `ScoreCallFormatter` — pure enum; `format(match:myName:opponentName:locale:strings:)` returns a spoken score announcement string. `strings` defaults to `NSLocalizedString` (app runtime); tests inject explicit format strings so coverage doesn't require `Bundle.main`. Handles English (love-score), Japanese (katakana), and Chinese (numeric integers)

**UI layer** (split by screen — one view file each; see Project Structure above)
- `ContentView.swift` — root view; owns only the `AppView` routing enum
- `AvatarView` (`PlayerAvatar.swift`) — renders asset image, SF Symbol, or initials depending on `iconName`; the same file holds `Player.avatarColors`/`avatarImageNames`/`sportIcons`/`avatarColor` as an app-side extension of the package's `Player`
- `ScoreAnnouncer` (`AudioFeedback.swift`) — wraps `AVSpeechSynthesizer`
- `SoundPlayer` (`AudioFeedback.swift`) — wraps `AVAudioEngine` for programmatic tones
- Screens live in their own files: `MenuView`, `PreMatchView`, `GameView`, `SettingsView`, `HistoryView`, `StatsView`, `PlayerEditView`
- `GameView` is layout-only — all match state and actions delegate to `GameViewModel`

**`AppStore.swift`** (app target)
- `AppStore` — `@MainActor` singleton `ObservableObject`. Holds `@Published private(set) var roster: [Player]` and `history: [MatchRecord]`. `init` calls `runMigrations()` (upgrades on-disk data via `PersistenceStore.migratedRosterData(from:)`/`migratedHistoryData(from:)` before the first decode) then decodes once; decodes again when iCloud sync pulls external data (`reloadFromStorage()`). Write through `saveRoster(_:)`, `saveHistory(_:)`, or `clearHistory()` — each writes to `UserDefaults` directly, updates the published property, and calls `CloudSyncManager.shared.pushToCloud()`. Injected via `.environmentObject(AppStore.shared)` from the app entry point; all screens receive it via `@EnvironmentObject`. `localPlayerId: UUID` lazily generates and persists a stable identity for the local user on first access — "Me" is deliberately never added to `roster` (see `Player.shouldBeStoredAsSavedPlayer`), so this is the only stable ID `GameViewModel.saveMatch()` can stamp on a near-side "Me" record.

**`GameViewModel.swift`** (app target)
- `GameViewModel` — `@MainActor final class ObservableObject`. Owns all live-game business logic extracted from `GameView`: `BadmintonMatch` state, undo stack, time-mode/sudden-death, haptics (via `HapticsProvider` protocol), sound, spoken announcements (via `ScoreCallFormatter`), and match persistence. `GameView` creates one via `@StateObject` and delegates every action here. Match config is read from `@AppStorage` directly in the VM (pointsToWin, gamesInMatch, timeModeEnabled, timeLimitMinutes, announceScore, enableSounds). `enableCrownScoring` and `courtTheme` stay in the view (input binding and display respectively).
- `HapticsProvider` — protocol with `play(_ type: WKHapticType)`. `WatchHapticsProvider` (production) wraps `WKInterfaceDevice.current().play(_:)`. `NoOpHapticsProvider` (tests) is a no-op struct. All 13 former inline `WKInterfaceDevice` calls in `GameView` are now routed through this protocol.

### Navigation
State-driven via `ContentView.AppView` enum (`.menu`, `.preMatch`, `.game`, `.settings`, `.history`, `.stats`) — no `NavigationLink` at the top level.

---

## AppStorage Keys

All key strings are constants in `BadmintonCore.AppStorageKeys` — declare `@AppStorage(AppStorageKeys.x)`, never an inline literal, and add new keys there first.

| Key | Type | Description |
|-----|------|-------------|
| `myName` | `String` | Display name for the local player |
| `localPlayerId` | `String` (UUID) | Stable identity for the local player, independent of display name and the roster; generated once by `AppStore.localPlayerId`, syncs via iCloud like `myName` |
| `matchMyName` | `String` | Near-side player for the current match — a real name, "Me" (empty = default), or `Player.guestNearToken` |
| `matchOpponentName` | `String` | Far-side player for the current match — a real name or `Player.guestFarToken` |
| `playerRoster` | `Data` | JSON-encoded `[Player]` |
| `matchHistory` | `Data` | JSON-encoded `[MatchRecord]` |
| `playerSortOrder` | `String` | `Player.SortOrder` raw value (default `.name`) |
| `pointsToWin` | `Int` | Default 21 |
| `gamesInMatch` | `Int` | Default 3 |
| `courtTheme` | `String` | `CourtTheme` raw value |
| `gameMode` | `String` | `SettingsView.GameMode` raw value (default singles) |
| `announceScore` | `Bool` | Score announcement toggle |
| `enableSounds` | `Bool` | Sound effects toggle |
| `enableCrownScoring` | `Bool` | Digital Crown scoring toggle (default true) |
| `timeModeEnabled` | `Bool` | Match Timer mode toggle |
| `timeLimitMinutes` | `Int` | Default 10 |

---

## Git Workflow — MUST FOLLOW

- **Never commit directly to `main`** — all changes go through a PR
- Create a `feature/...` or `fix/...` branch for every change
- Every PR that adds or changes a feature **must also update `SPEC.md`**
- Every PR that changes project structure, architecture, models, or conventions **must also update `CLAUDE.md`**
- After merging a PR, always clean up without being asked:
  ```
  gh pr merge <number> --merge --delete-branch
  git checkout main && git pull
  git remote prune origin
  ```
- Do not leave stale local or remote branches — one branch per PR, deleted on merge

### Continuous Integration
`.github/workflows/ci.yml` runs on every PR (and pushes to `main`). The five jobs have no `needs:` dependency, so they run in parallel:
- **SwiftLint** — `swiftlint lint` against the config in `.swiftlint.yml` (non-strict: style issues are warnings/annotations; only error-severity rules fail). Observed runtime: **~10-20s**.
- **BadmintonCore Tests** — `swift test --package-path BadmintonCore --enable-code-coverage` on macOS (no simulator). All core unit tests live here; runs in well under a minute. A follow-up step runs `xcrun llvm-cov report` against the resulting `.profdata` and prints a per-file coverage table straight into the job log (no external coverage service).
- **Localization Sync** — extracts the key set from each of the 6 `.lproj/Localizable.strings` files and fails, naming the missing locale/key, if any locale's keys don't match the union. Pure bash/grep, no Xcode toolchain needed. Runtime: seconds.
- **Watch App Build** — `xcodebuild build-for-testing` of the Watch App scheme against `generic/platform=watchOS Simulator` (no concrete simulator device needed — runner images don't reliably ship watchOS simulators). Compiles the app **and both test bundles** without executing them, so it's the integration gate for project-file, linking, and app-code errors, and app-layer test code can't silently rot. Observed runtime: **~1.5-4 min** — this is the long pole. Note: app-target tests are compiled but not *run* in CI (running needs a concrete simulator); the core logic that needs behavioral verification belongs in the package where `swift test` runs it.
- **Complication Build** — `xcodebuild build` of the `badminton score tracker ComplicationExtension` scheme (shared scheme checked into `xcshareddata/xcschemes/`) against the same generic watchOS Simulator destination. Uses plain `build`, not `build-for-testing` — the WidgetKit extension has no test target. Catches breakage in `BadmintonComplication.swift` that the Watch App Build job doesn't compile.

All targets' `WATCHOS_DEPLOYMENT_TARGET` are aligned at **11.4** (the Complication extension previously drifted to 26.5 with no `@available` usage requiring it — an unaligned Xcode-template default, not an intentional API dependency).

A PR is checkable within **~4 minutes** of pushing. If you're polling/scheduling a check-in on a PR (e.g. an agent session without webhook access to CI success events), don't default to a long cadence like 20 minutes — check back in ~3-5 minutes first, and only back off if the run is still in progress.

Run SwiftLint locally before pushing with `swiftlint` (install via `brew install swiftlint`), and run the core tests locally with `swift test --package-path BadmintonCore` (seconds on any Mac). Keep the build green — fix or intentionally silence lint findings rather than letting warnings accumulate. When possible, also build locally (`xcodebuild build`) before pushing SwiftUI changes: CI's watchOS build is the safety net, but it's a slow feedback loop, and a local compile catches type-check timeouts and errors in seconds.

### Reviewing risky changes
CI (lint + unit tests) proves the code compiles and the logic it covers is correct — it does not catch architectural/interaction bugs. The worst bug found in this codebase so far wasn't in any single PR: it was two independently-correct changes to `CloudSyncManager`/`AppStore` (the id-based history merge and the clear-history feature) combining to silently undo "Clear History." CI was green on both. For anything beyond mechanical changes (docs, string localization, dead-code removal):
- Use plan mode before implementing, especially anything touching `CloudSyncManager`/`AppStore` — that's where both real bugs in this codebase have lived. A wrong plan costs one sentence to fix; a wrong diff already cost the rewrite.
- Run a `/code-review` pass before merging non-trivial PRs. CI-green is evidence the mechanics work, not that the change is correct.

---

## Keeping the Docs Up-to-Date

When making any change, ask:
- Does this add, remove, or change a user-facing feature? → Update **`SPEC.md`**
- Does this add a new file, model, AppStorage key, or architectural pattern? → Update **`CLAUDE.md`**
- Does this close a GitHub issue? → Move it from Open to Closed in **`SPEC.md`** with the PR number
- Does this change how the app is built/run, or add a top-level doc/workflow file? → Update **`README.md`**

Both `CLAUDE.md` and `SPEC.md` should always reflect the current state of the codebase. A future session reading only these two files should have a complete picture of the project. `README.md` is the human-facing entry point and should stay short — link out to `SPEC.md`/`CLAUDE.md` for detail rather than duplicating it.

### Other repo docs
- `README.md` — human-facing overview: what the app is, screenshots, build instructions. Rarely changes.
- `ROADMAP.md` — long-term architecture roadmap: phased plan for the shared `BadmintonCore` package, schema versioning/identity groundwork, CloudKit sync, cross-person sharing, and the iOS companion app, with a phase→issue map. Consult it before starting architectural work; update its Issue map when a phase's issue closes.
- `.github/PULL_REQUEST_TEMPLATE.md` / `.github/ISSUE_TEMPLATE/report.md` — the PR/issue shape used throughout this project's history (Summary/Changes/Verification; Problem/Proposed approach/Acceptance criteria). Follow them when opening PRs/issues even if a tool doesn't auto-populate them.
- `docs/` — `privacy-policy.md` and `app-store-metadata.md` (App Store submission content) and `index.md` (the GitHub Pages host for the privacy policy link). Not living specs; update only when their specific subject changes.

---

## Conventions
- Use SwiftUI for all UI — no UIKit / WKInterfaceController
- SwiftUI view complexity: keep `body` small. Pull sub-sections into computed `some View` properties, and hoist non-trivial values — nested ternaries, `String(format:)` around string interpolation — out of result builders into explicitly-typed helpers (`Color`, `CGFloat`, `String`). The Swift type-checker times out on large view expressions (*"unable to type-check this expression in reasonable time"*), and each computed property/function is a separate, cheaper type-check unit. `ScoreView` and `GameView` follow this pattern. The Watch App target's Debug config sets `OTHER_SWIFT_FLAGS = -Xfrontend -warn-long-expression-type-checking=100`, so a slow expression shows up as a build warning before it becomes a hard timeout — don't ignore that warning.
- Keep watchOS constraints in mind: small screen (~44–46mm), large tap targets, no keyboard by default (scribble/dictation only)
- `BadmintonMatch` must remain a pure value type — no UI, no timers, no side effects
- Platform-free logic (models, persistence codecs, derivations over history) lives in the `BadmintonCore` package, which must never import SwiftUI/WatchKit. Package API the app uses must be `public`. UI presentation of package models (colors, icons, views) goes in app-side extensions (see `PlayerAvatar.swift`)
- Audio: tones via `AVAudioEngine`, speech via `AVSpeechSynthesizer` with `.duckOthers` — delay speech by tone duration to avoid interference
- Localization: all user-facing strings go in `Localizable.strings` for all 6 languages (en, ja, zh-Hans, ko, id, hi)
- Sentinel identity (guest selection, "Me") must not be hardcoded string literals — read from `Player.defaultMyName` / `.guestNearToken` / `.guestFarToken` / `.isGuestName(_:)` for anything that's *stored or compared* (persisted names, identity checks), and from `Player.guestNearLabel` / `.guestFarLabel` / `.displayName(for:)` only for what's *shown or spoken* to the user. Storing identity as a non-localized token and rendering it as a localized label at the last possible moment is what keeps guest detection working regardless of which locale was active when the record was saved vs. when it's read
- Accessibility: custom/gesture-based controls (e.g. the score tiles) need `accessibilityLabel`/`accessibilityHint` and the right traits; decorative imagery gets `accessibilityHidden(true)`. Accessibility strings are localized like any other (`a11y.*` keys)
- Persistence: read/write `[Player]` and `[MatchRecord]` through `PersistenceStore` — never call `JSONEncoder`/`JSONDecoder` inline in views

---

## GitHub Repo
`rinaba501/badminton-score-tracker`
Issues: https://github.com/rinaba501/badminton-score-tracker/issues
