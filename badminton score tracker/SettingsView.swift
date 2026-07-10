//
//  SettingsView.swift
//  badminton score tracker (iOS)
//
//  Just the CloudKit sync toggle for now (Phase 4 cutover). Room to grow into
//  a full settings mirror of the Watch's later; not scoped here.
//

import SwiftUI
import BadmintonCore

struct SettingsView: View {
    @AppStorage(AppStorageKeys.cloudKitSyncEnabled) private var cloudKitSyncEnabled = false
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

            Section(header: Text("settings.sync"), footer: Text("settings.sync_caption")) {
                Toggle("settings.sync_cloudkit", isOn: $cloudKitSyncEnabled)
            }
        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}
