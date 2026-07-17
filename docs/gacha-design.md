# Feathers & Gacha — Design

Initiative: an in-app cosmetic gacha (ガチャ) with an earned soft currency ("Feathers")
and real-money paid pulls. Design discussed and confirmed 2026-07-17; this document is
the reference for the implementation phases (Phase 8 in [ROADMAP.md](../ROADMAP.md)).

**Status: design only — no code exists yet.**

---

## 1. Goals & non-goals

**Goals**

1. A retention loop: recording real matches earns Feathers, Feathers buy gacha pulls,
   pulls award cosmetics that show up on your avatar/profile — a reason to score every
   match in the app.
2. A second, impulse-friendly revenue stream alongside the existing Pro/pack IAPs,
   without cannibalizing them.
3. Minimal legal/compliance surface (details in §2 — this constraint shapes the whole
   economy model).

**Non-goals**

- No gameplay or stats advantages from gacha items — cosmetics only. The ROADMAP
  invariant ("scoring, history, roster, and clubs stay free; everything gated is
  additive polish") holds.
- No trading, gifting, or cash-out of items or Feathers.
- No server. Everything runs on-device + CloudKit, same as the rest of the app.
- No new image assets in v1 — every prize is code-drawable (SwiftUI/SF Symbols/tones).

## 2. Economy model & compliance (the load-bearing decisions)

### 2.1 Two inputs, no stored paid value

| Input | What it is | Stored? |
|---|---|---|
| **Feathers** (羽根) | Earned-only soft currency from playing matches. Never purchasable. | Yes — a local ledger, synced later (§6) |
| **Paid pulls** | StoreKit **consumable** products. Purchasing executes the pull(s) *immediately* in the same flow — the user sees results seconds after paying. | **No** — nothing paid is ever banked |

This split is deliberate:

- **資金決済法 (Japan Payment Services Act):** purchasable stored in-app currency is a
  prepaid payment instrument with issuer obligations. Because paid pulls execute
  immediately and only *earned* Feathers are stored (無償ポイント — granted free of
  charge), the app never issues a prepaid instrument. This is the single biggest
  simplification in the design; do not "improve" it later by banking paid pulls or
  selling Feathers without revisiting this section.
- **Refund exposure:** consumables are invisible to `Transaction.currentEntitlements`
  after finishing, and without a server there are no App Store Server Notifications, so
  refunds cannot be reliably detected or clawed back. Accepted as bounded leakage: a
  refunded purchase is one already-executed pull batch, never a large stored balance.
  Pricing assumes 1–2% refund leakage.
- **Apple 3.1.1 odds disclosure:** required regardless of model. §7's Odds screen is a
  first-class, prominently linked screen — a visible "Odds / 提供割合" button on the
  gacha screen itself, not buried in settings. This is the main App Review risk; make
  it impossible to miss.
- **景品表示法 / no コンプガチャ:** there is no "collect the set, win a meta-prize"
  mechanic anywhere, and none may be added. Duplicate compensation (§4.4) and the pity
  counter (§4.3) are fine; set-completion rewards are not.
- **Age rating:** re-answer the App Store Connect questionnaire on the release that
  ships this. Gacha is not classified as simulated gambling under current Apple
  practice, but the answers must be consistent with the mechanic.
- **Ask to Buy:** pending purchases resolve later through the `Transaction.updates`
  listener — redemption must work from that path, not only from the purchase call
  (§5.2), and must be idempotent.

### 2.2 Anti-tamper posture

The Feather ledger lives in UserDefaults and is editable by a motivated user. Accepted:
Feathers are earned-only and buy cosmetics only, so tampering mints zero revenue loss —
paid pulls never read the ledger. Do not add obfuscation; it buys nothing here.

## 3. Earning Feathers

Earning hooks into the existing save path (`GameViewModel.saveMatch` →
`AppStore.saveHistory`); only real completed matches earn. Rules are pure functions in
`BadmintonCore` (`GachaEarnRules`), unit-tested:

| Event | Feathers |
|---|---|
| Match completed (saved to history) | 10 |
| Won the match | +5 |
| First match of the calendar day (device-local day) | +20 |
| Current win streak reaches 3, 5, 10 (each once per streak) | +10 |
| Daily earn cap | 200 |

At 100 Feathers per pull (§4.1), an active player earns roughly a pull per 6–8 matches
— a physical badminton session, so grinding is naturally rate-limited; the daily cap is
a backstop, not the primary control. All numbers are constants in `GachaEarnRules`,
tuned freely before launch; they are **not** remote-configurable (no server).

## 4. The gacha

### 4.1 Pulls

- 1 pull = **100 Feathers**, or via paid products (§5.1).
- Single pull and 10-pull. A 10-pull guarantees at least one Rare-or-better (the last
  slot rerolls if the first nine and it are all Common).

### 4.2 Odds (published verbatim on the Odds screen)

| Rarity | Rate | Items in pool (v1) |
|---|---|---|
| Common | 70% | 22 |
| Rare | 24% | 12 |
| Epic | 5% | 5 |
| Legendary | 1% | 2 |

Within a rarity, every item is equally likely. The Odds screen shows both the rarity
table and the full per-item list with each item's individual rate.

### 4.3 Pity

A persistent counter guarantees a Legendary within 100 pulls (counter resets when one
drops, from pity or luck). Derived from the ledger (§6.1), never stored separately.
Shown on the gacha screen ("Legendary guaranteed within N pulls") — disclosed mechanics
are both friendlier and safer than hidden ones.

### 4.4 Duplicates

Owning an item removes nothing from the pool (odds stay as published — simpler and
honest). A duplicate converts to Feathers on the spot: Common 10, Rare 30, Epic 100,
Legendary 300. This is compensation, not a second currency.

### 4.5 Prize pool (v1 catalog, ~41 items, all code-drawable)

| Kind | What it is | Where it shows | Count |
|---|---|---|---|
| **Avatar frames** | Rings around `AvatarView`: solid colors (Common) → gradients (Rare) → glow/metallic (Epic) → animated gradient, static fallback on watchOS + `reduceMotion` (Legendary) | Everywhere `AvatarView` renders (roster, pre-match, history, clubs, friends) | 16 |
| **Badges** | SF Symbol + color chip next to your name | Profile, friends list, club member rows | 12 |
| **Titles** | Localized honorifics ("Smash Master", "Net Ninja", …) | Profile header, friend profile | 8 |
| **Victory fanfares** | Short tone sequences via the existing `AVAudioEngine` path (no audio files, per convention) played on match win | Match-over moment | 5 |

New kinds/items append to the catalog in later releases; ids are stable forever (§6.1
stores results by id). The pool is deliberately disjoint from the existing avatar/theme
packs — gacha never dispenses anything Pro or a pack sells, and `Entitlements.swift` is
not touched by this initiative (a consumable is not an entitlement).

## 5. StoreKit

### 5.1 Products

Two new **consumables**, added to `ProductID` alongside the existing three and to
`Badminton.storekit`:

| ID | Grants | Suggested price (tune in App Store Connect) |
|---|---|---|
| `ritsuma.badminton.gacha.pull1` | 1 pull, executed immediately | ¥160 tier |
| `ritsuma.badminton.gacha.pull10` | 11 pulls (10+1 bonus), executed immediately | ¥1,500 tier |

### 5.2 Redemption

Both targets' `StoreManager`s currently finish-and-refresh every transaction; they gain
one branch: a verified transaction whose `productID` is a gacha product routes to
redemption (execute pulls → append a ledger event → then `finish()`), from **both** the
purchase call and the `Transaction.updates` listener (Ask to Buy, interrupted
purchases, cross-device). Redemption is idempotent by `Transaction.id`: the ledger
event records it, and a transaction id already present in the ledger redeems nothing.
Pull results are computed at redemption time on the redeeming device.

## 6. Data model & persistence (`BadmintonCore`, Foundation-only)

### 6.1 Single source of truth: an append-only ledger

One new persisted collection, `[GachaEvent]` under `AppStorageKeys.gachaLedger`, with
`PersistenceStore` codecs like every other collection. Two event shapes:

- **earn** — amount + reason (`matchCompleted`/`win`/`dailyFirst`/`streak`/`duplicate`),
  date, source match id where applicable
- **pull** — cost (`feathers(Int)` or `paid(transactionId: String, productId: String)`),
  the resulting item ids, date

Everything else is **derived** by folding the ledger: Feather balance, owned-item set,
pity counter, lifetime pull count. No stored balance to drift, and — because events are
immutable and identified by UUID — sync is a conflict-free set union (§6.3), the same
per-record pattern `MatchRecord` uses. A `GachaLedgerSummary` fold (computed once per
mutation, cached in `AppStore`) keeps views from re-folding per render.

### 6.2 Engine and catalog

- `GachaItem` / `GachaCatalog.all` — static catalog in code: id, kind, rarity,
  localization key, render descriptor (colors/symbol/tone data — presentation mapping
  itself stays app-side, per the `PlayerAvatar.swift` precedent).
- `GachaEngine.roll(count:pity:rng:)` — pure function, `RandomNumberGenerator`
  injected, so tests drive it with a seeded generator: determinism tests, the 10-pull
  guarantee, pity bounds, and a statistical test that a large seeded sample lands
  within tolerance of the published odds (the disclosed table must be *true*).
- `GachaEarnRules` — pure earn computation (§3).

### 6.3 Sync

- **Ledger:** one CKRecord per event in the personal zone via the existing
  `CloudKitSyncManager` enqueue path; events are immutable so merge = union, no
  conflict logic. Ships as its own phase (8e) — the ledger is device-local until then,
  which is safe: worst case a device shows a stale balance, and paid pulls never
  depend on sync. Per repo convention this phase needs **plan mode and a two-device
  test** (CLAUDE.md; `CloudKitSyncManager`/`AppStore` history).
- **Equipped cosmetics:** four new `SettingsSnapshot` scalars — `equippedFrameId`,
  `equippedBadgeId`, `equippedTitleId`, `equippedFanfareId` (String, "" = none) —
  blind-overwritten like the other scalars (an equip preference has no merge hazard).
  Same `decodeIfPresent`-with-default migration as every field added after first ship.
- **Friends visibility (later, optional):** equipped frame/badge/title could join
  `FriendIdentitySnapshot` behind the existing avatar share toggle. Explicitly out of
  v1.

## 7. UI

**iOS** — new "Gacha" row on `ContentView`'s menu (with the others, not inside
Settings, per the Roster/Clubs precedent):

