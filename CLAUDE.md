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
- **Audio:** `AVAudioEngine` + `AVAudioPlayerNode` for programmatic sine-wave tones; `AVSpeechSynthesizer` for score announcements — no audio files required
- **Persistence:** `@AppStorage` (UserDefaults) with JSON-encoded structs (`[Player]`, `[MatchRecord]`)
- **Sync:** `NSUbiquitousKeyValueStore` (iCloud key-value store) — mirrors `playerRoster`, `matchHistory`, and settings across devices; requires `com.apple.developer.ubiquity-kvstore-identifier` entitlement
- **Health:** `HealthKit` — `HKWorkoutSession` + `HKLiveWorkoutBuilder` for badminton workout tracking; requires HealthKit capability in Xcode + `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` in Info.plist

---

## Project Structure

```
badminton score tracker Watch App/
  ContentView.swift          — root view + state-driven navigation only
  MenuView.swift             — main menu
  PreMatchView.swift         — two-step player selection before a match
  GameView.swift             — live scoring screen; also OnboardingView, GamesWonHeader, ScoreView, MatchOverOverlay
  SettingsView.swift         — match format, audio, theme, timer, roster management
  HistoryView.swift          — saved match list + filters; also MatchHistoryRow
  StatsView.swift            — per-player stats + head-to-head; also StatRow
  PlayerEditView.swift       — single-player editor sheet (name, color, avatar, icon)
  Player.swift               — Player model + AvatarView
  AudioFeedback.swift        — ScoreAnnouncer (AVSpeechSynthesizer) + SoundPlayer (AVAudioEngine)
  CourtTheme.swift           — CourtTheme enum
  AppStore.swift             — @MainActor ObservableObject singleton; caches decoded [Player] and [MatchRecord]; all views read from here instead of decoding JSON on every render
  PersistenceStore.swift     — centralized JSON encode/decode for [Player] and [MatchRecord]
  MatchModel.swift           — BadmintonMatch, GameScore, MatchRecord, Side
  WorkoutManager.swift       — HKWorkoutSession lifecycle; started on match begin, ended on save or discard
  CloudSyncManager.swift     — NSUbiquitousKeyValueStore sync; pushes on data change, pulls on launch and external update. Match history is merged by record id (union via PersistenceStore.mergeHistory), not last-write-wins; other keys are last-write-wins
  badminton_score_trackerApp.swift — app entry point; starts CloudSyncManager, handles badminton://newmatch deep link
  badminton_score_tracker_Watch_App.entitlements — iCloud KV store entitlement
  Assets.xcassets/           — app icon, racket animation asset, 15 avatar images
  *.lproj/Localizable.strings — en, ja, zh-Hans, ko, id, hi

badminton score tracker Complication/
  BadmintonComplication.swift — WidgetKit extension; circular, corner, inline, rectangular families
```

### Key Models

**`MatchModel.swift`**
- `Side` — `.me` / `.opponent`
- `GameScore` — `my: Int`, `opponent: Int` for one completed game
- `BadmintonMatch` — pure scoring engine; no UI, no timers. Tracks scores, games won, serve side, win conditions
- `MatchRecord` — persisted match result; stores player names + optional `UUID` player IDs for name-change tracking

**UI layer** (split by screen — one view file each; see Project Structure above)
- `ContentView.swift` — root view; owns only the `AppView` routing enum
- `Player` (`Player.swift`) — `id: UUID`, `name`, `colorIndex`, `iconName?`; stored as JSON in `@AppStorage("playerRoster")`
- `AvatarView` (`Player.swift`) — renders asset image, SF Symbol, or initials depending on `iconName`
- `Player.defaultMyName` / `.guestNearLabel` / `.guestFarLabel` / `.isGuestName(_:)` (`Player.swift`) — the single source of truth for the "me"/guest sentinel display names, localized via `NSLocalizedString`. Every screen that offers or recognizes these labels reads from here, so a guest selection is always recognized as a guest (and never persisted to the roster) regardless of locale
- `ScoreAnnouncer` (`AudioFeedback.swift`) — wraps `AVSpeechSynthesizer`
- `SoundPlayer` (`AudioFeedback.swift`) — wraps `AVAudioEngine` for programmatic tones
- Screens live in their own files: `MenuView`, `PreMatchView`, `GameView`, `SettingsView`, `HistoryView`, `StatsView`, `PlayerEditView`

**`AppStore.swift`**
- `AppStore` — `@MainActor` singleton `ObservableObject`. Holds `@Published private(set) var roster: [Player]` and `history: [MatchRecord]`. Decodes once on init and again when iCloud sync pulls external data (`reloadFromStorage()`). Write through `saveRoster(_:)`, `saveHistory(_:)`, or `clearHistory()` — each writes to `UserDefaults` directly, updates the published property, and calls `CloudSyncManager.shared.pushToCloud()`. Injected via `.environmentObject(AppStore.shared)` from the app entry point; all screens receive it via `@EnvironmentObject`.

