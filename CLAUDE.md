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
- **Sync:** CloudKit only (`CKSyncEngine` on both targets; container `iCloud.ritsuma.badminton-score-tracker`) — one record per match/player/club + fixed personal-zone `Settings` (`SettingsSnapshot`: every scalar setting). No KV store, no `cloudKitSyncEnabled` flag; engines start on launch. Correctness is not CI-provable — needs a two-device iCloud test
- **Health:** `HKWorkoutSession` + `HKLiveWorkoutBuilder` (HealthKit capability + usage descriptions in Info.plist)

## Project Structure

```
BadmintonCore/                 — local Swift package; platform-free core (no SwiftUI/WatchKit imports, ever)
  Sources/BadmintonCore/
    MatchModel.swift          — BadmintonMatch (pure scoring engine — no UI/timers/player identity), GameScore, MatchRecord, Side (live-match perspective, `.me`/`.opponent`). MatchRecord.winner is `RecordSide` (`.near`/`.far` — distinct from `Side`, a persisted viewer-neutral tag, not a display-name copy); MatchRecord has a custom Codable init that self-migrates legacy `winner: String` records without a PersistenceStore schema-version bump (Roadmap Phase 5a, #93). MatchRecord.clubId: UUID? tags a record as belonging to a Club — nil (default) means personal, unchanged (Roadmap Phase 5b)
    PersistenceStore.swift    — all JSON encode/decode for [Player]/[MatchRecord]/[Club]/[ChallengeRecord]/[ReactionRecord]/[FriendRequest]/SettingsSnapshot; versioned envelope, per-record-tolerant decoding, migration hooks, plus single-record codecs + diff/conflict helpers for CloudKit (#109)
    SettingsSnapshot.swift    — every scalar setting synced as one personal-zone CloudKit Settings record (myName/localPlayerId/pointsToWin/gamesInMatch/courtTheme/announceScore/enableSounds/enableCrownScoring/timeModeEnabled/timeLimitMinutes)
    Player.swift              — Player model, SortOrder, sentinel identity (guest tokens vs. localized labels — see doc comments). Player.clubId: UUID? tags a roster entry as belonging to a Club — nil (default) means personal, unchanged (Roadmap Phase 5b)
    Club.swift                — Club model (id/name/createdDate, plus ownerRecordName: String? — Roadmap Phase 5c; nil means locally-owned, set when a club's zone is shared to us). Grouping tag for Player/MatchRecord via clubId; syncs via CloudKitSyncManager (private DB for owned clubs, shared DB once a CKShare zone exists — Phase 5c)
    ChallengeRecord.swift     — Roadmap Phase 5 backlog (#162): a "want to play?" ping between two club members, always tagged with a non-nil clubId. Unlike Club/Player/MatchRecord, fromParticipantId/toParticipantId identify real CKShare participants (CKShare.Participant.userIdentity.userRecordID.recordName), not roster Players — a Player has no Apple ID link. CloudKit-only (see AppStore.saveChallenges)
    ReactionRecord.swift      — Roadmap Phase 5 backlog (#164): an emoji reaction or one-line comment (kind + content) on a club match, authored by a CKShare participant (same identity model as ChallengeRecord). Links to its match by plain matchId — no CKRecord references. CloudKit-only (see AppStore.saveReactions); orphaned reactions after a match/club delete stay invisible, never purged
    FriendProfile.swift       — Friends v1 (graph-only, club-independent — see ROADMAP.md "Friends" initiative): a discoverable CloudKit **public**-database profile record so two people can find each other via an out-of-band invite link/code with no club/CKShare in common yet. participantId is a CKContainer.fetchUserRecordID() result (NOT a CKShare.Participant id like Challenge/ReactionRecord use). One profile per Apple ID, upserted by participantId. No local array cache — fetched on demand per participant
    FriendRequest.swift       — Friends v1: a friend request/graph edge between two people, independent of any Club. Structurally mirrors ChallengeRecord (fromParticipantId/toParticipantId/status/snapshotted display names) but has no clubId — lives in CloudKit's public database, not a club zone. No separate Friendship record: an accepted FriendRequest *is* the friendship edge. Accepting does NOT create a CKShare/zone or share match history — explicit non-goal of this phase, deferred to a future slice
    FriendInviteLink.swift    — Friends v1 (7d): pure build/parse of the `badminton://addfriend?id=<participantId>&name=<name>` invite link (name trimmed + capped at 50 chars on both build AND parse — the link is editable UGC). Parsing never triggers a network write; consumption always goes through a confirmation sheet (iOS FriendInviteView)
    StatsCalculator.swift     — pure stats/history derivations; intentionally duplicated function pairs — see file header before unifying anything
    AppStorageKeys.swift      — single source of truth for EVERY UserDefaults/@AppStorage key string
    Entitlements.swift        — monetization: ProductID constants + pure owned-product-IDs → features mapping (isPro/hasAllThemes/hasAllAvatars/showsAds; packs count as owned under Pro). StoreKit-free by design — each target's StoreManager feeds it; purchase state is per-Apple-ID via StoreKit, NEVER KV/CloudKit-synced (ownedProductIds key is a local launch cache only)
    ScoreCallFormatter.swift  — locale-aware spoken score formatting (en/ja/zh); injectable strings closure for tests
  Tests/BadmintonCoreTests/   — all core unit tests; run with `swift test --package-path BadmintonCore`

