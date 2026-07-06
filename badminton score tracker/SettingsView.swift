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

    var body: some View {
        List {
            Section(header: Text("settings.sync"), footer: Text("settings.sync_caption")) {
                Toggle("settings.sync_cloudkit", isOn: $cloudKitSyncEnabled)
            }
        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
    }
}
