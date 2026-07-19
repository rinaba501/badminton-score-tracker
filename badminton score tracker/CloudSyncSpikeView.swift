//
//  CloudSyncSpikeView.swift
//  badminton score tracker (iOS)
//
//  DEBUG-only screen for the Postgres/Supabase + Google OAuth feasibility
//  spike (see CLAUDE.md, CloudSyncSpike package). Performs the actual OAuth
//  handshake, then relays the resulting session to the paired watch over
//  WCSession — the watch never authenticates on its own. Entirely separate
//  from the real save/sync path: AppStore/CloudKitSyncManager are untouched.
//

import SwiftUI
import CloudSyncSpike
import AuthenticationServices

struct CloudSyncSpikeView: View {
    @ObservedObject private var client = SupabaseSpikeClient.shared
    @State private var testNote = ""

    var body: some View {
        List {
            Section("Status") {
                Text(client.statusMessage)
            }

            Section("Google Sign-In") {
                Button("Sign in with Google") {
                    Task {
                        guard let anchor = presentationAnchor() else { return }
                        await client.signInWithGoogle(presentationAnchor: anchor)
                        await relayCurrentSession()
                    }
                }
                .disabled(client.isSignedIn)
            }

            Section("Watch Relay") {
                Button("Relay to Watch") {
                    Task { await relayCurrentSession() }
                }
                .disabled(!client.isSignedIn)
            }

            Section("Test record") {
                TextField("Note", text: $testNote)
                Button("Send test record") {
                    Task { await client.insertTestRecord(note: testNote.isEmpty ? "spike test" : testNote) }
                }
                .disabled(!client.isSignedIn)
                Button("Fetch records") {
                    Task { _ = await client.fetchTestRecords() }
                }
                .disabled(!client.isSignedIn)
            }

            Section("Log") {
                ForEach(Array(client.log.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.caption)
                }
            }
        }
        .navigationTitle("Cloud Sync Spike")
    }

    private func relayCurrentSession() async {
        if let tokens = await client.relayableSessionTokens() {
            AppDelegate.relaySessionToWatch(tokens: tokens)
        } else {
            client.logDiagnostic("Relay skipped: no session tokens available")
        }
    }

    private func presentationAnchor() -> ASPresentationAnchor? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
    }
}
