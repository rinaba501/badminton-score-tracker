# Badminton Score Tracker

A **watchOS app** built with SwiftUI for tracking badminton match scores in real time.

> **For the full feature specification, see [SPEC.md](SPEC.md).**
> CLAUDE.md covers project structure, architecture, and working conventions — kept deliberately terse; the deep rationale lives as doc comments in the source files themselves.
> SPEC.md covers what the app does and why.

## Tech Stack

- **Platform:** watchOS (scoring device) + iOS companion app in progress (#41, iPhone-only, iOS 17+) · **Language:** Swift · **UI:** SwiftUI
- **Shared code:** local Swift package `BadmintonCore` — Foundation-only (no SwiftUI/WatchKit) so both app targets and `swift test` on macOS consume it unchanged
- **Audio:** `AVAudioEngine` sine-wave tones + `AVSpeechSynthesizer` announcements — no audio files
- **Persistence:** `@AppStorage` (UserDefaults) with JSON-encoded structs
- **Sync:** `NSUbiquitousKeyValueStore` (iCloud KV store; requires the ubiquity-kvstore entitlement). Phase 4 (#109) adds a CloudKit private-DB path (`CKSyncEngine`) for history+roster behind the `cloudKitSyncEnabled` flag — **default off / ships inert**; KV store still handles everything until the flag is flipped on after a two-device test
- **Health:** `HKWorkoutSession` + `HKLiveWorkoutBuilder` (HealthKit capability + usage descriptions in Info.plist)

## Project Structure

```
BadmintonCore/                 — local Swift package; platform-free core (no SwiftUI/WatchKit imports, ever)
  Sources/BadmintonCore/
    MatchModel.swift          — BadmintonMatch (pure scoring engine — no UI/timers/player identity), GameScore, MatchRecord, Side
    PersistenceStore.swift    — all JSON encode/decode for [Player]/[MatchRecord]; versioned envelope, per-record-tolerant decoding, migration hooks, iCloud merge/shrink/quota helpers, plus single-record codecs + diff/conflict helpers for CloudKit (#109)
    Player.swift              — Player model, SortOrder, sentinel identity (guest tokens vs. localized labels — see doc comments)
    StatsCalculator.swift     — pure stats/history derivations; intentionally duplicated function pairs — see file header before unifying anything
    AppStorageKeys.swift      — single source of truth for EVERY UserDefaults/@AppStorage key string
    ScoreCallFormatter.swift  — locale-aware spoken score formatting (en/ja/zh); injectable strings closure for tests
  Tests/BadmintonCoreTests/   — all core unit tests; run with `swift test --package-path BadmintonCore`

badminton score tracker Watch App/
  ContentView.swift          — root view; owns only the AppView routing enum (.menu/.preMatch/.game/.settings/.history/.stats — state-driven, no top-level NavigationLink)
  MenuView.swift             — main menu
  PreMatchView.swift         — player selection: 2 steps (Singles) or 4 steps (Doubles, reading SettingsView.GameMode)
  GameView.swift             — live scoring screen, layout only; all logic delegates to GameViewModel. ScoreView renders one or two stacked names per team depending on whether a partner is present
  GameViewModel.swift        — @MainActor ObservableObject; owns all live-game logic: scoring, undo, time mode, haptics, persistence, announcements, doubles partner names/rotation display
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
  CloudSyncManager.swift     — iCloud KV sync; history merges by record id, deletions overwrite (see file comments), other keys last-write-wins; publishes quota warnings. When `cloudKitSyncEnabled` is on it carries scalar settings only (CloudKit owns history+roster)
  CloudKitSyncManager.swift  — CloudKit private-DB sync via CKSyncEngine (one CKRecord per match/player, opaque JSON payload; real per-record deletion). Ships inert behind `cloudKitSyncEnabled` (default off); no CloudKit entitlement needed until flipped on. Correctness is NOT CI-provable — gated on a two-device test
  badminton_score_trackerApp.swift — entry point; starts sync, handles badminton://newmatch deep link
  Assets.xcassets/           — app icon, racket animation, 15 avatar images
  *.lproj/Localizable.strings — en, ja, zh-Hans, ko, id, hi

badminton score tracker Watch AppTests/  — GameViewModel tests (compiled in CI, run locally on a simulator)
badminton score tracker Complication/    — WidgetKit extension (circular/corner/inline/rectangular)

badminton score tracker/       — iOS companion app (#41, in progress). Same target that used to be the watch-only stub container — now a real iOS app (NavigationStack root, iPhone-only, iOS 17+) that still embeds the Watch App. Has its own Info.plist, Assets.xcassets, .entitlements, and 6 *.lproj tables (iOS-only chrome under ios.*; History/Stats screens reuse the Watch's own string keys verbatim so translations copy across); the Watch App's Info.plist now declares it as companion (WKCompanionAppBundleIdentifier) instead of WKWatchOnly
  ContentView.swift          — iOS root: NavigationStack + List menu linking to History and Stats (Watch stays the scoring device)
  HistoryView.swift          — iOS match list + MatchHistoryRow; date/type/sort/player filters and swipe-delete/clear-all. All filtering delegates to StatsCalculator; pushed via NavigationStack (no currentView binding). iOS-native restyle of the Watch's HistoryView
  StatsView.swift            — iOS per-player stats: win-rate ring + stat-card grid + avatar'd head-to-head; math all in StatsCalculator. iOS-native restyle of the Watch's StatsView
  RosterView.swift           — iOS roster management (edit Me, add/rename/delete players, sort order). Ported from the Watch SettingsView roster section, incl. the rename→history propagation (renames update past matches via player id + update myName). Writes via AppStore.saveRoster/saveHistory
  PlayerEditView.swift       — iOS single-player editor sheet (real keyboard TextField + duplicate detection, color/avatar/icon grids). Restyle of the Watch's; validation logic verbatim
  PlayerAvatar.swift         — iOS presentation extension of Player (avatarColors/avatarImageNames/sportIcons/AvatarView). Per-target copy of the Watch's; the 15 avatar images are duplicated into this target's Assets.xcassets
  ShareCard.swift            — iOS-only (#13): match-result card rendered to PNG via ImageRenderer + a SharableMatchCard Transferable (image + plain-text). Long-press a history row → ShareLink. No Watch counterpart
  NewMatchFlow.swift         — modal container (fullScreenCover from ContentView) routing preMatch → game; PreMatchView writes match-config @AppStorage, GameView's VM reads it on appear (same handoff as the Watch's .preMatch/.game routes)
  PreMatchView.swift         — iOS player selection (singles/doubles picker + near/partner/far/partner steps, h2h records); reuses PlayerEditView to add players. Closure-driven (onReady/onCancel), no currentView binding
  GameView.swift             — iOS live scoring: two big tap tiles (ScoreView), games header, timer, banners, match-over overlay. Tap-only — NO Digital Crown, NO HealthKit workout. Restyle of the Watch's
  GameViewModel.swift        — iOS @MainActor VM; per-target adaptation of the Watch's (UIKit haptics, no WorkoutManager, top-level GameMode). Match-config keys (matchMyName/…/gameMode) are KV-excluded so phone- and watch-scored matches can't collide; finished MatchRecord flows through the shared shrink-aware saveHistory
  HapticsProvider.swift      — iOS HapticsProvider protocol + GameHapticType (platform-neutral) + UIKitHapticsProvider (impact/notification generators). Mirrors the Watch's WKHapticType abstraction
  CourtTheme.swift / AudioFeedback.swift — per-target copies of the Watch's (CourtTheme colors; AVFoundation tones + speech are cross-platform, byte-identical)
  CloudSyncManager.swift     — iOS iCloud KV sync; port of the Watch's. Shares the Watch's KV bucket via a byte-identical ubiquity-kvstore-identifier ($(TeamIdentifierPrefix)ritsuma.badminton-score-tracker.shared) declared in BOTH targets' .entitlements — they MUST stay identical or the apps land in different buckets and stop syncing
  AppStore.swift             — iOS cache/singleton; port of the Watch's, incl. the CloudKitSyncManager.isEnabled branches and applyRemoteUpsert/applyRemoteDeletions. Write-capable: saveRoster/saveHistory/clearHistory push to the shared KV bucket; saveHistory keeps the isHistoryShrink overwrite-vs-merge guard (deletions overwrite, not merge — else iCloud's unshrunk copy resurrects them)
  CloudKitSyncManager.swift  — iOS CloudKit private-DB sync via CKSyncEngine; near-verbatim port of the Watch's, sharing the same CloudKit container (iCloud.ritsuma.badminton-score-tracker) so watch and phone sync with each other. Ships inert behind `cloudKitSyncEnabled` (default off on both targets); no shipping toggle default-flip has happened — see the Settings sync section on both targets
  SettingsView.swift         — iOS: currently just the cloudKitSyncEnabled toggle (Sync section), reachable from a ContentView menu row. Room to grow into a fuller settings mirror of the Watch's later
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

Seven parallel jobs per PR (SwiftLint, core `swift test`, localization key sync ×2 — Watch + iOS tables are checked separately since their key sets legitimately diverge, Watch App build-for-testing, Complication build, iOS App build); green in **~4 min** — details, runtimes, and polling advice in [docs/ci.md](docs/ci.md). Before pushing: run `swiftlint` and `swift test --package-path BadmintonCore`; build locally before pushing SwiftUI changes when possible. **Use plan mode for anything touching `CloudSyncManager`/`CloudKitSyncManager`/`AppStore` (Watch OR iOS)** (both real bugs in this codebase lived there — see docs/ci.md; the iOS copies are the same hazard class and now a second writer to the shared KV bucket; sync correctness can't be proven by CI, only a two-device test), and run `/code-review` before merging non-trivial PRs.

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
