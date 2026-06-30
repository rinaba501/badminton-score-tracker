# Badminton Score Tracker — Feature Spec

Living specification for the watchOS app. Every PR that adds or changes a feature must update this file.

---

## Platform

- **Target:** watchOS (Apple Watch)
- **Language:** Swift / SwiftUI
- **Persistence:** `@AppStorage` (UserDefaults) with JSON-encoded structs
- **Audio:** `AVAudioEngine` + programmatic sine-wave tone generation (no audio files)
- **Health:** `HealthKit` — logs each match as a `.badminton` `HKWorkoutSession`; activity type indoor

---

## Screens

### Menu
- New Match → opens Pre-Match
- Match History → opens History
- Player Stats → opens Stats
- Settings → opens Settings

### Watch Face Complication
- Circular, corner, inline, and rectangular complication families supported
- Tapping any complication deep-links to Pre-Match via `badminton://newmatch`
- Complication source in `badminton score tracker Complication/` — separate WidgetKit extension target

### Pre-Match
Two-step flow:
1. **Near Side** — pick yourself or a roster player or a guest
2. **Far Side** — pick opponent (excludes Near Side selection); selecting immediately starts the match

### Game Screen
- **Tap** top/bottom half to score for that player
- **Undo** button (inline in header) — reverts last point; disabled during game-over overlay
- **Digital Crown** — rotate to score (clockwise = me, counter-clockwise = opponent)
- **Serve indicator** — small dot next to serving player's name; side (left/right) reflects service court (even score = right, odd = left)
- **Game-point / Match-point banner** — red banner at top when either side is one point from winning
- **Score pulse animation** — score number pulses on each point
- **Winner glow** — winning player's avatar turns gold when game ends
- **Game-over overlay** — shows game result and "Next Game" button; serve auto-assigns to the game winner (correct badminton rules)
- **Match-over overlay** — shows trophy, winner name, games score, "New Match" button

### Match History
- Lists all completed matches in reverse chronological order
- Each row: player names, games won, per-game scores, date, duration
- Swipe to delete individual records
- "Clear All" button with confirmation
- **Filter by player** — picker to show only matches involving a specific player (hidden if only one player in history)
- **Filter by date range** — All Time / This Week / This Month

### Player Stats
- Win rate, total matches, win/loss streak per player
- Filtered to the configured "Me" player
- **Head-to-Head** section listing W–L record against each opponent in history

### Pre-Match (opponent picker)
- Roster rows show H2H record (`XW – YL`) against the near-side player when picking an opponent; hidden if no prior matches exist

### Settings
- **Me** section — single tappable row showing avatar + name; opens Player Edit
- **Players** section — roster list; tap to edit, swipe to delete
- **Game Mode** — Singles / Doubles (Doubles UI not yet implemented)
- **Match Format** — Points to win (11 / 15 / 21), Games in match (1 / 3 / 5)
- **Match Timer** — toggle on/off; when enabled, duration stepper (±1 min, ±5 min buttons; min 1, max 99, default 10)
- **Court Theme** — Green / Blue / Red / Purple / Black
- **Digital Crown** — toggle crown scoring on/off (default on); off prevents accidental scoring from wrist movement
- **Score Announcement** — toggle spoken score via `AVSpeechSynthesizer`
- **Sound Effects** — toggle programmatic tones
- **Controls** — permanent gesture reference screen (tap, crown directions, undo)

---

## Scoring Rules

- Win a game at `pointsToWin` (default 21) with a 2-point lead
- Cap at `pointsToWin + 9` (default 30) — at 29-29 the 30th point wins
- Win the match by winning `ceil(gamesInMatch / 2)` games (default best-of-3)
- Serve changes on every rally won (rally point scoring)
- Serve indicator is hidden at 0-0; appears from the first point onward
- Service court: right when server's score is even, left when odd

### Match Timer mode
- All scoring rules above still apply (games end at 21, match ends at 2 games won, etc.)
- A countdown timer is shown above the games header
- Timer turns red in the last 30 seconds
- Timer pauses at zero — does not tick during game-over overlay
- **When timer reaches 0:**
  - Leader by games won → wins the match immediately
  - Tied on games → leader by current game score wins the match
  - Fully tied → **Sudden Death**: next point wins the match
- If a player wins the required games before the timer runs out, the match ends normally

---

## Players & Roster

- Players have: `id: UUID`, `name: String`, `colorIndex: Int`, `iconName: String?`
- **Avatar** — circle with player color; shows asset image, SF Symbol, or initials fallback
- **15 avatar images** — shuttlecock, racket, and character stickers (transparent PNG)
- **12 SF Symbol sport icons** — star, bolt, flame, crown, etc.
- **12 avatar colors** — blue, green, orange, purple, pink, red, cyan, mint, teal, indigo, yellow, brown
- Roster players are saved on first match with a new name
- **"Me" player** — stored in roster like any other player; shown under "Me" section in Settings, hidden from the Players list
- Duplicate names are rejected when renaming (alert shown)
- Renaming a player propagates to all match history records that reference their `UUID`

---

## Match History Storage

- `MatchRecord` fields: `id`, `games: [GameScore]`, `myGamesWon`, `opponentGamesWon`, `winner`, `myName`, `opponentName`, `date`, `duration`, `myPlayerId: UUID?`, `opponentPlayerId: UUID?`
- Player IDs are stored at match-save time by looking up names in the current roster
- Old records without IDs fall back to stored name strings
- When a player is renamed, all history records referencing their ID are updated

---

## Sound & Haptics

| Event | Haptic | Tone |
|---|---|---|
| Point scored | `.click` | 880 Hz, 0.18s |
| Game point reached | `.notification` | 740 Hz, 0.18s |
| Game won | `.success` + `.retry` | C5→E5 |
| Match won | `.success` × 2 | C5→E5→G5 fanfare |
| Undo | `.directionUp` | — |
| Sudden death | `.notification` | — |

- Score announcement via `AVSpeechSynthesizer` — server score first, then receiver score
- "love" used for 0 in English; katakana numbers in Japanese; numerals in Chinese/other
- Language auto-detected from device locale

---

## Animations

- **Racket animation** — plays on game start before score UI appears
- **Score pulse** — scale animation on score number each point
- **Winner glow** — avatar transitions to yellow on game win
- **Trophy shimmer** — match-over overlay trophy pulses

---

## Localization

Supported languages: English, Japanese (ja), Chinese Simplified (zh-Hans), Indonesian (id), Korean (ko), Hindi (hi)

---

## Open Issues

| # | Feature |
|---|---------|
| 8 | Doubles support (2v2) |
| 10 | Match history (enhanced) |
| 11 | Player stats (win rate, streaks, avg points) |
| 13 | Share match result — deferred until iPhone companion app exists |
| 41 | iPhone companion app |

---

## Closed Issues

| # | Feature | PR |
|---|---|---|
| 5 | Match Timer mode | #42 |
| 6 | App icon | #38 |
| 7 | Character selection per opponent | closed (roster system covers this) |
| 14 | Sound effects | #37 |
| 15 | Dark/light mode toggle | closed (Apple Watch is always dark) |
| 16 | Undo last point | #2 |
| 17 | Court color themes | #21 |
| 18 | Custom player names with avatar | #34, #36, #39 |
| 49 | Reselect who serves between games | #53 |
