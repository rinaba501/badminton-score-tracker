//
//  EraseDataView.swift
//  badminton score tracker Watch App
//
//  Erase All My Data (#264): a strongly-confirmed action that deletes every
//  local + CloudKit-synced record this account owns (roster, history,
//  clubs, the Friends graph) and resets every scalar setting back to its
//  fresh-install default — see AppStore.eraseAllData(). Owned clubs are
//  deleted outright (warned about below, listed by name); real club
//  ownership *transfer* isn't supported yet (CloudKit ties a private-DB
//  zone's ownership permanently to its creating account — transferring
//  would mean copying every record into a new zone under the new owner and
//  re-sharing it, a separate feature). Entered from SettingsView's Danger
//  Zone section.
//

import SwiftUI
import BadmintonCore

struct EraseDataView: View {
    @Binding var currentView: ContentView.AppView
    @EnvironmentObject private var appStore: AppStore
    @State private var confirmationText = ""
    @State private var isErasing = false

    /// Intentionally not localized — a fixed exact-match keyword (same
    /// convention as GitHub/AWS-style destructive confirmations) avoids
    /// translation ambiguity on the one string in the app that gates an
    /// irreversible, cross-user action.
    private static let confirmationKeyword = "DELETE"

    private var ownedClubs: [Club] {
        appStore.clubs.filter { $0.ownerRecordName == nil }
    }

    private var canErase: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == Self.confirmationKeyword
    }

    var body: some View {
        List {
            Section {
                Text("settings.erase_all_data_warning")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !ownedClubs.isEmpty {
                Section(header: Text("settings.erase_owned_clubs_warning").foregroundColor(.red)) {
                    ForEach(ownedClubs) { club in
                        Text(club.name)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section {
                Text(String(format: NSLocalizedString("settings.erase_confirm_prompt", comment: ""), Self.confirmationKeyword))
                    .font(.caption)
                TextField(Self.confirmationKeyword, text: $confirmationText)
                    .accessibilityLabel(Text("settings.erase_confirm_prompt"))
            }

            Section {
                Button(role: .destructive) {
                    isErasing = true
                    Task {
                        await appStore.eraseAllData()
                        isErasing = false
                        currentView = .menu
                    }
                } label: {
                    if isErasing {
                        ProgressView()
                    } else {
                        Text("settings.erase_confirm_button")
                    }
                }
                .disabled(!canErase || isErasing)
            }
        }
        .navigationTitle("settings.erase_all_data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
