//
//  PaywallView.swift
//  badminton score tracker Watch App
//
//  Slim watch storefront for the monetization products (Pro + cosmetic
//  packs), presented as a sheet from every lock badge and from Settings.
//  StoreKit 2 purchases run natively on watchOS — no phone hand-off needed;
//  a purchase on either device unlocks both (same Apple ID). Product names
//  and prices come localized from StoreKit; only the chrome strings live in
//  Localizable.strings. No explicit dismiss control: watchOS adds the
//  sheet's close button automatically (same convention as HistoryView's
//  filter sheets).
//

import StoreKit
import SwiftUI
import BadmintonCore

struct PaywallView: View {
    @EnvironmentObject private var storeManager: StoreManager

    var body: some View {
        // Wrapped in its own NavigationStack so the title renders inside the
        // sheet (the root NavigationView doesn't extend into sheets).
        NavigationStack {
            paywallList
        }
    }

    private var paywallList: some View {
        List {
            Section(footer: Text("paywall.pro_features")) {
                if storeManager.products.isEmpty {
                    Text("paywall.unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(storeManager.products, id: \.id) { product in
                        productRow(product)
                    }
                }
            }

            Section {
                Button("paywall.restore") {
                    Task { await storeManager.restorePurchases() }
                }
            }
        }
        .navigationTitle("paywall.title")
        .onAppear {
            if storeManager.products.isEmpty {
                Task { await storeManager.loadProducts() }
            }
        }
    }

    @ViewBuilder private func productRow(_ product: Product) -> some View {
        let owned = storeManager.entitlements.owns(product.id)
        Button {
            Task { try? await storeManager.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(owned ? NSLocalizedString("paywall.owned", comment: "") : product.displayPrice)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if owned {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .accessibilityHidden(true)
                }
            }
        }
        .disabled(owned)
    }
}
