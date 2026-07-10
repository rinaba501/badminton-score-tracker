//
//  PaywallView.swift
//  badminton score tracker (iOS)
//
//  Full storefront for the monetization products (Pro + cosmetic packs),
//  presented as a sheet from Settings, the menu's Pro row, and every lock
//  badge. Product names and prices come localized from StoreKit; only the
//  chrome strings live in Localizable.strings. Counterpart of the Watch's
//  slimmer PaywallView — a purchase on either device unlocks both (same
//  Apple ID; entitlements come from Transaction.currentEntitlements).
//

import StoreKit
import SwiftUI
import BadmintonCore

struct PaywallView: View {
    @EnvironmentObject private var storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    proFeatureList
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                Section(footer: Text("paywall.pro_features")) {
                    if storeManager.products.isEmpty {
                        Text("paywall.unavailable")
                            .foregroundStyle(.secondary)
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("history.cancel") { dismiss() }
                }
            }
            .onAppear {
                if storeManager.products.isEmpty {
                    Task { await storeManager.loadProducts() }
                }
            }
        }
    }

    private var proFeatureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            featureRow(icon: "rectangle.slash", key: "paywall.feature_no_ads")
            featureRow(icon: "chart.bar.fill", key: "paywall.feature_stats")
            featureRow(icon: "paintpalette.fill", key: "paywall.feature_cosmetics")
        }
        .padding(.vertical, 4)
    }

    private func featureRow(icon: String, key: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(key)
                .font(.subheadline)
        }
    }

    @ViewBuilder private func productRow(_ product: Product) -> some View {
        let owned = storeManager.entitlements.owns(product.id)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .fontWeight(.semibold)
                Text(product.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if owned {
                Label("paywall.owned", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            } else {
                Button(product.displayPrice) {
                    Task { try? await storeManager.purchase(product) }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .font(.subheadline.weight(.semibold))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(owned ? NSLocalizedString("paywall.owned", comment: "") : product.displayPrice))
    }
}
