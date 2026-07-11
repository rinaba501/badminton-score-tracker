//
//  SettingsView.swift
//  badminton score tracker (iOS)
//
//  Just the paywall entry point for now (sync is always-on via CloudKit,
//  no toggle). Room to grow into a full settings mirror of the Watch's
//  later; not scoped here.
//

import SwiftUI
import BadmintonCore

struct SettingsView: View {
    @EnvironmentObject private var storeManager: StoreManager
    @State private var showPaywall = false

    var body: some View {
        List {
            if !storeManager.entitlements.isPro {
                Section {
                    Button(action: { showPaywall = true }) {
                        Label("paywall.title", systemImage: "crown.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }
        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}
