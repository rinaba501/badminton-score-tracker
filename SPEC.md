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
- **Match History and Stats are on iPhone.** A dashboard-style home screen (quick-stats strip: matches / win rate / players — each cell navigates to History/Stats/Players respectively — plus a prominent New Match button, and a "last match" card below the menu once at least one match exists) links to a full Match History (date-range / match-type / sort / multi-player filters, avatar'd rows, swipe-to-delete, clear-all) and a Stats screen (win-rate ring, stat cards, head-to-head with avatars) — the same information and derivations as the Watch, restyled for the phone. Deleting a match on iPhone removes it everywhere via iCloud.
- **My Profile is its own page on iPhone**, reached from the home menu: edit your own name/avatar and link/unlink the device's CloudKit account, separate from the shared roster of other players. Renaming yourself here updates your name in every past match. iOS only — watchOS keeps "Me" as a distinguished row inside Settings/Roster since the small screen doesn't warrant another top-level destination.
- **Roster management is on iPhone** (with a real keyboard): add / rename / delete saved players, choose the roster sort order, and pick an avatar color, image, or icon for them. Renaming a player updates their name in every past match. Changes sync to the Watch via iCloud.
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
Two-step flow in Singles mode, four-step in Doubles mode on the Watch (see Settings → Game Mode):
1. **Near Side** — pick yourself or a roster player or a guest; also offers the Club picker (default "Personal", hidden if the user has no clubs)
2. **Near Partner** (Doubles only) — pick your teammate; excludes the Near Side pick
3. **Far Side** — pick opponent; excludes everyone already picked on the near team
4. **Far Partner** (Doubles only) — pick the opponent's teammate; excludes everyone already picked; selecting starts the match

**iOS diverges here:** the phone's screen fits a side's player and partner on one screen instead of pushing a separate screen per pick. Picking the side's player swaps the same list in place to prompt for the partner (a summary banner keeps the already-picked player visible, tap it to change), so Doubles is Near Side → Far Side (2 screens) rather than the Watch's 4. Same exclusion rules, same Club/Friends scoping, same guest-token draw.

**Roster scoping by Club** — the "Saved" roster list is scoped to whichever Club is selected on the Near Side step (Personal shows only `clubId == nil` players; a Club shows only that club's members), for every step of the flow, not just Near Side. A quick-added player (the "+" sheet, or the full Player Editor) is tagged with the currently-selected club, so a player added while a club match is being set up shows up as a club member next time, not a Personal player invisible from club matches. **Friends section** — when Personal is selected, an additional "Friends" section lists accepted friends (from `AppStore.friends`) as selectable opponents/partners alongside the Saved roster; hidden for club matches and hidden entirely if the user has no friends.

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
- **Match-over overlay** — shows trophy, winner name (both partners’ names in Doubles), games score, a primary "Done" button that saves nothing extra (the match is already recorded) and exits, and a secondary "Rematch" button
- **Exit button** — the toolbar button reads "End" while a match is live (tapping asks to confirm discarding the score) and "Done" once the match is over or hasn’t started (tapping exits immediately); winner banners read "Game to X!" / "Match to X!" so team names stay grammatical
- **Score Screen Style (iOS only)** — 8 selectable visual styles for the live scoring screen: Depth (gradient/glass tiles, theme-driven accents — closest to the original layout; the serving tile is marked in solid white — 3pt border + soft glow + a white court-label chip — rather than the theme tint, which doesn't read against the tinted glass), Split (full-bleed diagonal split-screen; the currently-serving side's field takes the Court Theme color plus a pulsing red edge-light and serve dot, the other side stays neutral; scores carry a deep layered drop shadow and spring-animate on change), Minimal (flat two-row layout, hairline divider, restrained theme-tinted accent, subtle theme-tinted background wash), Blackbird (broadcast-style scorebar on a black field; serve is a shape marker, not a color — dimmed rather than hidden on the non-serving side — with a thin theme-colored edge-light; the screen splits into two equal halves at the scorebar's divider and tapping anywhere in a half scores that side, flashing the half to confirm), Matchstick (skeuomorphic retro LED gym scoreboard — glowing digits over a dim ghost digit, lit "SERVE" lamp per side, games-won as lamp dots), Birds-Eye (top-down court-diagram background; the serve marker sits in the correct service court per real serving rules, games-won as baseline tally marks), Tug (kinetic style — the divider between sides drags toward whoever's ahead and numerals spring-animate on each point; respects Reduce Motion), Scoreboard (the manual courtside flip-card scoreboard — cards on binder rings with a hinge seam, a small games-won card beside each score card, name plate under each stack, theme-colored plates and base rail; each point swings the card off its top hinge, skipped under Reduce Motion; serve is a lamp on the serving side's plate. **The app's one landscape style**: entering a match with Scoreboard active rotates the game screen to landscape and exiting restores portrait — every other screen stays portrait-only. Home/"me" team sits left, visitor right). Free for everyone, no Pro gating. The Watch's Game Screen is unaffected — it has its own layout and no style picker

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
- **"Me" is selectable in any slot** — near-side player, near partner, far side, or far partner — not just the near-side default. A pinned "Me" shortcut (with the same checkmark-seal badge Clubs uses) appears on every step you haven't already been placed in this match; once picked in one slot, it's excluded from the rest, same as any other player

### Settings
- **Me** section — single tappable row showing avatar + name; opens Player Edit
- **Players** section — roster list; tap to edit, swipe to delete
- **Game Mode** — Singles / Doubles; Doubles switches Pre-Match to the 4-player flow, the Game screen to two-name team tiles, and Match History rows to "Name & Partner" per team
- **Match Format** — Points to win (11 / 15 / 21), Games in match (1 / 3 / 5)
- **Match Timer** — toggle on/off; when enabled, duration stepper (±1 min, ±5 min buttons; min 1, max 99, default 10)
- **Court Theme** — Green / Blue / Red / Purple / Black
- **Score Screen Style** — Depth / Split / Minimal / Blackbird / Matchstick / Birds-Eye / Tug / Scoreboard (see Game Screen above; Scoreboard is landscape-only). **iOS-only** — no equivalent on Watch
- **Digital Crown** — toggle crown scoring on/off (default on); off prevents accidental scoring from wrist movement. **Watch-only** — no Digital Crown on iPhone, so this row doesn't exist on iOS
- **Score Announcement** — toggle spoken score via `AVSpeechSynthesizer`
- **Sound Effects** — toggle programmatic tones
- **Controls** — permanent gesture reference screen (tap, crown directions, undo). **Watch-only** — the hints are Digital Crown gestures, so there's no iOS equivalent

iOS Settings mirrors all of the above except Digital Crown and Controls (both scoring-input hints tied to Watch hardware), and additionally includes the iOS-only Score Screen Style picker (no Watch equivalent). Roster, Clubs, and Friends management live as their own rows on iOS's main menu instead of nesting under Settings, since iOS navigation is push-based rather than Settings-as-hub.

---

## Monetization

Hybrid model: free app + banner ads (iOS only) + one-time StoreKit 2 in-app purchases. Core scoring, history, roster, and clubs stay free forever (the local-first invariant); everything gated is additive polish.

**Products** (all non-consumable; a purchase on either device unlocks both — entitlements come from `Transaction.currentEntitlements`, never synced through iCloud):

| Product | ID | Grants |
|---|---|---|
| Featherkeep Pro | `ritsuma.badminton.pro` | Removes ads + everything below |
| Court Theme Pack | `ritsuma.badminton.pack.themes` | Premium court themes |
| Avatar Pack | `ritsuma.badminton.pack.avatars` | Premium avatar images/icons |

**What's gated:**

- **Advanced stats (Pro):** best-streak and the Head-to-Head section on both Stats screens show a lock row that opens the paywall. Matches/wins/losses/win rate/avg points/duration stay free
- **Premium themes (Pro or Theme Pack):** Red/Black court themes. The Watch's theme picker shows lock badges and snaps back to the last free theme (opening the paywall); Game screens fall back to Green at render time if the entitlement lapses — the stored setting is never overwritten
- **Premium avatars (Pro or Avatar Pack):** all but 11 avatar images and 7 sport icons. Editor grids show lock badges → paywall; the Watch's pre-match quick-add simply offers the free subset. Already-assigned premium avatars keep rendering regardless
- **Banner ads (iOS only, removed by Pro):** a 320×50 AdMob banner at the bottom of the iPhone menu, Match History, and Stats screens — never during live scoring, never on the Watch. First display runs the Google UMP consent flow, then the App Tracking Transparency prompt (denial = non-personalized ads). Shipping TODO: Info.plist `GADApplicationIdentifier` and the ad-unit ID in `AdBannerView.swift` are Google's public test ids until real AdMob ids exist

**Paywall:** reachable from Settings on both platforms and from every lock badge. The Settings row is always visible and carries a plan capsule badge — yellow "Pro" once Pro is owned, gray "Free" otherwise — so the current plan is checkable at a glance. Lists the three products with live App Store prices and a Restore Purchases button. `Badminton.storekit` at the repo root enables local purchase testing in Xcode (select it under Scheme → Run → Options → StoreKit Configuration).

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
- New players can be created from either the pre-match picker or Settings, with color and icon selection available at creation time; the editor pre-fills a randomized color + icon (`Player.randomDefaultAppearance()`, free-catalog only) so a player saved without touching the pickers still looks visually distinct, and reopening the add-player sheet without saving re-randomizes rather than repeating the same suggestion
- **"Me" player** — stored in roster like any other player; shown under "Me" section in Settings, hidden from the Players list
- Duplicate names are rejected when renaming (alert shown)
- Renaming a player propagates to all match history records that reference their `UUID`
- Players can be sorted by created order, name, most played, recently used, or pinned priority from Settings and the pre-match picker
- **Clubs (Roadmap Phase 5d)** — an opt-in local grouping of players/history, entered from Settings (Watch) or the main menu (iOS): create/rename a club, view its member list (shows "You" always; other members appear once CloudKit sync is on and the club has been shared), and view/manage its roster by tagging a player with the club from the player editor's "Club" picker (default "Personal"). Deleting a club you own, or leaving one shared to you, never deletes players or match history — it only clears their club tag back to Personal
- **Club invites (Roadmap Phase 5e, iOS-only)** — a club's owner can tap "Invite…" in its member list (shown only when CloudKit sync is on) to send a `CKShare` invitation via the system share sheet (`UICloudSharingController`); no watchOS equivalent exists
- **Club switcher in History/Stats (Roadmap Phase 5f)** — both screens gain a club scope filter (Personal + each joined club, hidden entirely if no clubs exist) that filters history/roster by `clubId` before any stats math runs; selection is per-session (not persisted). Watch uses a filter button + sheet (History) / inline `Picker` (Stats) since `Menu` is unavailable on watchOS; iOS uses a toolbar `Menu`. Since a club scope can show matches recorded by other members (`record.myName` isn't necessarily you), History's match rows carry the same small "you" badge as `ClubDetailView`'s Activity feed, next to whichever side's name matches your own
- **Club standings (Roadmap Phase 5 backlog, #159)** — `ClubDetailView` (both targets) shows a per-club leaderboard (name, wins-losses) sorted by win rate then wins; your own entry (your row in the Members section, and whichever side of an Activity feed row is you) all carry a small "you" badge instead of a separate label, so your name reads like everyone else's. Every Members/Standings/Activity/Friends row also shows an avatar circle next to the name — your own and any club opponent with a saved roster entry show their actual customized avatar, everyone else falls back to plain initials on gray (friends and CKShare-only members aren't local roster entries with a saved color/icon)
- **Match confirmation (Roadmap Phase 5 backlog, #160)** — a club owner can require matches to be confirmed before they count toward standings (default off, invisible for personal matches). Pending matches show in a Pending Confirmation section on `ClubDetailView` with Confirm/Decline actions; declining returns the match to Personal rather than deleting it
- **Tag a new match with a club (Roadmap Phase 5 backlog, #169)** — `PreMatchView` (both targets) offers the same "Club" picker (default "Personal") on its near-side player step, hidden entirely for a solo user with no clubs; the selection is threaded into the saved `MatchRecord.clubId`, making club standings (#159) and match confirmation (#160) reachable through normal play
- **Club seasons (Roadmap Phase 5 backlog, #163)** — a club owner (iOS-only editing, `ClubDetailView`) can set an optional Season window (a start date, plus an independently optional end date). When set, the Standings section only counts matches recorded within that window (inclusive; no end date means open-ended); the Activity Feed is unaffected — it stays a full chronological log regardless of season. No season set (the default) leaves standings exactly as before. The Standings section shows a read-only "Season: `<start>` – `<end/present>`" label whenever one is active, visible to owner and non-owner alike; Watch shows the same read-only label but has no editing controls, matching the existing DatePicker-editing-is-iOS-only precedent (birthday, introduction)
- **Reactions & comments on a club match (Roadmap Phase 5 backlog, #164)** — each club activity-feed entry supports emoji reactions (👍 🔥 🏸 😮; tap to toggle, one per member per emoji) and one-line comments (≤200 chars). Every activity row shows the exact per-game score (e.g. "21-18, 15-21, 21-19"), not just the games-won tally — same format History's per-game line uses. Watch: the feed row shows a count summary and pushes a detail screen with emoji toggling and a read-only comment list; iOS: emoji chips sit inline on the row, and a comment sheet lets comments be composed (real keyboard — the Watch never authors comments, only reads them). Stored as `ReactionRecord`s in the club's CloudKit zone, CloudKit-only like challenges: authoring needs CloudKit sync on plus a resolved CKShare identity, otherwise the controls are disabled. Reactions on a deleted match/club become invisible orphans (reads join on `clubId`+`matchId`) and are never purged or resurrected. A new reaction from a clubmate also lights the club's unread-activity dot
- **Friends invite link (Roadmap Phase 7d, iOS-only)** — a `badminton://addfriend?id=<participantId>&name=<name>` deep link lets two people connect without sharing a club. Opening one on iPhone presents a confirmation sheet naming the inviter; nothing is sent until the user taps "Send Friend Request" (which requires CloudKit sync on — otherwise the sheet explains how to enable it, with no send button). Confirming publishes the sender's public `FriendProfile` and writes a `FriendRequest` to CloudKit's public database; self-invites and duplicate pending requests are rejected with a specific message. The Watch does not consume this link (its `badminton://` handler remains the `newmatch` complication deep link)
- **Friends screen (Roadmap Phase 7e, both targets)** — a Friends entry point (next to Clubs, iOS shows a numeric badge for unread incoming requests) opens a list of incoming pending requests (Accept/Decline), outgoing pending requests (Cancel), and the current friends list. An "Add Friend" row shares the user's own invite link via the system share sheet (`ShareLink`) — works on both iPhone and Watch, since a friend invite is just a URL with no CKShare/keyboard involved. A second "Enter a Code" row (Roadmap Phase 7f) is a fallback for when the link doesn't transfer cleanly: paste either the full invite link or just the bare code, and the app looks up that player's profile before sending the request, showing a clear error if no such player exists. Incoming requests can also arrive via a best-effort silent push (Roadmap Phase 7f) — if it doesn't fire, the existing poll-on-appear/pull-to-refresh still catches it. Friends always shows/sends your existing scoring name ("Me" in Settings/Roster) — there's no separate name to set up first. Requests refresh on appear (iOS also supports pull-to-refresh); like the invite link, everything here requires CloudKit sync on
- **Ask for a name before it's shared with anyone** — the first time either app launches, it asks "what should other players call you?" (skippable, since the app must always work with zero setup); the answer becomes the same name used for scoring, Friends, and Clubs. Anyone who skips isn't blocked from using Friends or Clubs, but gets a lighter one-time-per-visit nudge instead — Friends opens the same prompt before publishing a profile or sending a request, and a Club screen opens it passively on first visit without blocking the rest of the screen. Whatever's typed doesn't have to be a real/legal name — just something other than the default placeholder
- **Cross-device sync of club unread markers** — each club's "last viewed activity" marker syncs across your own devices (via the personal-zone Settings record), so clearing a club's unread dot on one device clears it on the others. Markers merge (the most-recent view wins per club) rather than overwrite, so a device that's been offline can't re-raise a dot you already cleared
- **Link this device to one account (Roadmap Phase 7g)** — Friends has an explicit "Account" section: an unlinked device shows a "Link This Device" button; once linked, it shows "Linked as `<name>`" (your scoring name) plus an "Unlink" button. Linking is a single opt-in flag (zero or one linked account, never more) that syncs across your own devices; unlinking is non-destructive — it never deletes your Friends profile, removes friends, or leaves clubs, it only detaches the flag (re-linking restores it). Every club member (including you) gets a small friend badge if they're already one of your accepted Friends (Club and Friends identities resolve to the same underlying CloudKit account, so this is a simple cross-reference, no new invite/permission needed)
- **Share your profile with friends, field by field** — a "Sharing Settings" row at the bottom of Friends (both targets, grouped with "Friend Activity" under a trailing "More" section since neither is a day-to-day action) opens a dedicated screen with six independent toggles, each on/off: avatar, gender, birthday, "about me" bio, stats (win rate/games played/head-to-head), and match history — so you can, say, share your win rate with friends without exposing every match. All default off; your name is the one thing that's never toggle-gated, since an accepted friend already learned it the moment they accepted. Gender/birthday/bio are edited on iOS only (ProfileView — ID/DatePicker/a 200-char bio field), same iOS-only-authoring precedent as club match comments; identity/stats are precomputed snapshots (not raw match records), so turning on Stats never exposes your actual games unless History is also on. Turning any toggle on identity-shares the same dedicated `CKShare` zone to every accepted friend (not a joinable link, unlike Club invites) and stays in sync as the friend graph changes; turning off the *last* remaining toggle strips every participant. A friend's shared data is never merged into your own — it's shown read-only in a "Friend Activity" list (tap a friend's name to see whichever of their identity/stats/history they've actually shared, reusing the same match-row formatting as your own History screen for the history part). On iOS, the avatar/gender/birthday/bio toggles are also reachable inline: a small share icon sits right next to each field in Profile, so the decision can be made the moment that field is filled in, not just from the dedicated Sharing Settings screen. Since the icon has no visible text, tapping it briefly shows a "Shared with friends"/"No longer shared with friends" toast so the effect is unambiguous. History and Stats get the same inline treatment, since match history/stats have no natural field to sit next to in Profile: iOS History shows a full "Share My History with Friends" switch (with its explanatory footer) at the top of the list whenever you're viewing your personal matches, and iOS Stats shows the same icon-only toggle + toast as Profile's fields whenever you're viewing your own personal stats

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
| Undo | `.directionUp` | 660→440 Hz descending |
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

The default local-player name ("Me") and the guest labels offered during player selection are fully localized. Guests are randomly assigned one of 6 bird names (e.g. "Guest Falcon"), drawn without replacement per match so up to 4 guest slots (near/far solo + partner) never collide; a picker's guest button shows a generic "Guest" label until the specific name is drawn at tap time. These strings double as identity markers (a guest selection must never be saved to the roster, and never becomes a selectable filter/head-to-head subject in History or Stats), so every screen reads them from a single shared source (`Player.defaultMyName`/`Player.guestTokens`/`Player.displayName(for:)`) rather than each hardcoding its own copy — otherwise a guest chosen in one locale's label could fail the "is this a guest" check. For the same reason a guest's avatar is a fixed bird glyph rather than initials derived from their label (which would read as "GF" in English and differently in every other locale); their per-token color is what tells two guests apart.

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
| 165 | Push notifications for async club interactions — Roadmap Phase 5 backlog |

---

## Closed Issues

| # | Feature | PR |
|---|---|---|
| 163 | Club seasons: time-boxed standings resets — Roadmap Phase 5 backlog | #PLACEHOLDER |
| 252 | New "Scoreboard" Score Screen Style (8th): manual courtside flip-card scoreboard — hinge-seam cards on binder rings, games mini-card, card-flip on each point (Reduce Motion aware) — and the app's first landscape screen, via an app-wide orientation lock GameView flips on entry/exit (AppDelegate.setOrientation) | #253 |
| 239 | iOS Settings: Court Theme and Score Screen Style pickers were plain `Picker`s, which flatten custom label views (color swatches, thumbnails) into text-only UIMenu rows on iOS; replaced with pushed `CourtThemePickerView`/`GameScreenStylePickerView` screens showing a color swatch per theme and a small static mockup per one of the 7 score-screen styles, with existing lock/paywall gating preserved | #251 |
| 249 | iOS home screen: stats strip's three co-located NavigationLinks (Matches/Win rate/Players) mis-routed taps to the wrong sibling's destination; replaced with Buttons driving a single `.navigationDestination(item:)` | #250 |
| 238 | iOS Stats screen: grid's Wins/Losses cards (duplicated the header's W-L headline) replaced with Current Streak and a Singles/Doubles split; Avg Duration folded into the header instead of an odd 5th full-width card; Head-to-Head paywall CTA restyled from a full-width accent button to the gold/crown Pro identity Settings already uses | #248 |
| 240 | iOS polish: Friends/Club-detail empty sections use `ContentUnavailableView`; dropped duplicate title+header labels (Players, Friends, home screen's "Match History" row vs. now-"Latest Match" card header); About Me gets a bordered card + placeholder, club-name field a rounded border, "Require Match Confirmation" a footer | #247 |
| 237 | iOS History screen: sort + clear-all folded into one trailing "…" menu (down from 4 icon-only toolbar buttons) so the "Match History" title has room; MatchHistoryRow team-name Text now wraps to 2 lines instead of truncating doubles pairings | #246 |
| 236 | iOS player-row Buttons (Players, New Match, Club roster) now use `.buttonStyle(.plain)` so the default automatic button style stops overriding each row's explicit primary-color name text with the accent tint | #245 |
| 235 | Game screen exit flow: toolbar button reads "End" during play / "Done" after; match-over overlay gains a primary Done exit with Rematch demoted to secondary; English winner banners recast as "Game/Match to X!" for team grammar (both targets) | #241 |
| 223 | iOS Match History: sort order moved to a toolbar menu and the share-with-friends toggle merged into the filter section with its footer dropped, so the first match row sits higher on tall screens | #230 |
| 222 | iOS home screen: stat strip cells (Matches/Win rate/Players) now navigate to History/Stats/Players; a "last match" card (reusing MatchHistoryRow) fills the dead space below the menu when history isn't empty | #229 |
| 221 | iOS Stats screen: balanced stat grid (avg duration as its own full-width card, no orphan cell), locked cards show a redacted placeholder value instead of an empty lock, unlock row uses a solid-tint pill for contrast | #228 |
| 220 | iOS pre-match player list: primary-color names with the accent reserved for the pinned "you" row; guest avatars use a bird glyph, not locale-derived initials | #227 |
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
