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

## App Privacy

The backend migrated from CloudKit to Supabase/Postgres (Roadmap Phase 9) — sync is now an explicit per-device opt-in (default is local-only, `NoOpSyncEngine`; nothing leaves the device until the user turns on "Sync Backend" in Settings and signs in with Google). Because that opt-in path exists in the shipping build, App Store Connect's App Privacy section must reflect it — **do not declare "Data Not Collected"**.

When a user opts into sync, the following is sent to the developer's own Supabase project (not a third-party analytics SDK — this is first-party backend storage the developer operates):
- **Identifiers:** User ID (Google OAuth account identifier / Supabase `auth.uid()`)
- **Contact Info:** Name (the player's chosen display name)
- **User Content:** the match/roster/club/friends data the user enters (scores, player names, avatars) and, only if the user separately enables each sharing toggle, gender/birthday/introduction/stats shared with accepted friends
- None of the above is used for tracking (no cross-app/cross-company data linkage, no ad targeting)

Declare these under **"Data Linked to You"** (tied to the account identifier) rather than "Data Not Collected." HealthKit workout data stays local to the user's own Health database and is never sent to Supabase or the developer — that part of the old CloudKit-era description is still accurate. No analytics SDKs, no advertising SDKs, no third parties beyond the developer's own Supabase project.

---

## Screenshots

Captured in `docs/screenshots/`:
- `docs/screenshots/` — Apple Watch Ultra 3 (49mm)
- `docs/screenshots/46mm/` — Apple Watch Series 11 (46mm)
- `docs/screenshots/ios/6.9in/` — iPhone 17 Pro Max (6.9", 1320×2868) — menu, pre-match, live game (3 variants: Depth style in-progress, BirdsEye style, game-point banner), match history, stats

Watch: five screens each (menu, pre-match, live game, match history, stats). iOS: same five plus two extra live-game variants showing off different `GameScreenStyle` options.

All captured with fixture data only (players Jordan/Morgan/Sam/Taylor, "Me" name Alex) on an erased/iCloud-free simulator — no real personal data.

**Still open:** Apple's current App Store Connect screenshot requirements only strictly require the largest display class per device family (6.9" here covers iPhone); double-check at upload time whether 6.5"/6.3" iPhone slots are still separately requested, and capture those from the same fixture-data simulator session if so.

---

## Age Rating

4+ (no objectionable content).

---

## Review Notes (for App Review team)

```
Featherkeep is a badminton scorekeeping app with an Apple Watch app and an iPhone companion — either can score a match standalone, or run together with iCloud sync. No login or account is required — all features are available immediately. HealthKit is used only to log a workout when a match starts on Apple Watch; declining the permission does not affect scoring. iCloud sync is optional and degrades gracefully if the user is not signed in.
```
