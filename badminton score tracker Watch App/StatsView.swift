//
//  StatsView.swift
//  badminton score tracker Watch App
//
//  Per-player aggregate stats (record, win rate, streaks, averages) and
//  head-to-head breakdowns derived from match history.
//

import SwiftUI
import BadmintonCore

struct StatsView: View {
    @Binding var currentView: ContentView.AppView
    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName

    @State private var selectedPlayer: String = ""
    @State private var selectedClubId: UUID?

    private var history: [MatchRecord] { appStore.history.filter { $0.clubId == selectedClubId } }
    private var roster: [Player] { appStore.roster.filter { $0.clubId == selectedClubId } }

    // The stats engine lives in BadmintonCore.StatsCalculator; these
    // properties just bind it to this screen's selection state.

    private var allPlayers: [String] {
        StatsCalculator.allPlayers(history: history, hoisting: myName)
    }

    private var activePlayer: String {
        selectedPlayer.isEmpty ? myName : selectedPlayer
    }

    private var playerHistory: [MatchRecord] {
        StatsCalculator.playerHistory(history, player: activePlayer)
    }

    private var opponents: [String] {
        StatsCalculator.opponents(of: activePlayer, playerHistory: playerHistory)
    }

    private var totalMatches: Int { playerHistory.count }
    private var wins: Int { StatsCalculator.wins(player: activePlayer, playerHistory: playerHistory) }
    private var losses: Int { totalMatches - wins }

    private var winRate: Double {
        StatsCalculator.winRate(player: activePlayer, playerHistory: playerHistory)
    }

    private var avgPointsScored: Double {
        StatsCalculator.avgPointsScored(player: activePlayer, playerHistory: playerHistory)
    }

    private var avgMatchDuration: TimeInterval {
        StatsCalculator.avgMatchDuration(playerHistory: playerHistory)
    }

    private var longestStreak: Int {
        StatsCalculator.longestStreak(player: activePlayer, playerHistory: playerHistory)
    }

    private var clubPicker: some View {
        Picker("clubs.filter_label", selection: $selectedClubId) {
            Text("clubs.filter_personal").tag(UUID?.none)
            ForEach(appStore.clubs) { club in
                Text(club.name).tag(UUID?.some(club.id))
            }
        }
    }

    var body: some View {
        List {
            if !appStore.clubs.isEmpty {
                Section {
                    clubPicker
                }
            }

            if history.isEmpty {
                Section {
                    Text("stats.no_matches")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            } else {
                if allPlayers.count > 1 {
                    Section {
                        Picker("stats.player", selection: $selectedPlayer) {
                            ForEach(allPlayers, id: \.self) { name in
                                if name == myName {
                                    Label(Player.displayName(for: name), systemImage: "person.fill")
                                        .tag(name)
                                } else {
                                    Text(Player.displayName(for: name)).tag(name)
                                }
                            }
                        }
                    }
                }

                Section(header: Text(Player.displayName(for: activePlayer))) {
                    StatRow(label: NSLocalizedString("stats.matches", comment: ""), value: "\(totalMatches)")
                    StatRow(label: NSLocalizedString("stats.wins", comment: ""), value: "\(wins)")
                    StatRow(label: NSLocalizedString("stats.losses", comment: ""), value: "\(losses)")
                    StatRow(label: NSLocalizedString("stats.win_rate", comment: ""), value: String(format: "%.0f%%", winRate))
                    StatRow(label: NSLocalizedString("stats.avg_points", comment: ""), value: String(format: "%.1f", avgPointsScored))
                    StatRow(label: NSLocalizedString("stats.best_streak", comment: ""), value: "\(longestStreak)")
                    if avgMatchDuration > 0 {
                        StatRow(label: NSLocalizedString("stats.avg_duration", comment: ""), value: StatsCalculator.durationString(avgMatchDuration))
                    }
                }

                if !opponents.isEmpty {
                    Section(header: Text("stats.head_to_head")) {
                        ForEach(opponents, id: \.self) { opp in
                            let record = StatsCalculator.headToHead(player: activePlayer, opponent: opp, history: history, roster: roster)
                            StatRow(label: Player.displayName(for: opp), value: "\(record.wins)W – \(record.losses)L")
                        }
                    }
                }
            }
        }
        .navigationTitle("stats.title")
        .onAppear {
            if selectedPlayer.isEmpty { selectedPlayer = myName }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("stats.back") { currentView = .menu }
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}
