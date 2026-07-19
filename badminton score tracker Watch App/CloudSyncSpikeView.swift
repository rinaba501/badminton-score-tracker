//
//  CloudSyncSpikeView.swift
//  badminton score tracker Watch App
//
//  DEBUG-only screen for the Postgres/Supabase + Google OAuth feasibility
//  spike (see CLAUDE.md, CloudSyncSpike package). The watch never performs
//  Google OAuth itself (no in-app browser) — it only shows whatever session
//  WatchAppDelegate has adopted from a relay sent by the paired iPhone.
//  Entirely separate from the real save/sync path: AppStore/
//  CloudKitSyncManager are untouched.
//

import SwiftUI
import CloudSyncSpike

struct CloudSyncSpikeView: View {
    @ObservedObject private var client = SupabaseSpikeClient.shared

    var body: some View {
        List {
            Section("Status") {
                Text(client.statusMessage)
                if !client.isSignedIn {
                    Text("Sign in on the paired iPhone (Settings → Cloud Sync Spike) to relay a session here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Test record") {
                Button("Send test record") {
                    Task { await client.insertTestRecord(note: "watch spike test") }
                }
                .disabled(!client.isSignedIn)
                Button("Fetch records") {
                    Task { _ = await client.fetchTestRecords() }
                }
                .disabled(!client.isSignedIn)
            }

            Section("Log") {
                ForEach(Array(client.log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption2)
                }
            }
        }
        .navigationTitle("Cloud Sync Spike")
    }
}
