//
//  ClubDetailView.swift
//  badminton score tracker (iOS)
//
//  Roadmap Phase 5d: rename, member list, and per-club roster for a single
//  Club. Member list is read live from the CKShare (Phase 5c's
//  fetchOrCreateShare) when CloudKit sync is on, and always shows "You" as a
//  fallback first row so viewing a club never depends on CloudKit — see the
//  local-first invariant in ROADMAP.md. The fetched list filters out the
//  `.owner` role to avoid double-listing "You".
//  Phase 5e adds the owner-only "Invite" button (CloudSharingView, a
//  UICloudSharingController wrapper — iOS-only, no watchOS equivalent).
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
    @State private var shareBox: ShareBox?
    @State private var isPreparingShare = false
    @State private var shareErrorMessage: String?

    private var club: Club? { store.clubs.first { $0.id == clubId } }
    private var isOwned: Bool { club?.ownerRecordName == nil }

    private var clubRoster: [Player] {
        store.roster.filter { $0.clubId == clubId }
    }

    private var requireMatchConfirmation: Bool { club?.requireMatchConfirmation ?? false }

    private var clubMatches: [MatchRecord] {
        store.history.filter { $0.clubId == clubId }
    }

    private var pendingMatches: [MatchRecord] {
        requireMatchConfirmation ? clubMatches.filter { !$0.isConfirmed } : []
    }

    private var standings: [StatsCalculator.StandingsEntry] {
        StatsCalculator.standings(history: clubMatches.filter { $0.isConfirmed || !requireMatchConfirmation })
    }

    var body: some View {
        List {
            if let club {
                Section {
                    TextField("clubs.name", text: $name)
                        .onSubmit { rename(to: name, currentName: club.name) }
                    if isOwned {
                        Toggle("clubs.require_confirmation", isOn: Binding(
                            get: { requireMatchConfirmation },
                            set: { setRequireMatchConfirmation($0) }
                        ))
                    }
                } header: {
                    Text("clubs.name")
                }

                if !pendingMatches.isEmpty {
                    Section {
                        ForEach(pendingMatches) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(record.myName) vs \(record.opponentName)")
                                Text("\(record.myGamesWon)-\(record.opponentGamesWon)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("clubs.confirm_match") { confirmMatch(record) }
                                    Button("clubs.decline_match", role: .destructive) { declineMatch(record) }
                                }
                            }
                        }
                    } header: {
                        Text("clubs.pending_confirmation")
                    }
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
                    if isOwned && cloudKitSyncEnabled {
                        Button {
                            Task { await prepareShare(for: club) }
                        } label: {
                            if isPreparingShare {
                                ProgressView()
                            } else {
                                Label("clubs.invite", systemImage: "person.badge.plus")
                            }
                        }
                        .disabled(isPreparingShare)
                    }
                } header: {
                    Text("clubs.members")
                }

                Section {
                    if standings.isEmpty {
                        Text("stats.no_matches")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(standings) { entry in
                            HStack {
                                Text(entry.name)
                                Spacer()
                                Text("\(entry.wins)-\(entry.losses)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("clubs.standings")
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
        .sheet(item: $shareBox) { box in
            CloudSharingView(share: box.share, container: CloudKitSyncManager.shared.ckContainer, itemTitle: club?.name ?? "")
                .onDisappear { loadParticipants() }
        }
        .alert("clubs.invite_failed", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("common.ok") { shareErrorMessage = nil }
        } message: {
            Text(shareErrorMessage ?? "")
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

    private func setRequireMatchConfirmation(_ newValue: Bool) {
        var updated = store.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].requireMatchConfirmation = newValue
        store.saveClubs(updated)
    }

    private func confirmMatch(_ record: MatchRecord) {
        var history = store.history
        guard let idx = history.firstIndex(where: { $0.id == record.id }) else { return }
        history[idx].isConfirmed = true
        store.saveHistory(history)
    }

    private func declineMatch(_ record: MatchRecord) {
        var history = store.history
        guard let idx = history.firstIndex(where: { $0.id == record.id }) else { return }
        history[idx].clubId = nil
        store.saveHistory(history)
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

    private func prepareShare(for club: Club?) async {
        guard let club else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        do {
            let share = try await CloudKitSyncManager.shared.fetchOrCreateShare(for: club)
            shareBox = ShareBox(share: share)
        } catch {
            shareErrorMessage = error.localizedDescription
        }
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

/// CKShare isn't Identifiable, so this wraps it for `.sheet(item:)`.
private struct ShareBox: Identifiable {
    let id = UUID()
    let share: CKShare
}
