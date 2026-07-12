//
//  ProfileView.swift
//  badminton score tracker (iOS)
//
//  Dedicated "who am I" page, split out from the shared roster (RosterView,
//  which now only manages other players) and from Friends (FriendsView,
//  which now only manages the friend graph). Owns name/avatar editing for
//  "Me" and the CloudKit account-link toggle. iOS-only: on watchOS "Me" stays
//  a distinguished row inside Settings/Roster, since the small screen doesn't
//  warrant another top-level nav destination.
//

import SwiftUI
import BadmintonCore

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.accountLinked) private var accountLinked = false

    @State private var editingPlayer: Player?
    @State private var promptingForName = false
    @State private var pendingName = ""
    @State private var pendingAction: (() -> Void)?
    @State private var showUnlinkConfirm = false

    // Backstop for anyone who skipped the first-launch prompt (ContentView) —
    // linkAccount() still needs a real name before it publishes a FriendProfile.
    private var needsName: Bool {
        myName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || myName == Player.defaultMyName
    }

    private var roster: [Player] { store.roster }

    private func meAsPlayer() -> Player {
        roster.first(where: { $0.name == myName }) ?? Player(id: store.localPlayerId, name: myName, colorIndex: 0)
    }

    var body: some View {
        List {
            Section {
                Button {
                    editingPlayer = meAsPlayer()
                } label: {
                    let me = meAsPlayer()
                    HStack(spacing: 10) {
                        AvatarView(name: myName, color: me.avatarColor, size: 44, iconName: me.iconName)
                        Text(myName).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section("profile.account_section_header") {
                if accountLinked {
                    HStack(spacing: 8) {
                        AvatarView(name: myName, color: meAsPlayer().avatarColor, size: 24, iconName: meAsPlayer().iconName)
                        Text(String(format: NSLocalizedString("profile.linked_as", comment: ""), myName))
                    }
                    Button("profile.unlink_account", role: .destructive) { showUnlinkConfirm = true }
                } else {
                    Button {
                        linkAccount()
                    } label: {
                        Label("profile.link_account", systemImage: "link")
                    }
                }
            }
        }
        .navigationTitle("ios.profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingPlayer) { player in
            PlayerEditView(
                initialPlayer: player,
                existingNames: roster.filter { $0.name != myName }.map(\.name),
                clubs: store.clubs,
                onSave: saveMe
            )
        }
        .sheet(isPresented: $promptingForName) {
            namePrompt
        }
        .confirmationDialog(
            "profile.unlink_account_confirm",
            isPresented: $showUnlinkConfirm,
            titleVisibility: .visible
        ) {
            Button("profile.unlink_account", role: .destructive) { unlinkAccount() }
        }
    }

    // MARK: - Pieces

    private var namePrompt: some View {
        NavigationStack {
            Form {
                Section {
                    Text("friends.display_name_prompt_message")
                        .foregroundStyle(.secondary)
                    TextField("friends.display_name_placeholder", text: $pendingName)
                }
            }
            .navigationTitle(Text("friends.display_name_prompt_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("history.cancel") {
                        pendingAction = nil
                        promptingForName = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("playeredit.save") { savePendingName() }
                        .disabled(pendingName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - Actions

    // Write myName before any save* that enqueues Settings so the
    // materialize path reads the updated identity name (same ordering
    // RosterView's savePlayerEdit used before this moved here).
    private func saveMe(_ updated: Player) {
        let old = roster.first(where: { $0.id == updated.id })
        let renamed = old != nil && old?.name != updated.name
        if renamed {
            myName = updated.name
        }

        var r = roster
        if let idx = r.firstIndex(where: { $0.id == updated.id }) {
            r[idx] = updated
        } else {
            r.insert(updated, at: 0)
        }
        store.saveRoster(r)

        if renamed {
            var history = store.history
            for i in history.indices {
                if history[i].myPlayerId == updated.id {
                    history[i].myName = updated.name
                }
                if history[i].opponentPlayerId == updated.id {
                    history[i].opponentName = updated.name
                }
            }
            store.saveHistory(history)
        }

        editingPlayer = nil
    }

    private func savePendingName() {
        let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        myName = trimmed
        promptingForName = false
        CloudKitSyncManager.shared.enqueueSettingsChange()
        Task { @MainActor in
            try? await CloudKitSyncManager.shared.ensureMyProfileExists(displayName: Player.displayName(for: myName))
            pendingAction?()
            pendingAction = nil
        }
    }

    // Explicit "link this device to one CloudKit account" opt-in flag —
    // purely informational today (Club's "you" row/badge no longer branches
    // on it, since there's only one identity to show), kept for future use.
    private func linkAccount() {
        guard !needsName else {
            pendingName = ""
            pendingAction = { [self] in
                accountLinked = true
                CloudKitSyncManager.shared.enqueueSettingsChange()
            }
            promptingForName = true
            return
        }
        accountLinked = true
        CloudKitSyncManager.shared.enqueueSettingsChange()
    }

    // Non-destructive: does not delete the FriendProfile, remove friends, or
    // leave clubs — just detaches the local link so Club stops showing the
    // shared name. Re-linking later restores it.
    private func unlinkAccount() {
        accountLinked = false
        CloudKitSyncManager.shared.enqueueSettingsChange()
    }
}
