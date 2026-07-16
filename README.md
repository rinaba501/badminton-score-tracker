# Badminton Score Tracker

A watchOS app, with an iPhone companion, for tracking badminton match scores in real time.

[![CI](https://github.com/rinaba501/badminton-score-tracker/actions/workflows/ci.yml/badge.svg)](https://github.com/rinaba501/badminton-score-tracker/actions/workflows/ci.yml)

<p>
  <img src="docs/screenshots/01_menu.png" width="160" alt="Watch menu screen" />
  <img src="docs/screenshots/03_game.png" width="160" alt="Watch live scoring screen" />
  <img src="docs/screenshots/04_history.png" width="160" alt="Watch match history screen" />
  <img src="docs/screenshots/05_stats.png" width="160" alt="Watch player stats screen" />
</p>
<p>
  <img src="docs/screenshots/ios/6.9in/01_menu.png" width="160" alt="iPhone menu screen" />
  <img src="docs/screenshots/ios/6.9in/03_game.png" width="160" alt="iPhone live scoring screen" />
</p>

## What it does

- Tap-to-score or Digital Crown scoring, with serve tracking and haptic/spoken feedback
- Best-of-N match formats (11/15/21 points), plus an optional match timer mode
- Player roster with avatars, match history, and per-player / head-to-head stats
- Watch face complication, HealthKit workout logging, and iCloud sync across your own devices
- iPhone companion app with 7 selectable live-scoring layouts, sharing roster/history/stats with the Watch app via iCloud
- Localized into English, Japanese, Simplified Chinese, Korean, Indonesian, and Hindi
- VoiceOver-accessible scoring controls

See [`SPEC.md`](SPEC.md) for the full feature spec, and the [Open Issues](SPEC.md#open-issues) table for what's planned next. [`ROADMAP.md`](ROADMAP.md) lays out the long-term architecture plan — shared core package, CloudKit sync, sharing between players, and an iOS companion app.

## Requirements

- Xcode (CI selects the newest Xcode installed on the runner — currently 26.6; watchOS + iOS Simulators)
- watchOS 11.4+ deployment target (Watch App)
- iOS 17+ deployment target, iPhone-only (companion app)

## Building & running

1. Open `badminton score tracker.xcodeproj` in Xcode.
2. Select the **badminton score tracker Watch App** scheme (Watch) or the **badminton score tracker** scheme (iPhone companion).
3. Run on a Simulator or a paired/connected device.

Core logic (scoring, persistence, stats) lives in the local `BadmintonCore` Swift package; its tests run with `swift test --package-path BadmintonCore` — no simulator needed. The `badminton score tracker Watch AppTests` bundle remains for app-layer tests (⌘U in Xcode).

## Project structure & conventions

[`CLAUDE.md`](CLAUDE.md) documents the file layout, key models, `@AppStorage` keys, and coding conventions this codebase follows — start there before making changes. CI job details and review guidance live in [`docs/ci.md`](docs/ci.md).

## Development

This codebase is developed primarily with [Claude Code](https://claude.com/claude-code), with human review before anything merges to `main`. Every PR that changes a feature updates [`SPEC.md`](SPEC.md); every PR that changes structure or conventions updates [`CLAUDE.md`](CLAUDE.md) — see [`CLAUDE.md`'s Git Workflow section](CLAUDE.md#git-workflow--must-follow) for the full process.

## License

Apache License 2.0 — see [`LICENSE`](LICENSE).
