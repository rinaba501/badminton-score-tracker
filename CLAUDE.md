# Badminton Score Tracker

A **watchOS app** built with SwiftUI for tracking badminton match scores in real time.

> **For the full feature specification, see [SPEC.md](SPEC.md).**
> CLAUDE.md covers project structure, architecture, and working conventions — kept deliberately terse; the deep rationale lives as doc comments in the source files themselves.
> SPEC.md covers what the app does and why.

## Tech Stack

- **Platform:** watchOS · **Language:** Swift · **UI:** SwiftUI
- **Shared code:** local Swift package `BadmintonCore` — Foundation-only (no SwiftUI/WatchKit) so a future iOS target and `swift test` on macOS consume it unchanged
- **Audio:** `AVAudioEngine` sine-wave tones + `AVSpeechSynthesizer` announcements — no audio files
- **Persistence:** `@AppStorage` (UserDefaults) with JSON-encoded structs
- **Sync:** `NSUbiquitousKeyValueStore` (iCloud KV store; requires the ubiquity-kvstore entitlement)
- **Health:** `HKWorkoutSession` + `HKLiveWorkoutBuilder` (HealthKit capability + usage descriptions in Info.plist)

## Project Structure

```
BadmintonCore/                 — local Swift package; platform-free core (no SwiftUI/WatchKit imports, ever)
  Sources/BadmintonCore/
    MatchModel.swift          — BadmintonMatch (pure scoring engine — no UI/timers/player identity), GameScore, MatchRecord, Side
    PersistenceStore.swift    — all JSON encode/decode for [Player]/[MatchRecord]; versioned envelope, per-record-tolerant decoding, migration hooks, iCloud merge/shrink/quota helpers
    Player.swift              — Player model, SortOrder, sentinel identity (guest tokens vs. localized labels — see doc comments)
    StatsCalculator.swift     — pure stats/history derivations; intentionally duplicated function pairs — see file header before unifying anything
    AppStorageKeys.swift      — single source of truth for EVERY UserDefaults/@AppStorage key string
    ScoreCallFormatter.swift  — locale-aware spoken score formatting (en/ja/zh); injectable strings closure for tests
  Tests/BadmintonCoreTests/   — all core unit tests; run with `swift test --package-path BadmintonCore`

badminton score tracker Watch App/
  ContentView.swift          — root view; owns only the AppView routing enum (.menu/.preMatch/.game/.settings/.history/.stats — state-driven, no top-level NavigationLink)
  MenuView.swift             — main menu
  PreMatchView.swift         — two-step player selection
  GameView.swift             — live scoring screen, layout only; all logic delegates to GameViewModel
  GameViewModel.swift        — @MainActor ObservableObject; owns all live-game logic: scoring, undo, time mode, haptics, persistence, announcements
  HapticsProvider.swift      — HapticsProvider protocol + Watch/NoOp implementations (tests use NoOp)
  SettingsView.swift         — match format, audio, theme, timer, roster management
  HistoryView.swift          — saved match list + filters
  StatsView.swift            — per-player stats + head-to-head (math lives in StatsCalculator)
  PlayerEditView.swift       — single-player editor sheet
  PlayerAvatar.swift         — app-side presentation extension of Player (colors/images/icons + AvatarView)
  AudioFeedback.swift        — ScoreAnnouncer (speech) + SoundPlayer (tones)
  CourtTheme.swift           — CourtTheme enum
  AppStore.swift             — @MainActor singleton; caches decoded roster/history, runs migrations on init, all writes go through it (it pushes to iCloud); owns localPlayerId ("Me" is never in the roster)
  WorkoutManager.swift       — HKWorkoutSession lifecycle (start on match begin, end on save/discard)
  CloudSyncManager.swift     — iCloud KV sync; history merges by record id, deletions overwrite (see file comments), other keys last-write-wins; publishes quota warnings
  badminton_score_trackerApp.swift — entry point; starts sync, handles badminton://newmatch deep link
  Assets.xcassets/           — app icon, racket animation, 15 avatar images
  *.lproj/Localizable.strings — en, ja, zh-Hans, ko, id, hi

badminton score tracker Watch AppTests/  — GameViewModel tests (compiled in CI, run locally on a simulator)
badminton score tracker Complication/    — WidgetKit extension (circular/corner/inline/rectangular)
```

