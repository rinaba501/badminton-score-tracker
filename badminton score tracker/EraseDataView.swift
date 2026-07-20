//
//  EraseDataView.swift
//  badminton score tracker (iOS)
//
//  Erase All My Data (#264): a strongly-confirmed action that deletes every
//  local + cloud-synced record this account owns (roster, history, clubs,
//  the Friends graph) and resets every scalar setting back to its
//  fresh-install default — see AppStore.eraseAllData(). Owned clubs are
//  deleted outright (warned about below, listed by name); real club
//  ownership *transfer* isn't supported yet (a club's `owner_id` ties its
//  ownership permanently to its creating account — transferring would mean
//  copying every row to the new owner and re-inviting members, a separate
//  feature). Entered from SettingsView's Danger Zone section. On success,
//  shows a confirmation and dismisses back to
//  Settings — the user's normal back-navigation to ContentView's root
//  re-triggers the first-launch name prompt, since myName/didPromptForName
//  are reset along with everything else.
//

import SwiftUI
import BadmintonCore

struct EraseDataView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmationText = ""
    @State private var isErasing = false
    @State private var showSuccess = false

    /// Intentionally not localized — a fixed exact-match keyword (same
    /// convention as GitHub/AWS-style destructive confirmations) avoids
    /// translation ambiguity on the one string in the app that gates an
    /// irreversible, cross-user action.
    private static let confirmationKeyword = "DELETE"

    /// Pre-formatted once (not a bare Text(LocalizedStringKey) lookup) so
    /// both the visible instruction and its VoiceOver accessibilityLabel
    /// read "Type DELETE to confirm." rather than the raw "%@" template.
    private static let confirmPrompt = String(
        format: NSLocalizedString("settings.erase_confirm_prompt", comment: ""), confirmationKeyword
    )

    private var ownedClubs: [Club] {
        store.clubs.filter { $0.ownerRecordName == nil }
    }

    private var canErase: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == Self.confirmationKeyword
    }

    var body: some View {
        List {
            Section {
                Text("settings.erase_all_data_warning")
                    .foregroundStyle(.secondary)
            }

            if !ownedClubs.isEmpty {
                Section(header: Text("settings.erase_owned_clubs_warning").foregroundStyle(.red)) {
                    ForEach(ownedClubs) { club in
                        Text(club.name)
                    }
                }
            }

            Section {
                Text(Self.confirmPrompt)
                    .foregroundStyle(.secondary)
                TextField(Self.confirmationKeyword, text: $confirmationText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .accessibilityLabel(Text(Self.confirmPrompt))
            }

            Section {
                Button(role: .destructive) {
                    isErasing = true
                    Task {
                        await store.eraseAllData()
                        isErasing = false
                        showSuccess = true
                    }
                } label: {
                    HStack {
                        Text("settings.erase_confirm_button")
                        if isErasing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!canErase || isErasing)
            }
        }
        .navigationTitle("settings.erase_all_data")
        .navigationBarTitleDisplayMode(.inline)
        .alert("settings.erase_success", isPresented: $showSuccess) {
            Button("settings.erase_done") { dismiss() }
        }
    }
}
