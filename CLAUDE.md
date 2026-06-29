# Badminton Score Tracker

A **watchOS app** built with SwiftUI for tracking badminton match scores in real time.

## Tech Stack
- **Platform:** watchOS (Apple Watch)
- **Language:** Swift
- **UI Framework:** SwiftUI
- **Audio:** AVFoundation (for score/win sound effects)
- **Persistence:** `@AppStorage` (UserDefaults) with JSON encoding for game history

## Project Structure
All app code lives in a single file:
- `badminton score tracker Watch App/ContentView.swift` — all views and logic
- `badminton score tracker Watch App/badminton_score_trackerApp.swift` — app entry point
- `badminton score tracker Watch App/Assets.xcassets/` — images (racket asset used in animation)

## Current Features
- **Menu screen** — New Game, Game History, Settings
- **Game screen** — tap to score, long-press to reset, match point indicator, winner overlay
- **Scoring rules** — win at 21 with 2-point lead, cap at 30 (deuce rules implemented)
- **Racket animation** — plays on game start before the score UI appears
- **Sound effects** — score sound and win sound via AVAudioPlayer (sound files must be in bundle)
- **Game history** — saved to AppStorage, viewable in HistoryView
- **Settings** — player names (myName / opponentName), game mode (singles/doubles enum exists but doubles not fully implemented)

## Architecture Notes
- Navigation is state-driven via `ContentView.AppView` enum (menu/game/settings/history) — no NavigationLink
- `@AppStorage` is used for all persistence (no CoreData or SwiftData)
- `GameView.GameMode` enum (singles/doubles) is defined but doubles logic is not yet implemented
- All views are in one file — consider splitting as the app grows

## GitHub Repo
`rinaba501/badminton-score-tracker`

## Open Issues (Feature Backlog)
All tracked at https://github.com/rinaba501/badminton-score-tracker/issues

| # | Feature |
|---|---------|
| 3 | Ask who serves first at match start |
| 4 | Configurable match format (games & points) |
| 5 | Time mode |
| 6 | App icons |
| 7 | Character selection per opponent |
| 8 | Doubles support |
| 9 | More animations |
| 10 | Match history (enhanced) |
| 11 | Player stats (win rate, streaks, avg points) |
| 12 | Game duration tracking |
| 13 | Share match result as image |
| 14 | Sound effects (score, game win, match win) |
| 15 | Dark / light mode toggle |
| 16 | Undo last point |
| 17 | Court color themes |
| 18 | Custom player names with avatar/initials |

## Conventions
- Use SwiftUI for all UI — no UIKit/WKInterfaceController
- Keep watchOS constraints in mind: small screen (~44mm/45mm), no keyboard by default, tap targets must be large
- Sound files (`.mp3`) must be added to the Xcode bundle manually
- Run on a real Apple Watch or watchOS Simulator for testing

## Git Workflow
- **All changes must go through a PR** — never commit directly to `main`
- Create a feature branch (`feature/...`) or fix branch (`fix/...`) for every change
- Every PR that adds or changes a feature must also update `SPEC.md`
- After merging, delete the local branch and prune remote refs
