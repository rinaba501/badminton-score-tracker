//
//  SettingsView.swift
//  badminton score tracker Watch App
//
//  Match format, audio, court theme, timer, and roster management.
//  Editing a player's name here propagates through match history via the
//  player's stable UUID.
//

import SwiftUI

struct SettingsView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("gameMode") private var gameMode: GameMode = .singles
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("pointsToWin") private var pointsToWin: Int = 21
    @AppStorage("gamesInMatch") private var gamesInMatch: Int = 3
    @AppStorage("courtTheme") private var courtTheme: CourtTheme = .green
    @AppStorage("announceScore") private var announceScore = true
    @AppStorage("enableCrownScoring") private var enableCrownScoring = true
    @AppStorage("timeModeEnabled") private var timeModeEnabled = false
    @AppStorage("timeLimitMinutes") private var timeLimitMinutes = 10
    @AppStorage("enableSounds") private var enableSounds = true
    @EnvironmentObject private var appStore: AppStore
    @State private var editingPlayer: Player? = nil

    enum GameMode: String, Codable, CaseIterable {
        case singles = "Singles"
        case doubles = "Doubles"
    }

    private var roster: [Player] { appStore.roster }

    private var opponents: [Player] { roster.filter { $0.name != myName } }

    private func deletePlayers(at offsets: IndexSet) {
        let toDelete = Set(offsets.map { opponents[$0].id })
        appStore.saveRoster(roster.filter { !toDelete.contains($0.id) })
    }

    private func savePlayerEdit(_ updated: Player) {
        let old = roster.first(where: { $0.id == updated.id })

        var r = roster
        if let idx = r.firstIndex(where: { $0.id == updated.id }) {
            r[idx] = updated
        } else {
            r.insert(updated, at: 0)
        }
        appStore.saveRoster(r)

        // Propagate name change to match history via player ID
        if let old, old.name != updated.name {
            var history = appStore.history
            for i in history.indices {
                if history[i].myPlayerId == updated.id {
                    if history[i].winner == history[i].myName { history[i].winner = updated.name }
                    history[i].myName = updated.name
                }
                if history[i].opponentPlayerId == updated.id {
                    if history[i].winner == history[i].opponentName { history[i].winner = updated.name }
                    history[i].opponentName = updated.name
                }
            }
            appStore.saveHistory(history)

            // Also update myName AppStorage if this is the "me" player
            if old.name == myName { myName = updated.name }
        }

        editingPlayer = nil
    }

    private func meAsPlayer() -> Player {
        roster.first(where: { $0.name == myName }) ?? Player(name: myName, colorIndex: 0)
    }

    var body: some View {
        List {
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
                if roster.isEmpty {
                    Text("settings.no_players")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(opponents) { player in
                        Button(action: { editingPlayer = player }) {
                            HStack(spacing: 8) {
                                AvatarView(name: player.name, color: player.avatarColor, size: 24, iconName: player.iconName)
                                Text(player.name)
                                    .font(.caption)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                appStore.saveRoster(roster.filter { $0.id != player.id })
                            } label: {
                                Label("settings.delete", systemImage: "trash")
                            }
                        }
                    }
                    .onDelete(perform: deletePlayers)
                }
            }

            Section(header: Text("settings.crown")) {
                Toggle("settings.crown_scoring", isOn: $enableCrownScoring)
            }

            Section(header: Text("settings.audio")) {
                Toggle("settings.sound_effects", isOn: $enableSounds)
                Toggle("settings.announce_score", isOn: $announceScore)
            }

            Section(header: Text("settings.court_theme")) {
                Picker("settings.theme", selection: $courtTheme) {
                    ForEach(CourtTheme.allCases, id: \.self) { theme in
                        HStack {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 12, height: 12)
                            Text(LocalizedStringKey("theme.\(theme.rawValue.lowercased())"))
                        }
                        .tag(theme)
                    }
                }
            }

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
            PlayerEditView(initialPlayer: player, existingNames: others, onSave: savePlayerEdit)
        }
    }
}
