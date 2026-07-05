# iOS Companion App Plan (Issue #41 / ROADMAP Phase 6)

Approved implementation plan for the iPhone companion app, split into 6 PRs. This is the detailed working plan; [ROADMAP.md](../ROADMAP.md) tracks phase-level status and [SPEC.md](../SPEC.md) tracks the shipped feature spec. Update the checklist below as each PR merges.

## Context

The watch is the scoring device; browsing history/stats, managing the roster with a real keyboard, and sharing results (#13) are all better on a phone. Phases 1–2 made this cheap: `BadmintonCore` is platform-free (already declares `.iOS("17.0")` in Package.swift) and all live-game logic sits behind `GameViewModel`. The iOS app consumes `BadmintonCore` + the same iCloud KV data; no live scoring on iOS in v1.

**Locked scope (decided up front):**
- Sync via `NSUbiquitousKeyValueStore` (NOT CloudKit, NOT WatchConnectivity), with a shared explicit `ubiquity-kvstore-identifier` on both targets.
- V1 = full: History (incl. delete), Stats, Roster management (add/rename/delete), Share card (#13).
- Live scoring on iPhone: yes, but as a follow-up **PR6** after the v1 screens land — not part of the v1 gate.
- Restructure the existing "badminton score tracker" container target in place (keep bundle id `ritsuma.badminton-score-tracker` and the "Embed Watch Content" phase) — no duplicate target.

## Facts verified before implementation

- pbxproj: target `badminton score tracker` was `productType = com.apple.product-type.application.watchapp2-container`, no Sources phase, owned "Embed Watch Content" embedding the Watch App. No `DEVELOPMENT_TEAM` on it (Watch App uses `MNX5PS5RV3`).
- CI (`.github/workflows/ci.yml`, pre-PR1): 5 independent jobs; `localization-sync` hardcodes `BASE="badminton score tracker Watch App"`. No shared scheme existed for the iOS target.
- `.swiftlint.yml` `included:` is an explicit list — a new iOS folder must be added or it silently goes unlinted.
- Watch entitlements: KV identifier is `$(TeamIdentifierPrefix)$(CFBundleIdentifier)` — per-target, so Watch and iOS land in different buckets unless changed. CloudKit entitlements are also present (inert, flag off) — do NOT add CloudKit to iOS v1.

## PR sequencing

### PR1 — Target restructure + shell + CI — done ([#133](https://github.com/rinaba501/badminton-score-tracker/pull/133))

Converted `badminton score tracker` to a real iOS app target in place; added the placeholder shell (`ContentView`, app entry, `Info.plist`, `Assets.xcassets`, 6-locale strings); fixed a `WKWatchOnly`/companion-app conflict (Watch App's Info.plist now declares `WKCompanionAppBundleIdentifier` + `WKRunsIndependentlyOfCompanionApp` instead of `WKWatchOnly` — **any archive taken from a commit after this PR includes the iOS app**; a watch-only submission must archive from an earlier commit); added the shared iOS scheme; added `ios-build` and `ios-localization-sync` CI jobs (5 → 7 total); added the iOS folder to `.swiftlint.yml`.

### PR2 — Sync layer (highest risk — plan mode + `/code-review` + two-device test required) — implemented; two-device test pending

Ported the Watch's `CloudSyncManager` + `AppStore` to iOS as KV-only copies (no CloudKit branching); both targets now share one KV bucket via a byte-identical `ubiquity-kvstore-identifier` (`$(TeamIdentifierPrefix)ritsuma.badminton-score-tracker.shared`). The iPhone is write-capable and keeps the `isHistoryShrink` delete-overwrite guard. The shell shows a temporary synced-counts line (replaced by real screens in PR3). Merge gate is the two-device manual test below.

- iOS `CloudSyncManager.swift` + `AppStore.swift`: near-verbatim ports of the Watch's, minus all `CloudKitSyncManager` branching (iOS v1 hardcodes the KV path). Same `SyncKeys`, same `pushToCloud(overwriteHistory:)` / `pullFromCloud()` / `externalChange(_:)` / merge-by-id `syncHistory()`.
- iOS must be write-capable: roster edits push, and history *deletion* from iOS must replicate the `PersistenceStore.isHistoryShrink` overwrite-vs-merge distinction — the same class of bug as the historical "clear history resurrection" bug, now with two real writers.
- Entitlement (both targets, via Xcode Signing & Capabilities, byte-identical): `com.apple.developer.ubiquity-kvstore-identifier = $(TeamIdentifierPrefix)ritsuma.badminton-score-tracker.shared`.
- **Bucket-migration note:** the new `.shared` bucket starts empty. History re-seeds automatically (`syncHistory()` merges local+cloud and writes the union back), but roster + scalars only reach the new bucket on the next local save on the Watch. The two-device test must start by launching the Watch app once and making one roster/settings touch to seed the bucket.
- **Merge gate:** two-device (real iPhone + paired Watch, same Apple ID) manual test: roster add on iPhone → appears on Watch; match delete on iPhone → stays deleted on Watch after relaunch; rename on Watch → appears on iPhone.

### PR3 — History + Stats views — implemented; two-device delete-recheck pending

Ported the Watch's `HistoryView`/`MatchHistoryRow`/`StatsView` filter + stats logic (all in `StatsCalculator` — zero reimplementation), restyled for iPhone: segmented date/type/sort controls, a toolbar player-filter menu, swipe-to-delete + clear-all (via PR2's shrink-aware `saveHistory`/`clearHistory`), and a per-player Stats screen with head-to-head. `ContentView` is now a home menu linking to both. History/Stats reuse the Watch's own string keys so translations copied verbatim. Gate: CI (green) + a lightweight two-device re-check that a delete stays deleted through the real UI.

### PR4 — Roster management — implemented; two-device propagation check pending

Added `RosterView.swift` (Me section + add/rename/delete + sort order), iOS `PlayerEditView.swift` (real-keyboard TextField + duplicate detection + color/avatar/icon grids), and `PlayerAvatar.swift` (per-target presentation extension); the 15 avatar images were duplicated into the iOS asset catalog. `savePlayerEdit` ports the Watch's rename→history propagation verbatim (renames update past matches via player id + update myName), writing through PR2's `saveRoster`/`saveHistory`. Gate: CI (green) + a two-device roster-edit propagation check.

### PR5 — Share card (#13) — implemented; closes #13

`ShareCard.swift`: SwiftUI card rendered to a PNG via `ImageRenderer`; a `SharableMatchCard: Transferable` exposes both the image and a plain-text summary. Long-press a history row → `ShareLink` (context menu). Lowest risk; closes #13.

### PR6 — Live scoring on iPhone (follow-up, after v1)

iOS `GameView.swift` + `PreMatchView.swift` + `GameViewModel.swift`: per-target adapted copies (`GameViewModel` uses `@AppStorage`/SwiftUI so it can't move into Foundation-only `BadmintonCore`; the pure scoring rules already live in `BadmintonMatch`). Reuses `ScoreCallFormatter`, `AppStorageKeys`, and the guest-token identity convention unchanged. iOS `HapticsProvider` implementation via `UIImpactFeedbackGenerator`/`UINotificationFeedbackGenerator`. Omissions vs. Watch: no HealthKit workout logging (watchOS-only), no crown scoring. Match state stays per-device (KV-excluded), so a phone-scored match and a watch-scored match can't collide. Gate: two-device check that an iPhone-scored match appears in the Watch's history.

## Docs to update per PR

- SPEC.md: iOS Companion App platform section; screens listed as they land; move #41/#13 to Closed when done.
- CLAUDE.md: Project Structure entry for `badminton score tracker/`; shared KV identifier note; extend the plan-mode rule to the iOS `CloudSyncManager`/`AppStore`; CI job count.
- ROADMAP.md: Phase 6 row progression.

## Verification

Per PR: `swiftlint`, `swift test --package-path BadmintonCore`, `xcodebuild build-for-testing` for both the Watch scheme (embedding intact) and the iOS scheme. iPhone Simulator can sign into real iCloud (unlike Watch Simulator), so single-device KV sync smoke-testing is possible locally — true two-writer tests still need the real-hardware gates called out in PR2–PR4.

## Status checklist

- [x] PR1 — target restructure + shell + CI ([#133](https://github.com/rinaba501/badminton-score-tracker/pull/133))
- [x] PR2 — sync layer (code merged; two-device hardware test still pending)
- [x] PR3 — History + Stats views (code merged; two-device delete-recheck still pending)
- [x] PR4 — Roster management (code merged; two-device propagation check still pending)
- [x] PR5 — Share card (#13, closes the issue)
- [ ] PR6 — live scoring on iPhone (follow-up)