badminton score tracker Watch App/
  ContentView.swift          — root view; owns only the AppView routing enum (.menu/.preMatch/.game/.settings/.history/.stats — state-driven, no top-level NavigationLink)
  MenuView.swift             — main menu
  PreMatchView.swift         — player selection: 2 steps (Singles) or 4 steps (Doubles, reading SettingsView.GameMode); near-side step also offers a Club picker (default Personal, hidden if the user has no clubs — Phase 5 backlog, #169) whose selection is written to matchClubId and read by GameViewModel.saveMatch()
  GameView.swift             — live scoring screen, layout only; all logic delegates to GameViewModel. ScoreView renders one or two stacked names per team depending on whether a partner is present
  GameViewModel.swift        — @MainActor ObservableObject; owns all live-game logic: scoring, undo, time mode, haptics, persistence, announcements, doubles partner names/rotation display
  HapticsProvider.swift      — HapticsProvider protocol + Watch/NoOp implementations (tests use NoOp)
  StoreManager.swift         — StoreKit 2 plumbing (Transaction.updates listener, purchase/restore, entitlement refresh + UserDefaults cache); per-target copy pattern like HapticsProvider. Repo-root Badminton.storekit is the local-testing product config
  PaywallView.swift          — slim watch storefront (products + restore), presented as a sheet from Settings and every lock badge (StatsView lock rows, theme picker, PlayerEditView avatar grid)
  SettingsView.swift         — match format, audio, theme, timer, roster management, club management entry point (Phase 5d), Friends entry point (Phase 7e)
  HistoryView.swift          — saved match list + filters, incl. a club scope filter (Personal + joined clubs, Roadmap Phase 5f; sheet-based since `Menu` is unavailable on watchOS) that pre-filters by `clubId` before any StatsCalculator call
  StatsView.swift            — per-player stats + head-to-head (math lives in StatsCalculator); same club scope filter as HistoryView (Phase 5f), via an inline `Picker`
  PlayerEditView.swift       — single-player editor sheet; Phase 5d adds an optional club Picker (bound to Player.clubId) shown only when the caller passes a non-empty `clubs` list
  ClubsView.swift            — Phase 5d: club list + create, entered via a SettingsView section; pure UI over AppStore.saveClubs
  FriendsView.swift          — Friends v1 (Phase 7e): incoming/outgoing pending FriendRequests (accept/decline/cancel via CloudKitSyncManager.respondToFriendRequest), the friends list (AppStore.friends), and an add-friend ShareLink over FriendInviteLink.url — works on watchOS since a friend invite is just a URL, unlike Phase 5e's club invite (UICloudSharingController, UIKit-only). Also owns the one-time display-name prompt (myFriendsDisplayName), which FriendInviteView's roster-name fallback backstops for a deep link opened before this screen is ever visited. Phase 7f adds a second "Enter a Code" row: pastes either a full invite link (parsed via FriendInviteLink.parse) or a bare participantId, validated via CloudKitSyncManager.fetchProfile before sending. Entered via SettingsView
  ClubDetailView.swift       — Phase 5d: rename, member list (read live from CloudKitSyncManager.fetchOrCreateShare's CKShare.participants, falling back to "You" if the share fetch fails), and per-club roster (players filtered by clubId) for one Club; delete/leave clears clubId back to nil on that club's players/matches (never deletes them) then removes the club via the existing saveClubs diffing. Activity rows show a reaction-count caption and push MatchReactionsView (#164)
  MatchReactionsView.swift   — Phase 5 backlog (#164): emoji toggling + read-only comment list for one club match, pushed from a ClubDetailView activity row (comment authoring is iOS-only — no Watch keyboard)
  PlayerAvatar.swift         — app-side presentation extension of Player (colors/images/icons + AvatarView)
  AudioFeedback.swift        — ScoreAnnouncer (speech) + SoundPlayer (tones)
  CourtTheme.swift           — CourtTheme enum
  AppStore.swift             — @MainActor singleton; caches decoded roster/history/clubs, runs migrations on init, all writes go through it and enqueue to CloudKitSyncManager; owns localPlayerId ("Me" is never in the roster). saveRoster/saveHistory/clearHistory also enqueue the Settings record; applyRemoteSettings writes every scalar (ignores empty localPlayerId). Friends v1 (#7c): also caches friendRequests + a derived `friends` computed property (accepted requests only); saveFriendRequests is the one save* method that does NOT enqueue to CKSyncEngine — it only reconciles the local cache after a direct public-DB write or a fetchMyFriendRequests() poll
  WorkoutManager.swift       — HKWorkoutSession lifecycle (start on match begin, end on save/discard)
  CloudKitSyncManager.swift  — the only sync path: two CKSyncEngine instances (private DB for personal data + shared DB for accepted club zones). One CKRecord per match/player/club (opaque JSON payload; real per-record deletion) plus a fixed personal-zone Settings record. Each club gets its own `Club-<uuid>` zone (`Club.ownerRecordName` disambiguates owner private DB vs member shared DB). `fetchOrCreateShare`/`acceptShare` handle CKShare invites (WatchAppDelegate). Friends section talks to the public DB with plain save/fetch/query (not CKSyncEngine); Phase 7f adds best-effort FriendRequest push subscription. Starts on launch (idempotent); correctness NOT CI-provable — two-device test required
  badminton_score_trackerApp.swift — entry point; starts CloudKitSyncManager synchronously on the main actor, handles badminton://newmatch deep link. Installs WatchAppDelegate via @WKApplicationDelegateAdaptor (Roadmap Phase 5c, CKShare accept callback)
  WatchAppDelegate.swift     — WKApplicationDelegate; forwards userDidAcceptCloudKitShare(with:) to CloudKitSyncManager.acceptShare (Roadmap Phase 5c). Roadmap Phase 7f: registerForRemoteNotifications on launch + didReceiveRemoteNotification refetch of friend requests
  Assets.xcassets/           — app icon, racket animation, 15 avatar images
  *.lproj/Localizable.strings — en, ja, zh-Hans, ko, id, hi

badminton score tracker Watch AppTests/  — GameViewModel tests (compiled in CI, run locally on a simulator)
badminton score tracker Complication/    — WidgetKit extension (circular/corner/inline/rectangular)

badminton score tracker/       — iOS companion app (#41, in progress). Same target that used to be the watch-only stub container — now a real iOS app (NavigationStack root, iPhone-only, iOS 17+) that still embeds the Watch App. Has its own Info.plist, Assets.xcassets, .entitlements, and 6 *.lproj tables (iOS-only chrome under ios.*; History/Stats screens reuse the Watch's own string keys verbatim so translations copy across); the Watch App's Info.plist now declares it as companion (WKCompanionAppBundleIdentifier) instead of WKWatchOnly
  ContentView.swift          — iOS root: NavigationStack + List menu linking to History, Stats, and Friends (a numeric badge shows the incoming pending-request count, from a cached myParticipantId lookup mirroring AppStore.friends). Also owns onOpenURL for the `badminton://addfriend` invite link (scheme registered in this target's Info.plist, Roadmap 7d), presenting FriendInviteView as a sheet
  FriendInviteView.swift     — Friends v1 (7d), iOS-only: confirmation sheet for a parsed FriendInviteLink; confirm = ensureMyProfileExists (roster "Me" name fallback, backstopping FriendsView's 7e display-name prompt for a deep link opened before that screen is ever visited) → sendFriendRequest → fetchMyFriendRequests → AppStore.saveFriendRequests. No Watch counterpart — the invite *link* stays iOS-only, unlike FriendsView itself (Roadmap 7e)
  FriendsView.swift          — Friends v1 (Phase 7e): incoming/outgoing pending FriendRequests (accept/decline/cancel via CloudKitSyncManager.respondToFriendRequest), the friends list (AppStore.friends), and an add-friend ShareLink over FriendInviteLink.url. Also owns the one-time display-name prompt (myFriendsDisplayName). iOS restyle of the Watch's — ShareLink works on watchOS too (a friend invite is just a URL), so unlike ClubDetailView's CloudSharingView invite (UIKit-only), this view is symmetric across targets. Phase 7f adds a second "Enter a Code" row: pastes either a full invite link (parsed via FriendInviteLink.parse) or a bare participantId, validated via CloudKitSyncManager.fetchProfile before sending
  HistoryView.swift          — iOS match list + MatchHistoryRow; date/type/sort/player filters, a toolbar club-scope `Menu` (Personal + joined clubs, Roadmap Phase 5f), and swipe-delete/clear-all. All filtering delegates to StatsCalculator; pushed via NavigationStack (no currentView binding). iOS-native restyle of the Watch's HistoryView
  StatsView.swift            — iOS per-player stats: win-rate ring + stat-card grid + avatar'd head-to-head; math all in StatsCalculator; same toolbar club-scope `Menu` as HistoryView (Phase 5f). iOS-native restyle of the Watch's StatsView
  RosterView.swift           — iOS roster management (edit Me, add/rename/delete players, sort order). Ported from the Watch SettingsView roster section, incl. the rename→history propagation (renames update past matches via player id + update myName). Writes via AppStore.saveRoster/saveHistory
  PlayerEditView.swift       — iOS single-player editor sheet (real keyboard TextField + duplicate detection, color/avatar/icon grids). Restyle of the Watch's; validation logic verbatim. Phase 5d adds the same optional club Picker as the Watch's
  ClubsView.swift            — iOS restyle of the Watch's Phase 5d club list + create; entered from ContentView's menu (not SettingsView, matching where RosterView is entered)
  ClubDetailView.swift       — iOS restyle of the Watch's Phase 5d club detail (rename, member list, per-club roster, delete/leave); Phase 5e adds an owner-only "Invite" button presenting CloudSharingView. Activity rows carry inline emoji reaction chips + a comment-count button opening MatchReactionsView (#164)
  MatchReactionsView.swift   — Phase 5 backlog (#164), iOS: reactions/comments sheet for one club match — emoji toggling plus comment composing (TextField + Send, trimmed, 200-char cap); ReactionEmojiButton is the shared borderless chip also used inline on ClubDetailView's activity rows
  CloudSharingView.swift     — Phase 5e, iOS-only: UIViewControllerRepresentable wrapping UICloudSharingController, the system sheet for sending a club's CKShare invite (built from CloudKitSyncManager.fetchOrCreateShare's CKShare + the new ckContainer accessor). No watchOS counterpart — UICloudSharingController is UIKit-only
  PlayerAvatar.swift         — iOS presentation extension of Player (avatarColors/avatarImageNames/sportIcons/AvatarView). Per-target copy of the Watch's; the 15 avatar images are duplicated into this target's Assets.xcassets
  ShareCard.swift            — iOS-only (#13): match-result card rendered to PNG via ImageRenderer + a SharableMatchCard Transferable (image + plain-text). Long-press a history row → ShareLink. No Watch counterpart
  NewMatchFlow.swift         — modal container (fullScreenCover from ContentView) routing preMatch → game; PreMatchView writes match-config @AppStorage, GameView's VM reads it on appear (same handoff as the Watch's .preMatch/.game routes)
  PreMatchView.swift         — iOS player selection (singles/doubles picker + near/partner/far/partner steps, h2h records); reuses PlayerEditView to add players. Closure-driven (onReady/onCancel), no currentView binding. Near-side step also offers a Club picker (default Personal, hidden if the user has no clubs — Phase 5 backlog, #169) whose selection is written to matchClubId and read by GameViewModel.saveMatch()
  GameView.swift             — iOS live scoring: two big tap tiles (ScoreView), games header, timer, banners, match-over overlay. Tap-only — NO Digital Crown, NO HealthKit workout. Restyle of the Watch's
  GameViewModel.swift        — iOS @MainActor VM; per-target adaptation of the Watch's (UIKit haptics, no WorkoutManager, top-level GameMode). Match-config keys (matchMyName/…/gameMode) stay device-local so phone- and watch-scored matches can't collide mid-setup; finished MatchRecord flows through AppStore.saveHistory
  HapticsProvider.swift      — iOS HapticsProvider protocol + GameHapticType (platform-neutral) + UIKitHapticsProvider (impact/notification generators). Mirrors the Watch's WKHapticType abstraction
  StoreManager.swift / PaywallView.swift — iOS copies of the Watch's StoreKit 2 manager + a fuller storefront sheet (feature list, price buttons, restore); same entitlement gating call sites (StatsView, PlayerEditView, GameView theme fallback)
  AdBannerView.swift         — iOS-only, the single home of ALL ad code (GoogleMobileAds v12 SPM dep on this target only): UMP consent → ATT prompt → SDK start → 320×50 banner; mounted via safeAreaInset on ContentView/HistoryView/StatsView behind Entitlements.showsAds, never on GameView. Test app/ad-unit ids until release
  CourtTheme.swift / AudioFeedback.swift — per-target copies of the Watch's (CourtTheme colors; AVFoundation tones + speech are cross-platform, byte-identical). CourtTheme.isPremium (both copies) gates red/purple/black behind Pro/theme-pack
  AppStore.swift             — iOS cache/singleton; port of the Watch's (save* enqueue to CloudKitSyncManager, applyRemoteUpsert/applyRemoteDeletions/applyRemoteSettings). Friends v1 (#7c): byte-identical friendRequests/friends/saveFriendRequests addition as the Watch's
  CloudKitSyncManager.swift  — iOS CloudKit sync; near-verbatim port of the Watch's two-CKSyncEngine + Settings + Friends public-DB setup, sharing the same CloudKit container (iCloud.ritsuma.badminton-score-tracker) so watch and phone sync with each other. Always-on (no feature flag)
  AppDelegate.swift / SceneDelegate.swift — registers the scene delegate and catches CKShare-acceptance callbacks (willConnectTo cloudKitShareMetadata + userDidAcceptCloudKitShareWith), forwarding to CloudKitSyncManager.acceptShare (Roadmap Phase 5c). Installed via @UIApplicationDelegateAdaptor in badminton_score_trackerApp.swift. Phase 7f: remote-push registration/handling mirror of the Watch
  SettingsView.swift         — iOS: paywall entry (and room to grow into a fuller settings mirror of the Watch's later); sync is always-on CloudKit with no toggle
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

Seven parallel jobs per PR (SwiftLint, core `swift test`, localization key sync ×2 — Watch + iOS tables are checked separately since their key sets legitimately diverge, Watch App build-for-testing, Complication build, iOS App build); green in **~4 min** — details, runtimes, and polling advice in [docs/ci.md](docs/ci.md). Before pushing: run `swiftlint` and `swift test --package-path BadmintonCore`; build locally before pushing SwiftUI changes when possible. **Use plan mode for anything touching `CloudKitSyncManager`/`AppStore` (Watch OR iOS)** (real bugs in this codebase lived there — see docs/ci.md; dual-target writers to the same CloudKit container; sync correctness can't be proven by CI, only a two-device test), and run `/code-review` before merging non-trivial PRs.

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
