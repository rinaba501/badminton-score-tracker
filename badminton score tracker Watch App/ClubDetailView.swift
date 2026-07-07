//
//  ClubDetailView.swift
//  badminton score tracker Watch App
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
//

import SwiftUI
import CloudKit
import BadmintonCore

struct ClubDetailView: View {
    let clubId: UUID

    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKeys.cloudKitSyncEnabled) private var cloudKitSyncEnabled = false
    @AppStorage(AppStorageKeys.clubLastViewedActivity) private var lastViewedData = Data()

    @State private var name = ""
    @State private var participants: [String] = []
    @State private var loadingParticipants = true
    @State private var showRemoveConfirm = false
    @State private var editingPlayer: Player?

    private var club: Club? { appStore.clubs.first { $0.id == clubId } }
    private var isOwned: Bool { club?.ownerRecordName == nil }

    private var clubRoster: [Player] {
        appStore.roster.filter { $0.clubId == clubId }
    }

    private var requireMatchConfirmation: Bool { club?.requireMatchConfirmation ?? false }

    private var clubMatches: [MatchRecord] {
        appStore.history.filter { $0.clubId == clubId }
    }

    private var pendingMatches: [MatchRecord] {
        requireMatchConfirmation ? clubMatches.filter { !$0.isConfirmed } : []
    }

    private var standings: [StatsCalculator.StandingsEntry] {
        StatsCalculator.standings(history: clubMatches.filter { $0.isConfirmed || !requireMatchConfirmation })
    }

    private var activityFeed: [StatsCalculator.ActivityFeedEntry] {
        StatsCalculator.activityFeed(history: clubMatches.filter { $0.isConfirmed || !requireMatchConfirmation })
    }

    var body: some View {
        List {
            if let club {
                Section(header: Text("clubs.name")) {
                    TextField("clubs.name", text: $name)
                        .onSubmit { rename(to: name, currentName: club.name) }
                    if isOwned {
                        Toggle("clubs.require_confirmation", isOn: Binding(
                            get: { requireMatchConfirmation },
                            set: { setRequireMatchConfirmation($0) }
                        ))
                        .font(.caption)
                    }
                }

                if !pendingMatches.isEmpty {
                    Section(header: Text("clubs.pending_confirmation")) {
                        ForEach(pendingMatches) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(record.myName) vs \(record.opponentName)")
                                    .font(.caption)
                                Text("\(record.myGamesWon)-\(record.opponentGamesWon)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Button("clubs.confirm_match") { confirmMatch(record) }
                                        .font(.caption2)
                                    Button("clubs.decline_match", role: .destructive) { declineMatch(record) }
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("clubs.activity")) {
                    if activityFeed.isEmpty {
                        Text("stats.no_matches")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(activityFeed) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(entry.myName) vs \(entry.opponentName)")
                                    .font(.caption)
                                Text("\(entry.myGamesWon)-\(entry.opponentGamesWon)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text("clubs.members")) {
                    Text("clubs.you")
                        .font(.caption)
                    if loadingParticipants {
                        ProgressView()
                    } else {
                        ForEach(participants, id: \.self) { participant in
                            Text(participant).font(.caption)
                        }
                    }
                }

                Section(header: Text("clubs.standings")) {
                    if standings.isEmpty {
                        Text("stats.no_matches")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(standings) { entry in
                            HStack {
                                Text(entry.name).font(.caption)
                                Spacer()
                                Text("\(entry.wins)-\(entry.losses)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                Section(header: Text("clubs.roster")) {
                    if clubRoster.isEmpty {
                        Text("settings.no_players")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(clubRoster) { player in
                            Button(action: { editingPlayer = player }) {
                                HStack(spacing: 8) {
                                    AvatarView(name: player.name, color: player.avatarColor, size: 24, iconName: player.iconName)
                                    Text(player.name).font(.caption)
                                }
                            }
                        }
                    }
                    Button(action: {
                        editingPlayer = Player(name: "", colorIndex: appStore.roster.count % Player.avatarColors.count, clubId: clubId)
                    }) {
                        Label("clubs.add_player", systemImage: "plus")
                    }
                }

                Section {
                    Button(role: .destructive, action: { showRemoveConfirm = true }) {
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
            markActivityViewed()
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
            let others = appStore.roster.filter { $0.id != player.id }.map(\.name)
            PlayerEditView(initialPlayer: player, existingNames: others, clubs: appStore.clubs, onSave: savePlayer)
        }
    }

    private func rename(to newName: String, currentName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != currentName else { return }
        var updated = appStore.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].name = trimmed
        appStore.saveClubs(updated)
    }

    private func setRequireMatchConfirmation(_ newValue: Bool) {
        var updated = appStore.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].requireMatchConfirmation = newValue
        appStore.saveClubs(updated)
    }

    private func confirmMatch(_ record: MatchRecord) {
        var history = appStore.history
        guard let idx = history.firstIndex(where: { $0.id == record.id }) else { return }
        history[idx].isConfirmed = true
        appStore.saveHistory(history)
    }

    private func declineMatch(_ record: MatchRecord) {
        var history = appStore.history
        guard let idx = history.firstIndex(where: { $0.id == record.id }) else { return }
        history[idx].clubId = nil
        appStore.saveHistory(history)
    }

    private func savePlayer(_ updated: Player) {
        var roster = appStore.roster
        if let idx = roster.firstIndex(where: { $0.id == updated.id }) {
            roster[idx] = updated
        } else {
            roster.append(updated)
        }
        appStore.saveRoster(roster)
        editingPlayer = nil
    }

    private func removeClub() {
        appStore.saveRoster(appStore.roster.map { player in
            var p = player
            if p.clubId == clubId { p.clubId = nil }
            return p
        })
        appStore.saveHistory(appStore.history.map { record in
            var r = record
            if r.clubId == clubId { r.clubId = nil }
            return r
        })
        appStore.saveClubs(appStore.clubs.filter { $0.id != clubId })
        dismiss()
    }

    private func markActivityViewed() {
        var lastViewed = ClubActivityCodec.decode(lastViewedData)
        lastViewed[clubId.uuidString] = Date()
        lastViewedData = ClubActivityCodec.encode(lastViewed)
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
