//
//  StatsView.swift
//  badminton score tracker (iOS)
//
//  Per-player aggregate stats (record, win rate, streaks, averages) and
//  head-to-head breakdowns. All math lives in BadmintonCore.StatsCalculator
//  (shared with the Watch); this screen binds it to the selected player and
//  is pushed via NavigationStack (no currentView binding).
//

import SwiftUI
import BadmintonCore

struct StatsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName

    @State private var selectedPlayer: String = ""

    private var history: [MatchRecord] { store.history }
    private var roster: [Player] { store.roster }

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
    private var winRate: Double { StatsCalculator.winRate(player: activePlayer, playerHistory: playerHistory) }
    private var avgPointsScored: Double { StatsCalculator.avgPointsScored(player: activePlayer, playerHistory: playerHistory) }
    private var avgMatchDuration: TimeInterval { StatsCalculator.avgMatchDuration(playerHistory: playerHistory) }
    private var longestStreak: Int { StatsCalculator.longestStreak(player: activePlayer, playerHistory: playerHistory) }

    var body: some View {
        Group {
            if history.isEmpty {
                VStack {
                    Spacer()
                    Text("stats.no_matches").foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    if allPlayers.count > 1 {
                        Section {
                            Picker("stats.player", selection: $selectedPlayer) {
                                ForEach(allPlayers, id: \.self) { name in
                                    if name == myName {
                                        Label(Player.displayName(for: name), systemImage: "person.fill").tag(name)
                                    } else {
                                        Text(Player.displayName(for: name)).tag(name)
                                    }
                                }
                            }
                        }
                    }

                    Section(header: Text(Player.displayName(for: activePlayer))) {
                        StatRow(labelKey: "stats.matches", value: "\(totalMatches)")
                        StatRow(labelKey: "stats.wins", value: "\(wins)")
                        StatRow(labelKey: "stats.losses", value: "\(losses)")
                        StatRow(labelKey: "stats.win_rate", value: String(format: "%.0f%%", winRate))
                        StatRow(labelKey: "stats.avg_points", value: String(format: "%.1f", avgPointsScored))
                        StatRow(labelKey: "stats.best_streak", value: "\(longestStreak)")
                        if avgMatchDuration > 0 {
                            StatRow(labelKey: "stats.avg_duration", value: StatsCalculator.durationString(avgMatchDuration))
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
        }
        .navigationTitle("stats.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedPlayer.isEmpty { selectedPlayer = myName }
        }
    }
}

struct StatRow: View {
    let label: String?
    let labelKey: LocalizedStringKey?
    let value: String

    init(label: String, value: String) {
        self.label = label
        self.labelKey = nil
        self.value = value
    }

    init(labelKey: LocalizedStringKey, value: String) {
        self.label = nil
        self.labelKey = labelKey
        self.value = value
    }

    var body: some View {
        HStack {
            if let labelKey {
                Text(labelKey).foregroundStyle(.secondary)
            } else if let label {
                Text(label).foregroundStyle(.secondary)
            }
            Spacer()
            Text(value).fontWeight(.semibold)
        }
    }
}
