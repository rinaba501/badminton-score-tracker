# Badminton Score Tracker — Feature Spec

Living specification for the watchOS app. Every PR that adds or changes a feature must update this file.

---

## Platform

- **Target:** watchOS (Apple Watch) — the scoring device — plus an iPhone companion app (in progress, #41)
- **Language:** Swift / SwiftUI
- **Persistence:** `@AppStorage` (UserDefaults) with JSON-encoded structs
- **Audio:** `AVAudioEngine` + programmatic sine-wave tone generation (no audio files)
- **Health:** `HealthKit` — logs each match as a `.badminton` `HKWorkoutSession`; activity type indoor
- **Sync:** CloudKit only (`CKSyncEngine` on both Watch + iOS) — one `CKRecord` per match/player/club plus a fixed personal-zone `Settings` record carrying every scalar setting (`myName`, `localPlayerId`, `pointsToWin`, `gamesInMatch`, `courtTheme`, `announceScore`, `enableSounds`, `enableCrownScoring`, `timeModeEnabled`, `timeLimitMinutes`). No iCloud KV store / `NSUbiquitousKeyValueStore` path and no feature flag — engines start on launch. Correctness still needs a real two-device iCloud test (not CI-provable)

### iOS Companion App (in progress — #41, ROADMAP Phase 6)

- The former stub container target is now a real iOS app (`NavigationStack`-based, iPhone-only, iOS 17+)
- **Score a match on the phone** (New Match → pick singles/doubles and players → tap-to-score). Same rules, serve tracking, time mode, sounds, and spoken announcements as the Watch; the finished match saves to the shared iCloud history. iPhone omits the Digital Crown and HealthKit workout logging (both watchOS-only) — the Watch stays the richest scoring device, but the phone is now fully capable on its own
- **Share a match result** (#13): long-press any history row to share a rendered summary card (final score, team names, per-game line, date) as an image, plus a plain-text fallback, through the native iOS share sheet
- **Match History and Stats are on iPhone.** A dashboard-style home screen (quick-stats strip: matches / win rate / players, plus a prominent New Match button) links to a full Match History (date-range / match-type / sort / multi-player filters, avatar'd rows, swipe-to-delete, clear-all) and a Stats screen (win-rate ring, stat cards, head-to-head with avatars) — the same information and derivations as the Watch, restyled for the phone. Deleting a match on iPhone removes it everywhere via iCloud.
- **Roster management is on iPhone** (with a real keyboard): edit your own name/avatar, add / rename / delete saved players, choose the roster sort order, and pick an avatar color, image, or icon. Renaming a player updates their name in every past match. Changes sync to the Watch via iCloud.
- **iCloud sync is live:** the iPhone reads (and can edit/delete) the same match history, roster, clubs, and identity/match-format settings the Watch records — both share one CloudKit container (`iCloud.ritsuma.badminton-score-tracker`). No new iCloud account or pairing step; sign both devices into the same Apple ID. The Watch stays the richest scoring device.
- Distribution shape changed with the shell: the Watch app is no longer `WKWatchOnly` — it declares the iOS app as its companion (`WKCompanionAppBundleIdentifier`) and keeps running independently (`WKRunsIndependentlyOfCompanionApp`). **An App Store submission from a commit after this change ships the iOS app too; to submit watch-only, archive from an earlier commit**

---

## Screens

### Menu
- New Match → opens Pre-Match
- Match History → opens History
- Player Stats → opens Stats
- Settings → opens Settings

### Watch Face Complication
- Circular, corner, inline, and rectangular complication families supported
- The circular family draws a vector rendition of the shuttlecock mascot (feather crown, white cork body, smiling face) in the app-icon colors; tinted/vibrant watch faces automatically reduce it to luminance shades
- Tapping any complication deep-links to Pre-Match via `badminton://newmatch`
- Complication source in `badminton score tracker Complication/` — separate WidgetKit extension target

### Pre-Match
Two-step flow in Singles mode, four-step in Doubles mode (see Settings → Game Mode):
1. **Near Side** — pick yourself or a roster player or a guest
2. **Near Partner** (Doubles only) — pick your teammate; excludes the Near Side pick
3. **Far Side** — pick opponent; excludes everyone already picked on the near team
4. **Far Partner** (Doubles only) — pick the opponent's teammate; excludes everyone already picked; selecting starts the match

### Game Screen
- **Tap** top/bottom half to score for that player (or team, in Doubles)
- **Undo** button (inline in header) — reverts last point; disabled during game-over overlay
- **Digital Crown** — rotate to score (clockwise = me, counter-clockwise = opponent)
- **Serve indicator** — small dot next to the serving player's name (Singles only); side (left/right) reflects service court (even score = right, odd = left); hidden at 0-0
- **Doubles team tiles** — each team's tile shows both partner names stacked with equal weight; the serve indicator stays team-level (tile border highlight + right/left court label), same as it is for Singles alongside the dot. The app does not track or display which specific partner is currently serving
- **Game-point / Match-point banner** — red banner at top when either side is one point from winning
- **Score pulse animation** — score number pulses on each point
- **Winner glow** — winning player's avatar turns gold when game ends
- **Game-over overlay** — shows game result and "Next Game" button; serve auto-assigns to the game winner (correct badminton rules)
- **Match-over overlay** — shows trophy, winner name (both partners' names in Doubles), games score, "New Match" button

### Match History
- Lists all completed matches in reverse chronological order
- Each row: player names (Doubles rows show both partners as "Name & Partner"), games won, per-game scores, date, duration
- Swipe to delete individual records
- "Clear All" button with confirmation
- **Filter by player** — multi-select picker (hidden if only one player in history); a record only matches once every selected player participated, on either team, in any combination — so picking two specific doubles partners finds the exact match they played together. Tapping "All Players" clears the selection and dismisses immediately; picking specific players stays open (checkmarks toggle) until "Done" is tapped
- **Filter by date range** — All Time / This Week / This Month
- **Filter by match type** — All / Singles / Doubles (hidden unless history contains both types)
- **Sort** — toggle button switches between Newest first (default) and Oldest first

### Player Stats
- Win rate, total matches, win/loss streak per player
- Filtered to the configured "Me" player
- **Head-to-Head** section listing W–L record against each opponent in history
- Doubles matches count for both partners individually — each partner appears as their own selectable player and as their own head-to-head opponent entry (a teammate is never counted as an opponent)

### Pre-Match (opponent picker)
- Roster rows show H2H record (`XW – YL`) against the near-side player when picking an opponent; hidden if no prior matches exist

### Settings
- **Me** section — single tappable row showing avatar + name; opens Player Edit
- **Players** section — roster list; tap to edit, swipe to delete
- **Game Mode** — Singles / Doubles; Doubles switches Pre-Match to the 4-player flow, the Game screen to two-name team tiles, and Match History rows to "Name & Partner" per team
- **Match Format** — Points to win (11 / 15 / 21), Games in match (1 / 3 / 5)
- **Match Timer** — toggle on/off; when enabled, duration stepper (±1 min, ±5 min buttons; min 1, max 99, default 10)
- **Court Theme** — Green / Blue / Red / Purple / Black
- **Digital Crown** — toggle crown scoring on/off (default on); off prevents accidental scoring from wrist movement
- **Score Announcement** — toggle spoken score via `AVSpeechSynthesizer`
- **Sound Effects** — toggle programmatic tones
- **Controls** — permanent gesture reference screen (tap, crown directions, undo)

---

## Monetization

Hybrid model: free app + banner ads (iOS only) + one-time StoreKit 2 in-app purchases. Core scoring, history, roster, and clubs stay free forever (the local-first invariant); everything gated is additive polish.

**Products** (all non-consumable; a purchase on either device unlocks both — entitlements come from `Transaction.currentEntitlements`, never synced through iCloud):

| Product | ID | Grants |
|---|---|---|
| Badminton Pro | `ritsuma.badminton.pro` | Removes ads + everything below |
| Court Theme Pack | `ritsuma.badminton.pack.themes` | Premium court themes |
| Avatar Pack | `ritsuma.badminton.pack.avatars` | Premium avatar images/icons |

**What's gated:**

- **Advanced stats (Pro):** best-streak and the Head-to-Head section on both Stats screens show a lock row that opens the paywall. Matches/wins/losses/win rate/avg points/duration stay free
- **Premium themes (Pro or Theme Pack):** Red/Purple/Black court themes. The Watch's theme picker shows lock badges and snaps back to the last free theme (opening the paywall); Game screens fall back to Green at render time if the entitlement lapses — the stored setting is never overwritten
- **Premium avatars (Pro or Avatar Pack):** all but 5 avatar images and 4 sport icons. Editor grids show lock badges → paywall; the Watch's pre-match quick-add simply offers the free subset. Already-assigned premium avatars keep rendering regardless
- **Banner ads (iOS only, removed by Pro):** a 320×50 AdMob banner at the bottom of the iPhone menu, Match History, and Stats screens — never during live scoring, never on the Watch. First display runs the Google UMP consent flow, then the App Tracking Transparency prompt (denial = non-personalized ads). Shipping TODO: Info.plist `GADApplicationIdentifier` and the ad-unit ID in `AdBannerView.swift` are Google's public test ids until real AdMob ids exist

**Paywall:** reachable from Settings on both platforms (row hidden once Pro is owned) and from every lock badge. Lists the three products with live App Store prices and a Restore Purchases button. `Badminton.storekit` at the repo root enables local purchase testing in Xcode (select it under Scheme → Run → Options → StoreKit Configuration).

**App Store Connect TODO before release:** Paid Apps agreement, create the three IAPs with the exact product IDs above, localized product names/descriptions, price tiers; AdMob account + real app/ad-unit ids; privacy nutrition labels updated for ads/tracking.

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
- New players can be created from either the pre-match picker or Settings, with color and icon selection available at creation time
- **"Me" player** — stored in roster like any other player; shown under "Me" section in Settings, hidden from the Players list
- Duplicate names are rejected when renaming (alert shown)
- Renaming a player propagates to all match history records that reference their `UUID`
- Players can be sorted by created order, name, most played, recently used, or pinned priority from Settings and the pre-match picker
- **Clubs (Roadmap Phase 5d)** — an opt-in local grouping of players/history, entered from Settings (Watch) or the main menu (iOS): create/rename a club, view its member list (shows "You" always; other members appear once CloudKit sync is on and the club has been shared), and view/manage its roster by tagging a player with the club from the player editor's "Club" picker (default "Personal"). Deleting a club you own, or leaving one shared to you, never deletes players or match history — it only clears their club tag back to Personal
- **Club invites (Roadmap Phase 5e, iOS-only)** — a club's owner can tap "Invite…" in its member list (shown only when CloudKit sync is on) to send a `CKShare` invitation via the system share sheet (`UICloudSharingController`); no watchOS equivalent exists
- **Club switcher in History/Stats (Roadmap Phase 5f)** — both screens gain a club scope filter (Personal + each joined club, hidden entirely if no clubs exist) that filters history/roster by `clubId` before any stats math runs; selection is per-session (not persisted). Watch uses a filter button + sheet (History) / inline `Picker` (Stats) since `Menu` is unavailable on watchOS; iOS uses a toolbar `Menu`
- **Club standings (Roadmap Phase 5 backlog, #159)** — `ClubDetailView` (both targets) shows a per-club leaderboard (name, wins-losses) sorted by win rate then wins
- **Match confirmation (Roadmap Phase 5 backlog, #160)** — a club owner can require matches to be confirmed before they count toward standings (default off, invisible for personal matches). Pending matches show in a Pending Confirmation section on `ClubDetailView` with Confirm/Decline actions; declining returns the match to Personal rather than deleting it
- **Tag a new match with a club (Roadmap Phase 5 backlog, #169)** — `PreMatchView` (both targets) offers the same "Club" picker (default "Personal") on its near-side player step, hidden entirely for a solo user with no clubs; the selection is threaded into the saved `MatchRecord.clubId`, making club standings (#159) and match confirmation (#160) reachable through normal play
- **Reactions & comments on a club match (Roadmap Phase 5 backlog, #164)** — each club activity-feed entry supports emoji reactions (👍 🔥 🏸 😮; tap to toggle, one per member per emoji) and one-line comments (≤200 chars). Watch: the feed row shows a count summary and pushes a detail screen with emoji toggling and a read-only comment list; iOS: emoji chips sit inline on the row, and a comment sheet lets comments be composed (real keyboard — the Watch never authors comments, only reads them). Stored as `ReactionRecord`s in the club's CloudKit zone, CloudKit-only like challenges: authoring needs CloudKit sync on plus a resolved CKShare identity, otherwise the controls are disabled. Reactions on a deleted match/club become invisible orphans (reads join on `clubId`+`matchId`) and are never purged or resurrected. A new reaction from a clubmate also lights the club's unread-activity dot
- **Friends invite link (Roadmap Phase 7d, iOS-only)** — a `badminton://addfriend?id=<participantId>&name=<name>` deep link lets two people connect without sharing a club. Opening one on iPhone presents a confirmation sheet naming the inviter; nothing is sent until the user taps "Send Friend Request" (which requires CloudKit sync on — otherwise the sheet explains how to enable it, with no send button). Confirming publishes the sender's public `FriendProfile` and writes a `FriendRequest` to CloudKit's public database; self-invites and duplicate pending requests are rejected with a specific message. The Watch does not consume this link (its `badminton://` handler remains the `newmatch` complication deep link)
- **Friends screen (Roadmap Phase 7e, both targets)** — a Friends entry point (next to Clubs, iOS shows a numeric badge for unread incoming requests) opens a list of incoming pending requests (Accept/Decline), outgoing pending requests (Cancel), and the current friends list. An "Add Friend" row shares the user's own invite link via the system share sheet (`ShareLink`) — works on both iPhone and Watch, since a friend invite is just a URL with no CKShare/keyboard involved. A second "Enter a Code" row (Roadmap Phase 7f) is a fallback for when the link doesn't transfer cleanly: paste either the full invite link or just the bare code, and the app looks up that player's profile before sending the request, showing a clear error if no such player exists. Incoming requests can also arrive via a best-effort silent push (Roadmap Phase 7f) — if it doesn't fire, the existing poll-on-appear/pull-to-refresh still catches it. The first time the screen (or the invite-link confirmation sheet) needs a display name, it prompts for one and saves it as the name shown to other players going forward. Requests refresh on appear (iOS also supports pull-to-refresh); like the invite link, everything here requires CloudKit sync on

---

## Match History Storage

- `MatchRecord` fields: `id`, `games: [GameScore]`, `myGamesWon`, `opponentGamesWon`, `winner`, `myName`, `opponentName`, `date`, `duration`, `myPlayerId: UUID?`, `opponentPlayerId: UUID?`, `myPartnerName: String?`, `opponentPartnerName: String?`, `myPartnerPlayerId: UUID?`, `opponentPartnerPlayerId: UUID?`. The four partner fields are populated for Doubles matches (`nil` for Singles) and rendered by the Game screen, roster, Match History, and Player Stats screens. `isDoubles` (computed: either partner field non-nil) is the single home of that check — used by Match History's match-type filter
- Player IDs are stored at match-save time by looking up names in the current roster
- Old records without IDs fall back to stored name strings
- When a player is renamed, all history records referencing their ID are updated
- CloudKit sync is per-record: a new match recorded on either device upserts its own `CKRecord`; deleting a match or clearing history enqueues real per-record deletes (no blob merge / overwrite heuristic)

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

The default local-player name ("Me") and the two guest labels offered during player selection are fully localized. These strings double as identity markers (a guest selection must never be saved to the roster), so every screen reads them from a single shared source (`Player.defaultMyName`/`.guestNearLabel`/`.guestFarLabel`) rather than each hardcoding its own copy — otherwise a guest chosen in one locale's label could fail the "is this a guest" check.

---

## Accessibility

- **VoiceOver** — custom controls carry spoken labels:
  - Each score tile reads the player, current score, and (while serving) the service court as one element, with a "double tap to add a point" hint and the button trait.
  - The games-won readout, the undo button, and the match-timer countdown have dedicated labels.
  - Purely decorative imagery (avatars beside names, timer/trophy icons) is hidden from VoiceOver to avoid redundant elements.
- All accessibility strings are localized in every supported language (`a11y.*` keys in `Localizable.strings`).

---

## Open Issues

Architectural issues are sequenced in [ROADMAP.md](ROADMAP.md).

| # | Feature |
|---|---------|
| 93 | Product/multi-user strategy epic — concretized by ROADMAP.md |
| 163 | Club seasons: time-boxed standings resets — Roadmap Phase 5 backlog |
| 165 | Push notifications for async club interactions — Roadmap Phase 5 backlog |

---

## Closed Issues

| # | Feature | PR |
|---|---|---|
| 109 | Migrate history sync to CloudKit private database (Roadmap Phase 4) — CloudKit is now the only sync path, KV store retired | #129, #130, #141, #183 |
| 41 | iPhone companion app — history, stats, roster, share, and live scoring (Roadmap Phase 6) | #133, #135, #136, #137, #138, #139 |
| 13 | Share match result as an image/summary card (iPhone) | #138 |
| 5 | Match Timer mode | #42 |
| 6 | App icon | #38 |
| 7 | Character selection per opponent | closed (roster system covers this) |
| 10 | Match history: save and browse past matches | closed (implemented — History screen) |
| 11 | Player stats: win rate, average points, longest streak | closed (implemented — Stats screen) |
| 14 | Sound effects | #37 |
| 15 | Dark/light mode toggle | closed (Apple Watch is always dark) |
| 16 | Undo last point | #2 |
| 17 | Court color themes | #21 |
| 18 | Custom player names with avatar | #34, #36, #39 |
| 49 | Reselect who serves between games | #53 |
| 57 | iCloud sync / data backup | #75 |
| 88 | Decouple player display name from stored identity | #91 |
| 96 | Extract GameView business logic into a testable view model (Roadmap Phase 2) | #113 |
| 106 | Extract shared `BadmintonCore` Swift package (Roadmap Phase 1) | #112 |
| 107 | Schema versioning, tolerant decoding, migration hook (Roadmap Phase 3) | #114 |
| 108 | Locale-independent player identity: guest tokens + stable "Me" id (Roadmap Phase 3) | #115 |
| 110 | CI guardrails: localization key-sync, coverage, Complication build, deployment-target alignment (Roadmap guardrails track) | #116 |
| 87 | iCloud KV sync quota guard: surface/log quota-exceeded, warn before the ~1 MB ceiling (merge-by-id landed earlier) | #117 |
| 8 | Doubles support (2v2) | #118, #120, #121, #122, #123 |
| 148 | Club management UI: create/rename/leave, member list, per-club roster (Roadmap Phase 5d) | #149 |
| 157 | Club switcher in History/Stats (Roadmap Phase 5f) | #158 |
| 155 | Club invite UI: CKShare invite via UICloudSharingController, iOS-only (Roadmap Phase 5e) | #156 |
| 159 | Club standings / leaderboard (Roadmap Phase 5 backlog) | #167 |
| 160 | Match confirmation: per-club admin toggle before a match counts toward standings (Roadmap Phase 5 backlog) | #168 |
| 169 | Club picker in PreMatchView so matches actually get tagged with clubId (Roadmap Phase 5 backlog) | #170 |
| 161 | Club activity feed: chronological recent results with per-club unread marker (Roadmap Phase 5 backlog) | #172 |
| 162 | Club challenges: "want to play?" ping between members (Roadmap Phase 5 backlog) | #173 |
| 164 | Reactions / comments on a club match (Roadmap Phase 5 backlog) | #174 |
