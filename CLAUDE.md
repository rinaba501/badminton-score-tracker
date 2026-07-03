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
    PersistenceStore.swift    — centralized JSON encode/decode for [Player] and [MatchRecord]
    Player.swift              — Player model + sentinel names + SortOrder + sortedPlayers (no SwiftUI; presentation lives in the app's PlayerAvatar.swift)
    StatsCalculator.swift     — pure stats/history derivations extracted from StatsView/HistoryView/PreMatchView
    AppStorageKeys.swift      — the single source of truth for every UserDefaults/@AppStorage key string
  Tests/BadmintonCoreTests/   — all core unit tests (Swift Testing); run with `swift test --package-path BadmintonCore`

badminton score tracker Watch App/
  ContentView.swift          — root view + state-driven navigation only
  MenuView.swift             — main menu
  PreMatchView.swift         — two-step player selection before a match
  GameView.swift             — live scoring screen; also OnboardingView, GamesWonHeader, ScoreView, MatchOverOverlay
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
  badminton_score_tracker_Watch_AppTests.swift — app-layer placeholder only; the core tests live in the package (future home of e.g. the issue #96 view-model tests)

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
- `Player.SortOrder` + `Player.sortedPlayers(_:order:history:)` — roster sorting (created/name/mostPlayed/recentlyUsed)
- `Player.defaultMyName` / `.guestNearLabel` / `.guestFarLabel` / `.isGuestName(_:)` — the single source of truth for the "me"/guest sentinel display names, localized via `NSLocalizedString`. Every screen that offers or recognizes these labels reads from here, so a guest selection is always recognized as a guest (and never persisted to the roster) regardless of locale. The strings tables stay in the app bundle (`Bundle.main`); under `swift test` these resolve to their raw keys, which remain distinct/non-empty — the identity checks don't care
- `PersistenceStore` — namespace of static `encodeRoster`/`decodeRoster` (`[Player]`) and `encodeHistory`/`decodeHistory` (`[MatchRecord]`) helpers, plus `mergeHistory`/`isHistoryShrink` for iCloud reconciliation. All view code goes through these instead of calling `JSONEncoder`/`JSONDecoder` inline. Decode returns `[]` on missing/corrupt data
- `StatsCalculator` — pure static derivations over `[MatchRecord]`: participants, per-player history, win rate/streak/averages, head-to-head, history filtering, duration formatting. It deliberately carries **two** participants functions (`allPlayers` hoists the main player and keeps empty names — StatsView semantics; `participants` drops empties — HistoryView semantics) and **two** head-to-head functions (`headToHead` returns (0,0) on no data — StatsView; `headToHeadIfAny` returns nil and counts wins from the near side only — PreMatchView). They preserve each screen's original behavior; don't unify them without a product decision
- `AppStorageKeys` — every persisted key string as a constant. New `@AppStorage`/UserDefaults keys must be added here, never inline as string literals. Typed defaults stay at the `@AppStorage` declaration sites (some reference app-only types like `CourtTheme`)

**UI layer** (split by screen — one view file each; see Project Structure above)
- `ContentView.swift` — root view; owns only the `AppView` routing enum
- `AvatarView` (`PlayerAvatar.swift`) — renders asset image, SF Symbol, or initials depending on `iconName`; the same file holds `Player.avatarColors`/`avatarImageNames`/`sportIcons`/`avatarColor` as an app-side extension of the package's `Player`
- `ScoreAnnouncer` (`AudioFeedback.swift`) — wraps `AVSpeechSynthesizer`
- `SoundPlayer` (`AudioFeedback.swift`) — wraps `AVAudioEngine` for programmatic tones
- Screens live in their own files: `MenuView`, `PreMatchView`, `GameView`, `SettingsView`, `HistoryView`, `StatsView`, `PlayerEditView`

**`AppStore.swift`** (app target)
- `AppStore` — `@MainActor` singleton `ObservableObject`. Holds `@Published private(set) var roster: [Player]` and `history: [MatchRecord]`. Decodes once on init and again when iCloud sync pulls external data (`reloadFromStorage()`). Write through `saveRoster(_:)`, `saveHistory(_:)`, or `clearHistory()` — each writes to `UserDefaults` directly, updates the published property, and calls `CloudSyncManager.shared.pushToCloud()`. Injected via `.environmentObject(AppStore.shared)` from the app entry point; all screens receive it via `@EnvironmentObject`.

### Navigation
State-driven via `ContentView.AppView` enum (`.menu`, `.preMatch`, `.game`, `.settings`, `.history`, `.stats`) — no `NavigationLink` at the top level.

---

## AppStorage Keys

All key strings are constants in `BadmintonCore.AppStorageKeys` — declare `@AppStorage(AppStorageKeys.x)`, never an inline literal, and add new keys there first.

| Key | Type | Description |
|-----|------|-------------|
| `myName` | `String` | Display name for the local player |
| `matchMyName` | `String` | Near-side player for the current match |
| `matchOpponentName` | `String` | Far-side player for the current match |
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
`.github/workflows/ci.yml` runs on every PR (and pushes to `main`). The three jobs have no `needs:` dependency, so they run in parallel:
- **SwiftLint** — `swiftlint lint` against the config in `.swiftlint.yml` (non-strict: style issues are warnings/annotations; only error-severity rules fail). Observed runtime: **~10-20s**.
- **BadmintonCore Tests** — `swift test --package-path BadmintonCore` on macOS (no simulator). All core unit tests live here; runs in well under a minute.
- **Watch App Build** — `xcodebuild build` of the Watch App scheme against `generic/platform=watchOS Simulator` (no concrete simulator device needed — runner images don't reliably ship watchOS simulators). This is the integration gate that catches project-file, linking, and app-code errors. Observed runtime: **~2.5-4 min** — this is the long pole. (The Watch AppTests bundle still exists for future app-layer tests but CI doesn't run it — it holds only a placeholder.)

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
- Sentinel display names (the local player's default name, guest labels) must not be hardcoded string literals — read them from `Player.defaultMyName` / `.guestNearLabel` / `.guestFarLabel` / `.isGuestName(_:)`, since these strings are both displayed *and* used for identity checks (e.g. "don't save a guest to the roster"). A hardcoded literal in one screen and a localized one in another would break that check across locales
- Accessibility: custom/gesture-based controls (e.g. the score tiles) need `accessibilityLabel`/`accessibilityHint` and the right traits; decorative imagery gets `accessibilityHidden(true)`. Accessibility strings are localized like any other (`a11y.*` keys)
- Persistence: read/write `[Player]` and `[MatchRecord]` through `PersistenceStore` — never call `JSONEncoder`/`JSONDecoder` inline in views

---

## GitHub Repo
`rinaba501/badminton-score-tracker`
Issues: https://github.com/rinaba501/badminton-score-tracker/issues
