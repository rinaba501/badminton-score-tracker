//
//  StoreManager.swift
//  badminton score tracker (iOS)
//
//  StoreKit 2 plumbing for the monetization model — per-target copy of the
//  Watch App's StoreManager (same pattern as HapticsProvider/CourtTheme; see
//  that file's header for the full design notes). BadmintonCore's
//  Entitlements.swift holds the pure product-ID → feature mapping this feeds.
//  Transaction.currentEntitlements is the per-Apple-ID source of truth, so
//  a purchase on either device unlocks both — purchase state is never synced
//  through the app's own sync backend. On iOS, Pro additionally hides the
//  AdBannerView (ads are iOS-only; the Watch never shows them).
//

import Combine
import StoreKit
import BadmintonCore

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    /// What the current Apple ID owns; seeded from the local cache so gated
    /// UI renders correctly before the first StoreKit round-trip resolves.
    @Published private(set) var entitlements: Entitlements

    /// Storefront products in `ProductID.all` display order (Pro first);
    /// empty until loaded (or when the App Store is unreachable).
    @Published private(set) var products: [Product] = []

    private var updatesTask: Task<Void, Never>?

    private init() {
        let cachedData = UserDefaults.standard.data(forKey: AppStorageKeys.ownedProductIds) ?? Data()
        entitlements = Entitlements(ownedProductIDs: OwnedProductsCodec.decode(cachedData))
    }

    /// Call once at app launch: verifies current entitlements, loads the
    /// storefront, and keeps listening for out-of-band transaction updates
    /// (purchases on another device, refunds, Ask to Buy approvals).
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in StoreKit.Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await refreshEntitlements()
            await loadProducts()
        }
    }

    func loadProducts() async {
        guard let storeProducts = try? await Product.products(for: ProductID.all) else { return }
        products = storeProducts.sorted { lhs, rhs in
            let order = ProductID.all
            let l = order.firstIndex(of: lhs.id) ?? order.count
            let r = order.firstIndex(of: rhs.id) ?? order.count
            return l < r
        }
    }

    /// Runs the purchase flow; entitlements refresh on success. `.pending`
    /// (Ask to Buy) resolves later through the Transaction.updates listener.
    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        if case .success(let verification) = result,
           case .verified(let transaction) = verification {
            await transaction.finish()
            await refreshEntitlements()
        }
    }

    /// "Restore Purchases": force a sync with the App Store, then re-derive.
    /// (StoreKit.AppStore, not this app's own AppStore cache class.)
    func restorePurchases() async {
        try? await StoreKit.AppStore.sync()
        await refreshEntitlements()
    }

    private func refreshEntitlements() async {
        var owned = Set<String>()
        for await entitlement in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.revocationDate == nil {
                owned.insert(transaction.productID)
            }
        }
        entitlements = Entitlements(ownedProductIDs: owned)
        UserDefaults.standard.set(OwnedProductsCodec.encode(owned),
                                  forKey: AppStorageKeys.ownedProductIds)
    }
}
