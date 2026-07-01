//
//  StatsView.swift
//  badminton score tracker Watch App
//
//  Per-player aggregate stats (record, win rate, streaks, averages) and
//  head-to-head breakdowns derived from match history.
//

import SwiftUI

struct StatsView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("matchHistory") private var matchHistoryData: Data = Data()
    @AppStorage("playerRoster") private var rosterData: Data = Data()

    @State private var selectedPlayer: String = ""

    private var history: [MatchRecord] {
        PersistenceStore.decodeHistory(matchHistoryData)
    }

    private var roster: [Player] {
        PersistenceStore.decodeRoster(rosterData)
    }

    private var allPlayers: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for record in history {
            for name in [record.myName, record.opponentName] {
                if seen.insert(name).inserted { result.append(name) }
            }
        }
        // Always show the main player first
        if let idx = result.firstIndex(of: myName), idx != 0 {
            result.remove(at: idx)
            result.insert(myName, at: 0)
        }
        return result
    }

    private var activePlayer: String {
        selectedPlayer.isEmpty ? myName : selectedPlayer
    }

    private var playerHistory: [MatchRecord] {
        history.filter { $0.myName == activePlayer || $0.opponentName == activePlayer }
    }

    private var opponents: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for record in playerHistory {
            let opp = record.myName == activePlayer ? record.opponentName : record.myName
            if seen.insert(opp).inserted { result.append(opp) }
        }
        return result
    }

    private func h2h(opponent: String) -> (wins: Int, losses: Int) {
        let mePlayer = roster.first(where: { $0.name == activePlayer })
        let oppPlayer = roster.first(where: { $0.name == opponent })
        let relevant = playerHistory.filter { record in
            let namesMatch = (record.myName == activePlayer && record.opponentName == opponent) ||
                             (record.myName == opponent && record.opponentName == activePlayer)
            let idsMatch: Bool = {
                guard let meId = mePlayer?.id, let oppId = oppPlayer?.id else { return false }
                return (record.myPlayerId == meId && record.opponentPlayerId == oppId) ||
                       (record.myPlayerId == oppId && record.opponentPlayerId == meId)
            }()
            return namesMatch || idsMatch
        }
        let wins = relevant.filter { $0.winner == activePlayer }.count
        return (wins: wins, losses: relevant.count - wins)
    }

    private var totalMatches: Int { playerHistory.count }
    private var wins: Int { playerHistory.filter { $0.winner == activePlayer }.count }
    private var losses: Int { totalMatches - wins }

    private var winRate: Double {
        totalMatches == 0 ? 0 : Double(wins) / Double(totalMatches) * 100
    }

    private var avgPointsScored: Double {
        guard !playerHistory.isEmpty else { return 0 }
        let total = playerHistory.flatMap { record -> [Int] in
            record.myName == activePlayer ? record.games.map { $0.my } : record.games.map { $0.opponent }
        }.reduce(0, +)
        let games = playerHistory.flatMap { $0.games }.count
        return games == 0 ? 0 : Double(total) / Double(games)
    }

    private var avgMatchDuration: TimeInterval {
        let timed = playerHistory.filter { $0.duration > 0 }
        guard !timed.isEmpty else { return 0 }
        return timed.map { $0.duration }.reduce(0, +) / Double(timed.count)
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private var longestStreak: Int {
        var best = 0
        var current = 0
        for record in playerHistory {
            if record.winner == activePlayer {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    var body: some View {
        List {
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
                                    Label(name, systemImage: "person.fill")
                                        .tag(name)
                                } else {
                                    Text(name).tag(name)
                                }
                            }
                        }
                    }
                }

                Section(header: Text(activePlayer)) {
                    StatRow(label: NSLocalizedString("stats.matches", comment: ""), value: "\(totalMatches)")
                    StatRow(label: NSLocalizedString("stats.wins", comment: ""), value: "\(wins)")
                    StatRow(label: NSLocalizedString("stats.losses", comment: ""), value: "\(losses)")
                    StatRow(label: NSLocalizedString("stats.win_rate", comment: ""), value: String(format: "%.0f%%", winRate))
                    StatRow(label: NSLocalizedString("stats.avg_points", comment: ""), value: String(format: "%.1f", avgPointsScored))
                    StatRow(label: NSLocalizedString("stats.best_streak", comment: ""), value: "\(longestStreak)")
                    if avgMatchDuration > 0 {
                        StatRow(label: NSLocalizedString("stats.avg_duration", comment: ""), value: durationString(avgMatchDuration))
                    }
                }

                if !opponents.isEmpty {
                    Section(header: Text("stats.head_to_head")) {
                        ForEach(opponents, id: \.self) { opp in
                            let record = h2h(opponent: opp)
                            StatRow(label: opp, value: "\(record.wins)W – \(record.losses)L")
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
