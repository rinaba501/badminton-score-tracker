# App Store Metadata — Badminton Score Tracker

Copy-paste source for App Store Connect. Character limits noted per field.

---

## App Name (30 chars max)

```
Badminton Score Tracker
```
*(23 chars)*

## Subtitle (30 chars max)

```
Live match scoring on watch
```
*(27 chars)*

Alternatives if you want a different angle:
- `Keep score, play more` (21)
- `Tap to score every rally` (24)
- `Your wrist-side umpire` (22)

---

## Promotional Text (170 chars max — editable any time without review)

```
Tap your side of the court to score. The app tracks serve, games, and match wins automatically — so you can keep your eyes on the shuttle.
```
*(137 chars)*

---

## Description (4000 chars max)

```
Keep score of your badminton matches right from your wrist — no phone, no paper, no shouting "what's the score?" mid-rally.

Badminton Score Tracker is built for watchOS from the ground up. Tap the top or bottom of the screen to score a point, and the app handles everything else: serve rotation, service court, game wins, and match completion — all following official badminton rules.

SCORING MADE EFFORTLESS
• Tap top or bottom of the screen to score for either player
• Or rotate the Digital Crown to score without looking
• Undo any accidental point with one tap
• Serve indicator shows who's serving and from which court
• Game-point and match-point banners so you always know what's on the line

MATCH FORMATS
• Points to win: 11, 15, or 21
• Best of 1, 3, or 5 games
• Rally point scoring with 2-point lead and 30-point cap
• Match Timer mode — play to the clock with sudden-death tiebreak

HISTORY & STATS
• Every match saved automatically
• Filter history by player or by date (this week / this month / all time)
• Win rate, total matches, and win/loss streaks
• Head-to-head records against each of your regular opponents

MADE FOR PLAYERS
• Build a roster of players with custom names, colors, and avatars
• 15 avatar stickers, 12 sport icons, and 12 colors to choose from
• Spoken score announcements after each point (optional)
• Satisfying sound effects and haptics on every point
• Five court color themes: green, blue, red, purple, black

SYNC & HEALTH
• iCloud sync keeps your roster, history, and settings on all your devices
• Each match is logged to Apple Health as a badminton workout
• Watch face complication — start a new match with one tap

Available in English, Japanese, Chinese (Simplified), Korean, Indonesian, and Hindi.

No account required. No ads. No tracking. Your data stays on your devices and in your private iCloud.
```

---

## Keywords (100 chars max, comma-separated, no spaces)

```
badminton,score,scorekeeper,racket,sport,match,shuttlecock,tracker,counter,umpire,games,squash
```
*(94 chars)*

Notes:
- Don't repeat words already in the app name ("badminton" is borderline — kept because it's the core search term).
- Apple ignores spaces after commas, so omit them to save characters.

---

## Categories

- **Primary:** Sports
- **Secondary:** Health & Fitness

---

## URLs

- **Support URL:** `https://github.com/rinaba501/badminton-score-tracker/issues`
- **Marketing URL:** `https://rinaba501.github.io/badminton-score-tracker/`
- **Privacy Policy URL:** `https://rinaba501.github.io/badminton-score-tracker/privacy-policy`

---

## App Privacy ("Data Not Collected")

In App Store Connect → App Privacy, declare **Data Not Collected**. The app:
- Stores all data locally and in the user's private iCloud (CloudKit private database; shared zones for clubs)
- Logs workouts to the user's own Health database
- Uses no analytics, no third-party SDKs, no advertising
- Sends no data to the developer or any server

---

## Screenshots

Captured in `docs/screenshots/`:
- `docs/screenshots/` — Apple Watch Ultra 3 (49mm)
- `docs/screenshots/46mm/` — Apple Watch Series 11 (46mm)

Five screens each: menu, pre-match, live game, match history, stats.

---

## Age Rating

4+ (no objectionable content).

---

## Review Notes (for App Review team)

```
Badminton Score Tracker is a standalone watchOS app for keeping score during badminton matches. No login or account is required — all features are available immediately. HealthKit is used only to log a workout when a match starts; declining the permission does not affect scoring. iCloud sync is optional and degrades gracefully if the user is not signed in.
```
