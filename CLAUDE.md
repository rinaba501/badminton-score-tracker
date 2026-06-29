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

---

## Project Structure

```
badminton score tracker Watch App/
  ContentView.swift          — all views and UI logic
  MatchModel.swift           — BadmintonMatch, GameScore, MatchRecord, Side
  badminton_score_trackerApp.swift — app entry point
  Assets.xcassets/           — app icon, racket animation asset, 15 avatar images
  *.lproj/Localizable.strings — en, ja, zh-Hans, ko, id, hi
```

### Key Models

**`MatchModel.swift`**
- `Side` — `.me` / `.opponent`
- `GameScore` — `my: Int`, `opponent: Int` for one completed game
- `BadmintonMatch` — pure scoring engine; no UI, no timers. Tracks scores, games won, serve side, win conditions
- `MatchRecord` — persisted match result; stores player names + optional `UUID` player IDs for name-change tracking

**`ContentView.swift`**
- `Player` — `id: UUID`, `name`, `colorIndex`, `iconName?`; stored as JSON in `@AppStorage("playerRoster")`
- `AvatarView` — renders asset image, SF Symbol, or initials depending on `iconName`
- `ScoreAnnouncer` — wraps `AVSpeechSynthesizer`
- `SoundPlayer` — wraps `AVAudioEngine` for programmatic tones
- All screens: `MenuView`, `PreMatchView`, `GameView`, `SettingsView`, `HistoryView`, `StatsView`, `PlayerEditView`

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
| `iServeFirst` | `Bool` | Serve preference |
| `pointsToWin` | `Int` | Default 21 |
| `gamesInMatch` | `Int` | Default 3 |
| `courtTheme` | `String` | `CourtTheme` raw value |
| `announceScore` | `Bool` | Score announcement toggle |
| `enableSounds` | `Bool` | Sound effects toggle |
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
- Keep watchOS constraints in mind: small screen (~44–46mm), large tap targets, no keyboard by default (scribble/dictation only)
- `BadmintonMatch` must remain a pure value type — no UI, no timers, no side effects
- Audio: tones via `AVAudioEngine`, speech via `AVSpeechSynthesizer` with `.duckOthers` — delay speech by tone duration to avoid interference
- Localization: all user-facing strings go in `Localizable.strings` for all 6 languages (en, ja, zh-Hans, ko, id, hi)

---

## GitHub Repo
`rinaba501/badminton-score-tracker`
Issues: https://github.com/rinaba501/badminton-score-tracker/issues
