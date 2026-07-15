# App Store Metadata — Featherkeep

Copy-paste source for App Store Connect. Character limits noted per field.

---

## App Name (30 chars max)

```
Featherkeep
```
*(11 chars)*

## Subtitle (30 chars max)

```
Score badminton, iPhone/Watch
```
*(29 chars)*

Options that fit:
- `Badminton scoring, iOS & Watch` (30)
- `Live scoring, iPhone & Watch` (28)
- `Your wrist-side umpire` (22 — Watch-only framing, avoid now)

---

## Promotional Text (170 chars max — editable any time without review)

```
Tap your side of the court to score. The app tracks serve, games, and match wins automatically — so you can keep your eyes on the shuttle.
```
*(137 chars)*

---

## Description (4000 chars max)

```
Keep score of your badminton matches from your wrist or your phone — no paper, no shouting "what's the score?" mid-rally.

Featherkeep runs as an Apple Watch app and an iPhone companion, sharing the same roster, history, and stats via iCloud. Tap the top or bottom of the screen to score a point, and the app handles everything else: serve rotation, service court, game wins, and match completion — all following official badminton rules.

SCORING MADE EFFORTLESS
• Tap top or bottom of the screen to score for either player
• On Apple Watch, rotate the Digital Crown to score without looking
• Score live from your iPhone too — no watch required
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
• Score on your Watch, review on your iPhone — or the other way around
• Each match is logged to Apple Health as a badminton workout
• Watch face complication — start a new match with one tap
• Share a match result as an image from iPhone

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
- "Featherkeep" doesn't contain "badminton" or "score" at all now, so keep both as keywords — they carry the core search intent the name no longer signals.
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

**Missing — needs capture before submission:** App Store Connect requires iPhone screenshots too, since this is now a combined iOS + watchOS listing (6.9" display class at minimum, plus possibly 6.3"/6.1"). None exist yet in `docs/screenshots/`.

**Note for whoever captures these:** a first attempt on the iPhone 17 Pro Max simulator pulled down real synced CloudKit data (actual roster names) instead of fixture data — the simulator was signed into a real iCloud account. Use a fresh simulator with no iCloud account signed in, or disable network before creating fixture players, so no real personal data (or accidental writes to the real account) ends up in App Store assets.

---

## Age Rating

4+ (no objectionable content).

---

## Review Notes (for App Review team)

```
Featherkeep is a badminton scorekeeping app with an Apple Watch app and an iPhone companion — either can score a match standalone, or run together with iCloud sync. No login or account is required — all features are available immediately. HealthKit is used only to log a workout when a match starts on Apple Watch; declining the permission does not affect scoring. iCloud sync is optional and degrades gracefully if the user is not signed in.
```
