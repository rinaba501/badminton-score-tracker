//
//  ClubDetailView.swift
//  badminton score tracker (iOS)
//
//  Roadmap Phase 5d: rename, member list, and per-club roster for a single
//  Club. Member list is read live from the CKShare (Phase 5c's
//  fetchOrCreateShare) when CloudKit sync is on, and always shows "You" as a
//  fallback first row so viewing a club never depends on CloudKit — see the
//  local-first invariant in ROADMAP.md. Since invite-sending UI (5e) doesn't
//  exist yet, a club's only real participant today is its owner, so the
//  fetched list filters out the `.owner` role to avoid double-listing "You".
//  Deleting/leaving a club never deletes match/player data — it only clears
//  clubId back to personal (nil) on every roster player and match record
//  tagged with it, then removes the club via the same AppStore.saveClubs
//  diffing that already routes owned vs. shared deletion correctly (Phase 5c).
//  iOS restyle of the Watch's ClubDetailView.
//

import SwiftUI
import CloudKit
import BadmintonCore

struct ClubDetailView: View {
    let clubId: UUID

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKeys.cloudKitSyncEnabled) private var cloudKitSyncEnabled = false

    @State private var name = ""
    @State private var participants: [String] = []
    @State private var loadingParticipants = true
    @State private var showRemoveConfirm = false
    @State private var editingPlayer: Player?

    private var club: Club? { store.clubs.first { $0.id == clubId } }
    private var isOwned: Bool { club?.ownerRecordName == nil }

    private var clubRoster: [Player] {
        store.roster.filter { $0.clubId == clubId }
    }

    var body: some View {
        List {
            if let club {
                Section {
                    TextField("clubs.name", text: $name)
                        .onSubmit { rename(to: name, currentName: club.name) }
                } header: {
                    Text("clubs.name")
                }

                Section {
                    Text("clubs.you")
                    if loadingParticipants {
                        ProgressView()
                    } else {
                        ForEach(participants, id: \.self) { participant in
                            Text(participant)
                        }
                    }
                } header: {
                    Text("clubs.members")
                }

                Section {
                    if clubRoster.isEmpty {
                        Text("settings.no_players")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(clubRoster) { player in
                            Button {
                                editingPlayer = player
                            } label: {
                                HStack(spacing: 10) {
                                    AvatarView(name: player.name, color: player.avatarColor, size: 30, iconName: player.iconName)
                                    Text(player.name).foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                    Button {
                        editingPlayer = Player(name: "", colorIndex: store.roster.count % Player.avatarColors.count, clubId: clubId)
                    } label: {
                        Label("clubs.add_player", systemImage: "plus")
                    }
                } header: {
                    Text("clubs.roster")
                }

                Section {
                    Button(role: .destructive) {
                        showRemoveConfirm = true
                    } label: {
                        Text(isOwned ? "clubs.delete_club" : "clubs.leave_club")
                    }
                }
            }
        }
        .navigationTitle(club?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let club { name = club.name }
            loadParticipants()
        }
        .confirmationDialog(
            isOwned ? "clubs.delete_confirm" : "clubs.leave_confirm",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button(isOwned ? "clubs.delete_club" : "clubs.leave_club", role: .destructive) {
                removeClub()
            }
        }
        .sheet(item: $editingPlayer) { player in
            PlayerEditView(
                initialPlayer: player,
                existingNames: store.roster.filter { $0.id != player.id }.map(\.name),
                clubs: store.clubs,
                onSave: savePlayer
            )
        }
    }

    private func rename(to newName: String, currentName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != currentName else { return }
        var updated = store.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].name = trimmed
        store.saveClubs(updated)
    }

    private func savePlayer(_ updated: Player) {
        var roster = store.roster
        if let idx = roster.firstIndex(where: { $0.id == updated.id }) {
            roster[idx] = updated
        } else {
            roster.append(updated)
        }
        store.saveRoster(roster)
        editingPlayer = nil
    }

    private func removeClub() {
        store.saveRoster(store.roster.map { player in
            var p = player
            if p.clubId == clubId { p.clubId = nil }
            return p
        })
        store.saveHistory(store.history.map { record in
            var r = record
            if r.clubId == clubId { r.clubId = nil }
            return r
        })
        store.saveClubs(store.clubs.filter { $0.id != clubId })
        dismiss()
    }

    private func loadParticipants() {
        guard cloudKitSyncEnabled, let club else {
            loadingParticipants = false
            return
        }
        loadingParticipants = true
        Task {
            do {
                let share = try await CloudKitSyncManager.shared.fetchOrCreateShare(for: club)
                let names = share.participants
                    .filter { $0.role != .owner }
                    .compactMap { participant -> String? in
                        if let components = participant.userIdentity.nameComponents {
                            return PersonNameComponentsFormatter().string(from: components)
                        }
                        return participant.userIdentity.lookupInfo?.emailAddress
                    }
                await MainActor.run {
                    participants = names
                    loadingParticipants = false
                }
            } catch {
                await MainActor.run { loadingParticipants = false }
            }
        }
    }
}
