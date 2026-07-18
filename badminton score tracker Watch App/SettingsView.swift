//
//  SettingsView.swift
//  badminton score tracker Watch App
//
//  Match format, audio, court theme, timer, and roster management.
//  Editing a player's name here propagates through match history via the
//  player's stable UUID.
//

import SwiftUI
import BadmintonCore

struct SettingsView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage(AppStorageKeys.gameMode) private var gameMode: GameMode = .singles
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.pointsToWin) private var pointsToWin: Int = 21
    @AppStorage(AppStorageKeys.gamesInMatch) private var gamesInMatch: Int = 3
    @AppStorage(AppStorageKeys.courtTheme) private var courtTheme: CourtTheme = .green
    @AppStorage(AppStorageKeys.announceScore) private var announceScore = true
    @AppStorage(AppStorageKeys.enableCrownScoring) private var enableCrownScoring = true
    @AppStorage(AppStorageKeys.timeModeEnabled) private var timeModeEnabled = false
    @AppStorage(AppStorageKeys.timeLimitMinutes) private var timeLimitMinutes = 10
    @AppStorage(AppStorageKeys.courtChangeRemindersEnabled) private var courtChangeRemindersEnabled = false
    @AppStorage(AppStorageKeys.enableSounds) private var enableSounds = true
    @AppStorage(AppStorageKeys.playerSortOrder) private var playerSortOrder: Player.SortOrder = .name
    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var storeManager: StoreManager
    @State private var editingPlayer: Player? = nil
    @State private var showAddPlayer = false
    @State private var showPaywall = false
    /// Where the theme picker snaps back to when a premium theme is tapped
    /// without the entitlement (tracks the last free selection; the paywall
    /// opens instead).
    @State private var lastFreeTheme: CourtTheme = .green
    @State private var pendingPlayerIdsToDelete: Set<Player.ID>?
    @State private var isSelectingPlayers = false
    @State private var selectedPlayerIds: Set<Player.ID> = []

    enum GameMode: String, Codable, CaseIterable {
        case singles = "Singles"
        case doubles = "Doubles"
    }

    private var roster: [Player] { appStore.roster }

    private var opponents: [Player] {
        Player.sortedPlayers(roster.filter { $0.name != myName }, order: playerSortOrder, history: appStore.history)
    }

    private func deletePlayers(at offsets: IndexSet) {
        pendingPlayerIdsToDelete = Set(offsets.map { opponents[$0].id })
    }

    private func confirmPendingPlayerDeletion() {
        guard let pendingPlayerIdsToDelete else { return }
        appStore.saveRoster(roster.filter { !pendingPlayerIdsToDelete.contains($0.id) })
        self.pendingPlayerIdsToDelete = nil
        exitPlayerSelection()
    }

    private func exitPlayerSelection() {
        isSelectingPlayers = false
        selectedPlayerIds = []
    }

    private func togglePlayerSelection(_ id: Player.ID) {
        if selectedPlayerIds.contains(id) {
            selectedPlayerIds.remove(id)
        } else {
            selectedPlayerIds.insert(id)
        }
    }

    private var allPlayersSelected: Bool {
        !opponents.isEmpty && Set(opponents.map(\.id)).isSubset(of: selectedPlayerIds)
    }

    private func togglePlayerSelectAll() {
        if allPlayersSelected {
            selectedPlayerIds.subtract(opponents.map(\.id))
        } else {
            selectedPlayerIds.formUnion(opponents.map(\.id))
        }
    }

    private var deletePlayersConfirmTitle: String {
        let count = pendingPlayerIdsToDelete?.count ?? 0
        guard count > 1 else { return NSLocalizedString("settings.delete_player_confirm", comment: "") }
        return String(format: NSLocalizedString("settings.delete_selected_players_confirm", comment: ""), count)
    }

    private func savePlayerEdit(_ updated: Player) {
        let old = roster.first(where: { $0.id == updated.id })

        // Write myName before any save* that enqueues Settings so the
        // materialize path reads the updated identity name.
        if let old, old.name != updated.name, old.name == myName {
            myName = updated.name
        }

        var r = roster
        if let idx = r.firstIndex(where: { $0.id == updated.id }) {
            r[idx] = updated
        } else {
            r.insert(updated, at: 0)
        }
        appStore.saveRoster(r)

        // Propagate name change to match history via player ID. `winner` is a
        // viewer-neutral RecordSide tag (see MatchModel.swift) — it never
        // duplicated a display name, so no rename patching is needed for it.
        if let old, old.name != updated.name {
            var history = appStore.history
            for i in history.indices {
                if history[i].myPlayerId == updated.id {
                    history[i].myName = updated.name
                }
                if history[i].opponentPlayerId == updated.id {
                    history[i].opponentName = updated.name
                }
            }
            appStore.saveHistory(history)
        }

        editingPlayer = nil
    }

    private func meAsPlayer() -> Player {
        roster.first(where: { $0.name == myName }) ?? Player(id: appStore.localPlayerId, name: myName, colorIndex: 0)
    }

    /// Capsule badge showing the current plan next to the Pro row — the row
    /// stays visible after purchase so the badge can flip from Free to Pro.
    private var planBadge: some View {
        let isPro = storeManager.entitlements.isPro
        return Text(LocalizedStringKey(isPro ? "paywall.plan_pro" : "paywall.plan_free"))
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background((isPro ? Color.yellow : Color.secondary).opacity(0.2))
            .foregroundStyle(isPro ? .yellow : .secondary)
            .clipShape(Capsule())
    }

    var body: some View {
        List {
            Section {
                Button(action: { showPaywall = true }) {
                    HStack {
                        Label(LocalizedStringKey("paywall.title"), systemImage: "crown.fill")
                            .foregroundColor(.yellow)
                        Spacer()
                        planBadge
                    }
                }
                .accessibilityElement(children: .combine)
            }

            Section(header: Text("settings.game_mode")) {
                Picker("settings.mode", selection: $gameMode) {
                    Text("settings.singles").tag(GameMode.singles)
                    Text("settings.doubles").tag(GameMode.doubles)
                }
            }

            Section(header: Text("settings.me")) {
                Button(action: { editingPlayer = meAsPlayer() }) {
                    HStack(spacing: 8) {
                        let me = meAsPlayer()
                        AvatarView(name: me.name, color: me.avatarColor, size: 28, iconName: me.iconName)
                        Text(myName)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("settings.players")) {
                Picker("settings.sort_order", selection: $playerSortOrder) {
                    Text("settings.sort_name").tag(Player.SortOrder.name)
                    Text("settings.sort_most_played").tag(Player.SortOrder.mostPlayed)
                    Text("settings.sort_recently_used").tag(Player.SortOrder.recentlyUsed)
                    Text("settings.sort_created").tag(Player.SortOrder.created)
                    Text("settings.sort_name_desc").tag(Player.SortOrder.nameDescending)
                }

                if roster.isEmpty {
                    Text("settings.no_players")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    HStack {
                        Button(isSelectingPlayers ? "settings.cancel_select" : "settings.select_players") {
                            isSelectingPlayers.toggle()
                            if !isSelectingPlayers { selectedPlayerIds = [] }
                        }
                        .font(.caption)
                        if isSelectingPlayers {
                            Spacer()
                            Button(allPlayersSelected ? "settings.deselect_all_players" : "settings.select_all_players") {
                                togglePlayerSelectAll()
                            }
                            .font(.caption)
                        }
                    }

                    ForEach(opponents) { player in
                        Button(action: {
                            if isSelectingPlayers {
                                togglePlayerSelection(player.id)
                            } else {
                                editingPlayer = player
                            }
                        }) {
                            HStack(spacing: 8) {
                                if isSelectingPlayers {
                                    Image(systemName: selectedPlayerIds.contains(player.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundColor(selectedPlayerIds.contains(player.id) ? .yellow : .secondary)
                                }
                                AvatarView(name: player.name, color: player.avatarColor, size: 24, iconName: player.iconName)
                                Text(player.name)
                                    .font(.caption)
                                Spacer()
                                if !isSelectingPlayers {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(isSelectingPlayers && selectedPlayerIds.contains(player.id) ? .isSelected : [])
                        .contextMenu {
                            if !isSelectingPlayers {
                                Button(role: .destructive) {
                                    pendingPlayerIdsToDelete = [player.id]
                                } label: {
                                    Label("settings.delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .onDelete(perform: isSelectingPlayers ? nil : deletePlayers)

                    if isSelectingPlayers {
                        Button(role: .destructive) {
                            pendingPlayerIdsToDelete = selectedPlayerIds.intersection(Set(opponents.map(\.id)))
                        } label: {
                            Text(String(format: NSLocalizedString("settings.delete_selected_players", comment: ""),
                                        selectedPlayerIds.intersection(Set(opponents.map(\.id))).count))
                        }
                        .disabled(selectedPlayerIds.isEmpty)
                    }
                }

                if !isSelectingPlayers {
                    Button(action: {
                        let appearance = Player.randomDefaultAppearance()
                        editingPlayer = Player(name: "", colorIndex: appearance.colorIndex, iconName: appearance.iconName)
                    }) {
                        Label("settings.add_player", systemImage: "plus")
                    }
                }
            }

            Section(header: Text("settings.clubs")) {
                NavigationLink(destination: ClubsView()) {
                    Label(LocalizedStringKey("settings.manage_clubs"), systemImage: "person.3")
                }
            }

            Section(header: Text("settings.friends")) {
                NavigationLink(destination: FriendsView()) {
                    Label(LocalizedStringKey("settings.friends"), systemImage: "person.2.circle")
                }
            }

            Section(header: Text("settings.crown")) {
                Toggle("settings.crown_scoring", isOn: $enableCrownScoring)
            }

            Section(header: Text("settings.audio")) {
                Toggle("settings.sound_effects", isOn: $enableSounds)
                Toggle("settings.announce_score", isOn: $announceScore)
            }

            CourtThemeSection(courtTheme: $courtTheme, lastFreeTheme: $lastFreeTheme, showPaywall: $showPaywall)

            Section(header: Text("settings.match_format")) {
                Picker("settings.points_to_win", selection: $pointsToWin) {
                    Text("settings.pts_11").tag(11)
                    Text("settings.pts_15").tag(15)
                    Text("settings.pts_21").tag(21)
                }
                Picker("settings.games_in_match", selection: $gamesInMatch) {
                    Text("settings.games_1").tag(1)
                    Text("settings.games_3").tag(3)
                    Text("settings.games_5").tag(5)
                }
                Toggle("settings.court_changes", isOn: $courtChangeRemindersEnabled)
            }
            .onChange(of: pointsToWin) { _ in
                CloudKitSyncManager.shared.enqueueSettingsChange()
            }
            .onChange(of: gamesInMatch) { _ in
                CloudKitSyncManager.shared.enqueueSettingsChange()
            }
            .onChange(of: courtChangeRemindersEnabled) { _ in
                CloudKitSyncManager.shared.enqueueSettingsChange()
            }

            Section(header: Text("settings.timer")) {
                Toggle("settings.timer_enable", isOn: $timeModeEnabled)
                if timeModeEnabled {
                    VStack(spacing: 6) {
                        Text(String(format: NSLocalizedString("settings.minutes", comment: ""), timeLimitMinutes))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                        HStack(spacing: 6) {
                            ForEach([(-5, "-5"), (-1, "-1"), (1, "+1"), (5, "+5")], id: \.0) { delta, label in
                                Button(label) { timeLimitMinutes = min(99, max(1, timeLimitMinutes + delta)) }
                                    .font(.caption2)
                                    .foregroundColor(delta < 0 ? .red : .green)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(6)
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                NavigationLink(destination: OnboardingView()) {
                    Label(LocalizedStringKey("onboarding.title"), systemImage: "hand.raised")
                }
            }

            Section(header: Text("settings.danger_zone")) {
                NavigationLink(destination: EraseDataView(currentView: $currentView)) {
                    Label(LocalizedStringKey("settings.erase_all_data"), systemImage: "trash.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("settings.back") { currentView = .menu }
            }
        }
        .sheet(item: $editingPlayer) { player in
            let others = roster.filter { $0.id != player.id }.map { $0.name }
            PlayerEditView(initialPlayer: player, existingNames: others, clubs: appStore.clubs, onSave: savePlayerEdit)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .confirmationDialog(
            deletePlayersConfirmTitle,
            isPresented: Binding(
                get: { pendingPlayerIdsToDelete != nil },
                set: { if !$0 { pendingPlayerIdsToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("settings.delete", role: .destructive) { confirmPendingPlayerDeletion() }
        }
        .onAppear {
            if !courtTheme.isPremium { lastFreeTheme = courtTheme }
        }
    }
}