**`PersistenceStore.swift`**
- `PersistenceStore` — namespace of static `encodeRoster`/`decodeRoster` (`[Player]`) and `encodeHistory`/`decodeHistory` (`[MatchRecord]`) helpers. All view code goes through these instead of calling `JSONEncoder`/`JSONDecoder` inline, so the storage encoding lives in one place. Decode returns `[]` on missing/corrupt data.

### Navigation
State-driven via `ContentView.AppView` enum (`.menu`, `.preMatch`, `.game`, `.settings`, `.history`, `.stats`) — no `NavigationLink` at the top level.

---

## AppStorage Keys

| Key | Type | Description |
|-----|------|-------------|
| `myName` | `String` | Display name for the local player |
| `matchMyName` | `String` | Near-side player for the current match |
| `matchOpponentName` | `String` | Far-side player for the current match |
| `playerRoster` | `Data` | JSON-encoded `[Player]` |
| `matchHistory` | `Data` | JSON-encoded `[MatchRecord]` |
| `pointsToWin` | `Int` | Default 21 |
| `gamesInMatch` | `Int` | Default 3 |
| `courtTheme` | `String` | `CourtTheme` raw value |
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
`.github/workflows/ci.yml` runs on every PR (and pushes to `main`):
- **SwiftLint** — `swiftlint lint` against the config in `.swiftlint.yml` (non-strict: style issues are warnings/annotations; only error-severity rules fail)
- **Unit Tests** — `xcodebuild test` on a watchOS simulator, running the `badminton score tracker Watch AppTests` bundle only (UI tests are skipped in CI)

Run SwiftLint locally before pushing with `swiftlint` (install via `brew install swiftlint`). Keep the build green — fix or intentionally silence lint findings rather than letting warnings accumulate. When possible, also build locally (`xcodebuild build`) before pushing SwiftUI changes: CI's watchOS build is the safety net, but it's a slow feedback loop, and a local compile catches type-check timeouts and errors in seconds.

---

## Keeping the Docs Up-to-Date

When making any change, ask:
- Does this add, remove, or change a user-facing feature? → Update **`SPEC.md`**
- Does this add a new file, model, AppStorage key, or architectural pattern? → Update **`CLAUDE.md`**
- Does this close a GitHub issue? → Move it from Open to Closed in **`SPEC.md`** with the PR number

Both files should always reflect the current state of the codebase. A future session reading only these two files should have a complete picture of the project.

---

## Conventions
- Use SwiftUI for all UI — no UIKit / WKInterfaceController
- SwiftUI view complexity: keep `body` small. Pull sub-sections into computed `some View` properties, and hoist non-trivial values — nested ternaries, `String(format:)` around string interpolation — out of result builders into explicitly-typed helpers (`Color`, `CGFloat`, `String`). The Swift type-checker times out on large view expressions (*"unable to type-check this expression in reasonable time"*), and each computed property/function is a separate, cheaper type-check unit. `ScoreView` and `GameView` follow this pattern.
- Keep watchOS constraints in mind: small screen (~44–46mm), large tap targets, no keyboard by default (scribble/dictation only)
- `BadmintonMatch` must remain a pure value type — no UI, no timers, no side effects
- Audio: tones via `AVAudioEngine`, speech via `AVSpeechSynthesizer` with `.duckOthers` — delay speech by tone duration to avoid interference
- Localization: all user-facing strings go in `Localizable.strings` for all 6 languages (en, ja, zh-Hans, ko, id, hi)
- Sentinel display names (the local player's default name, guest labels) must not be hardcoded string literals — read them from `Player.defaultMyName` / `.guestNearLabel` / `.guestFarLabel` / `.isGuestName(_:)`, since these strings are both displayed *and* used for identity checks (e.g. "don't save a guest to the roster"). A hardcoded literal in one screen and a localized one in another would break that check across locales
- Accessibility: custom/gesture-based controls (e.g. the score tiles) need `accessibilityLabel`/`accessibilityHint` and the right traits; decorative imagery gets `accessibilityHidden(true)`. Accessibility strings are localized like any other (`a11y.*` keys)
- Persistence: read/write `[Player]` and `[MatchRecord]` through `PersistenceStore` — never call `JSONEncoder`/`JSONDecoder` inline in views

---

## GitHub Repo
`rinaba501/badminton-score-tracker`
Issues: https://github.com/rinaba501/badminton-score-tracker/issues
