//
//  Entitlements.swift
//  BadmintonCore
//
//  Monetization model: the pure mapping from "which StoreKit product IDs
//  does this Apple ID own" to "which features are unlocked". Deliberately
//  StoreKit-free (Foundation-only, like everything in BadmintonCore) so the
//  mapping is unit-testable on macOS; each app target's StoreManager owns
//  the actual StoreKit 2 transaction plumbing and feeds owned IDs in here.
//
//  Source of truth is StoreKit's Transaction.currentEntitlements, which is
//  per-Apple-ID and already cross-device — purchase state is NEVER synced
//  through the iCloud KV store or CloudKit (see AppStorageKeys.ownedProductIds
//  for the local launch-state cache). Governing invariant (ROADMAP.md):
//  scoring, history, roster, and clubs stay free; everything gated here is
//  additive polish — advanced stats, cosmetics, and ad removal.
//

import Foundation

public enum ProductID {
    /// One-time Pro unlock: removes ads and includes every other unlock.
    public static let pro = "ritsuma.badminton.pro"
    /// À-la-carte premium court themes.
    public static let themePack = "ritsuma.badminton.pack.themes"
    /// À-la-carte premium avatar images/icons.
    public static let avatarPack = "ritsuma.badminton.pack.avatars"

    /// Every purchasable product, in display order (Pro first).
    public static let all = [pro, themePack, avatarPack]
}

public struct Entitlements: Equatable {
    public let isPro: Bool
    public let ownsThemePack: Bool
    public let ownsAvatarPack: Bool

    /// Nothing owned — the launch/default state and the free tier.
    public static let none = Entitlements(ownedProductIDs: [])

    public init(ownedProductIDs: Set<String>) {
        isPro = ownedProductIDs.contains(ProductID.pro)
        ownsThemePack = ownedProductIDs.contains(ProductID.themePack)
        ownsAvatarPack = ownedProductIDs.contains(ProductID.avatarPack)
    }

    /// Head-to-head and streak stats (basic win rate/totals stay free).
    public var hasAdvancedStats: Bool { isPro }

    /// Premium court themes — Pro includes the pack.
    public var hasAllThemes: Bool { isPro || ownsThemePack }

    /// Premium avatar images/icons — Pro includes the pack.
    public var hasAllAvatars: Bool { isPro || ownsAvatarPack }

    /// Banner ads (iOS only) show until Pro is owned. The packs deliberately
    /// do NOT remove ads — ad removal is Pro's headline feature.
    public var showsAds: Bool { !isPro }
}

/// Codec for `AppStorageKeys.ownedProductIds`'s `Data`-backed `Set<String>`
/// cache; same pattern as `ClubActivityCodec` — `@AppStorage` has no native
/// `Set<String>` support, so StoreManagers decode/encode through this.
public enum OwnedProductsCodec {
    public static func decode(_ data: Data) -> Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: data)) ?? []
    }

    public static func encode(_ productIDs: Set<String>) -> Data {
        (try? JSONEncoder().encode(productIDs)) ?? Data()
    }
}