Views read shared state via `@EnvironmentObject var store: AppStore`; live-game state lives in `GameViewModel` (created by `GameView` as `@StateObject`).

## AppStorage Keys

All key strings are constants in `BadmintonCore.AppStorageKeys` — **read that file for the current list**; declare `@AppStorage(AppStorageKeys.x)`, never an inline literal, and add new keys there first. Typed defaults stay at the `@AppStorage` declaration sites.

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

### CI & review

Five parallel jobs per PR (SwiftLint, core `swift test`, localization key sync, Watch App build-for-testing, Complication build); green in **~4 min** — details, runtimes, and polling advice in [docs/ci.md](docs/ci.md). Before pushing: run `swiftlint` and `swift test --package-path BadmintonCore`; build locally before pushing SwiftUI changes when possible. **Use plan mode for anything touching `CloudSyncManager`/`AppStore`** (both real bugs in this codebase lived there — see docs/ci.md), and run `/code-review` before merging non-trivial PRs.

## Keeping the Docs Up-to-Date

- User-facing feature change → **`SPEC.md`** (and move closed issues from Open to Closed there, with the PR number)
- New file, model, AppStorage key, or architectural pattern → **`CLAUDE.md`**
- Build/run changes or new top-level doc → **`README.md`** (human-facing; keep short, link out)

A future session reading CLAUDE.md + SPEC.md should have a complete picture of the project. Other docs: `ROADMAP.md` (phased architecture plan + phase→issue map — consult before architectural work, update on phase-issue close), `docs/ci.md` (CI details + review guidance), `.github/` PR/issue templates (follow their shape), `docs/` App Store/privacy content (update only when their subject changes).

## Conventions

- SwiftUI only — no UIKit / WKInterfaceController
- Keep `body` small: pull sub-sections into computed `some View` properties and hoist non-trivial expressions into explicitly-typed helpers — the Swift type-checker times out on large view expressions. Debug builds warn at 100ms per expression (`-warn-long-expression-type-checking=100`); don't ignore that warning
- watchOS constraints: small screen, large tap targets, no keyboard (scribble/dictation only)
- `BadmintonMatch` must remain a pure value type — no UI, no timers, no side effects
- Platform-free logic goes in `BadmintonCore` (never imports SwiftUI/WatchKit); package API the app uses must be `public` (explicit inits included — an `internal` member fails the Watch App build). UI presentation of package models goes in app-side extensions (see `PlayerAvatar.swift`)
- Audio: tones via `AVAudioEngine`, speech via `AVSpeechSynthesizer` with `.duckOthers`; delay speech by tone duration
- Localization: every user-facing string goes in `Localizable.strings` for all 6 languages
- Sentinel identity (guests, "Me") is never a hardcoded literal: store/compare via `Player.guestNearToken`/`.guestFarToken`/`.isGuestName(_:)`/`.defaultMyName`; display/speak via `Player.displayName(for:)`/`.guestNearLabel`/`.guestFarLabel`. Tokens are stored, labels are rendered at the last moment — that's what keeps guest detection locale-independent
- Accessibility: custom/gesture controls need `accessibilityLabel`/`Hint` + traits; decorative imagery gets `accessibilityHidden(true)`; a11y strings are localized (`a11y.*` keys)
- Persistence: read/write `[Player]`/`[MatchRecord]` only through `PersistenceStore` — never inline `JSONEncoder`/`JSONDecoder` in views

## Token Economy

CLAUDE.md is loaded into every session — keep it terse when the doc-update rules require touching it:

- New entries here state *what exists, where it lives, and the hard rule* in one line. Deep rationale and design history go in doc comments at the top of the source file (loaded only when that file is read) or in `docs/`, never as paragraphs here
- Never read `project.pbxproj` (~34KB) or all 6 `Localizable.strings` files wholesale — grep for the section/key you need and edit surgically
- SPEC.md/ROADMAP.md/docs/ are read-on-demand: link to them, don't duplicate their content here
- If SPEC.md's Closed Issues table grows long, prune old rows — git history keeps the record

## GitHub Repo

`rinaba501/badminton-score-tracker` — https://github.com/rinaba501/badminton-score-tracker/issues