- **GachaView:** Feather balance, pity progress, Pull ×1 / ×10 (Feathers), a Buy
  section listing the two products with live StoreKit prices, and the prominent
  **Odds** button. Reveal animation (shuttlecock flip → rarity-colored card), honors
  `accessibilityReduceMotion` (fade, no motion). Never mounts `AdBannerView` — no ads
  anywhere near a purchase surface.
- **OddsView:** the §4.2 tables verbatim + pity and duplicate rules in plain language.
- **CollectionView:** owned/unowned grid by kind, rarity-colored, unowned as
  silhouettes. Equip from here and from `ProfileView` (equips write the
  `SettingsSnapshot` fields).

**watchOS** — entered from `SettingsView` (Clubs/Friends precedent): slim `GachaView`
(balance, single pull, last results, Odds and Collection as pushed lists). Purchases
work natively on watchOS (`PaywallView` precedent) — both products offered. Legendary
animated frames render static on watch.

**Localization:** every string — item names/descriptions (`gacha.item.<id>`,
`gacha.item.<id>.desc`), UI chrome, odds copy, a11y labels (`a11y.gacha.*`) — in all 6
languages. ~100 new keys; the two localization CI jobs gate key sync as usual.

## 8. Implementation phases

Sliced like Phase 5/7 — each independently shippable, `ship-pr` loop per phase:

| Phase | Contents | Ships user-visible? |
|---|---|---|
| **8a** | `BadmintonCore` only: catalog, ledger + codecs, engine, earn rules, `AppStorageKeys`, full unit tests | No |
| **8b** | Earning wired into the save path + iOS Gacha/Odds/Collection/equip UI — Feathers only, no IAP | Yes (free loop) |
| **8c** | Watch UI (slim) | Yes |
| **8d** | StoreKit consumables end-to-end: products, `StoreManager` redemption branch (idempotent, updates-listener path), storekit config, paywall-adjacent copy | Yes (paid pulls) |
| **8e** | CloudKit ledger sync (plan mode; two-device test) | Yes (cross-device balance) |
| **8f** | Release checklist: App Store Connect products, odds/terms copy, age-rating questionnaire, `docs/app-store-metadata.md` + privacy policy updates | — |

8b before 8d is deliberate: the free loop ships and soaks (economy tuning, review risk
isolated from money) before real money enters. SPEC.md/CLAUDE.md update in each phase's
PR per the doc convention.

## 9. Rejected alternatives (for the record)

- **Purchasable coin balance** (the classic model): rejected — stored paid value
  triggers 資金決済法 prepaid-instrument obligations, makes the balance a real-money
  tamper/refund target, and forces synced-balance correctness into v1. Revisit only
  with a server.
- **Existing avatars/themes as the prize pool:** rejected — cannibalizes the packs,
  Pro owners pull dead duplicates, and it entangles gacha with `Entitlements`.
- **Server-authoritative economy:** out of scope for a CloudKit-only app; the design
  above is chosen precisely so nothing *needs* to be authoritative.

## 10. Open questions (decide before the relevant phase)

1. Final price tiers and the earn/cost constants (defaults above are starting points —
   tune in 8b's soak).
2. Currency name/branding: "Feathers" (羽根) is the working name; localize or keep as
   a proper noun per locale?
3. Whether 8e ships before or after the first paid release (8d) — paid pulls don't
   depend on it either way.
