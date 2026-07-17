//
//  RosterView.swift
//  badminton score tracker (iOS)
//
//  Roster management: add / rename / delete saved players, choose sort
//  order. Ported from the Watch's SettingsView roster section — same
//  AppStore.saveRoster call pattern and the same rename→history propagation
//  (a rename updates the player's name in every past match via player id).
//  "Me" editing lives in ProfileView, not here; guests never persist.
//

import SwiftUI
import BadmintonCore

struct RosterView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.playerSortOrder) private var playerSortOrder: Player.SortOrder = .name

    @State private var editingPlayer: Player?
    @State private var pendingPlayerIdsToDelete: Set<Player.ID>?

    private var roster: [Player] { store.roster }

    private var opponents: [Player] {
        Player.sortedPlayers(roster.filter { $0.name != myName }, order: playerSortOrder, history: store.history)
    }

    private func deletePlayers(at offsets: IndexSet) {
        pendingPlayerIdsToDelete = Set(offsets.map { opponents[$0].id })
    }

    private func confirmPendingPlayerDeletion() {
        guard let pendingPlayerIdsToDelete else { return }
        store.saveRoster(roster.filter { !pendingPlayerIdsToDelete.contains($0.id) })
        self.pendingPlayerIdsToDelete = nil
    }

    private func savePlayerEdit(_ updated: Player) {
        let old = roster.first(where: { $0.id == updated.id })

        var r = roster
        if let idx = r.firstIndex(where: { $0.id == updated.id }) {
            r[idx] = updated
        } else {
            r.insert(updated, at: 0)
        }
        store.saveRoster(r)

        // Propagate name change to match history via player ID. `winner` is a
        // viewer-neutral RecordSide tag (see MatchModel.swift) — it never
        // duplicated a display name, so no rename patching is needed for it.
        if let old, old.name != updated.name {
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

    var body: some View {
        List {
            Section {
                Picker("settings.sort_order", selection: $playerSortOrder) {
                    Text("settings.sort_name").tag(Player.SortOrder.name)
                    Text("settings.sort_most_played").tag(Player.SortOrder.mostPlayed)
                    Text("settings.sort_recently_used").tag(Player.SortOrder.recentlyUsed)
                    Text("settings.sort_created").tag(Player.SortOrder.created)
                    Text("settings.sort_name_desc").tag(Player.SortOrder.nameDescending)
                }

                if opponents.isEmpty {
                    Text("settings.no_players")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(opponents) { player in
                        Button {
                            editingPlayer = player
                        } label: {
                            playerRow(name: player.name, color: player.avatarColor, iconName: player.iconName)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deletePlayers)
                }

                Button {
                    let appearance = Player.randomDefaultAppearance()
                    editingPlayer = Player(name: "", colorIndex: appearance.colorIndex, iconName: appearance.iconName)
                } label: {
                    Label("settings.add_player", systemImage: "plus")
                }
            }
        }
        .navigationTitle("settings.players")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingPlayer) { player in
            PlayerEditView(initialPlayer: player,
                           existingNames: roster.filter { $0.id != player.id }.map(\.name),
                           clubs: store.clubs,
                           onSave: savePlayerEdit)
        }
        .confirmationDialog(
            "settings.delete_player_confirm",
            isPresented: Binding(
                get: { pendingPlayerIdsToDelete != nil },
                set: { if !$0 { pendingPlayerIdsToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("settings.delete", role: .destructive) { confirmPendingPlayerDeletion() }
        }
    }

    private func playerRow(name: String, color: Color, iconName: String?) -> some View {
        HStack(spacing: 10) {
            AvatarView(name: name, color: color, size: 30, iconName: iconName)
            Text(name).foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
