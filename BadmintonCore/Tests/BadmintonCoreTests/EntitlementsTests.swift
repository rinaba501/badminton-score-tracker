//
//  EntitlementsTests.swift
//  BadmintonCoreTests
//
//  Pins the product-ID → feature mapping: Pro includes everything and is the
//  only way to remove ads; packs unlock exactly their own cosmetics.
//

import Foundation
import Testing
@testable import BadmintonCore

struct EntitlementsTests {

    @Test func freeTierShowsAdsAndUnlocksNothing() {
        let e = Entitlements.none
        #expect(e.showsAds)
        #expect(!e.isPro)
        #expect(!e.hasAdvancedStats)
        #expect(!e.hasAllThemes)
        #expect(!e.hasAllAvatars)
    }

    @Test func proUnlocksEverythingAndRemovesAds() {
        let e = Entitlements(ownedProductIDs: [ProductID.pro])
        #expect(!e.showsAds)
        #expect(e.hasAdvancedStats)
        #expect(e.hasAllThemes)
        #expect(e.hasAllAvatars)
        #expect(!e.ownsThemePack)
        #expect(!e.ownsAvatarPack)
    }

    @Test func themePackUnlocksOnlyThemesAndKeepsAds() {
        let e = Entitlements(ownedProductIDs: [ProductID.themePack])
        #expect(e.hasAllThemes)
        #expect(!e.hasAllAvatars)
        #expect(!e.hasAdvancedStats)
        #expect(e.showsAds)
    }

    @Test func avatarPackUnlocksOnlyAvatarsAndKeepsAds() {
        let e = Entitlements(ownedProductIDs: [ProductID.avatarPack])
        #expect(e.hasAllAvatars)
        #expect(!e.hasAllThemes)
        #expect(!e.hasAdvancedStats)
        #expect(e.showsAds)
    }

    @Test func proCountsPacksAsOwnedSoTheyCannotBeBoughtTwice() {
        let pro = Entitlements(ownedProductIDs: [ProductID.pro])
        #expect(pro.owns(ProductID.pro))
        #expect(pro.owns(ProductID.themePack))
        #expect(pro.owns(ProductID.avatarPack))
        let free = Entitlements.none
        #expect(!free.owns(ProductID.pro))
        #expect(!free.owns(ProductID.themePack))
        #expect(!free.owns("some.future.product"))
    }

    @Test func unknownProductIDsAreIgnored() {
        let e = Entitlements(ownedProductIDs: ["some.future.product"])
        #expect(e == .none)
    }

    @Test func ownedProductsCodecRoundTripsAndToleratesGarbage() {
        let ids: Set<String> = [ProductID.pro, ProductID.themePack]
        let data = OwnedProductsCodec.encode(ids)
        #expect(OwnedProductsCodec.decode(data) == ids)
        #expect(OwnedProductsCodec.decode(Data("not json".utf8)) == [])
    }
}
