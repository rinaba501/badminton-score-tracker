//
//  StatsView.swift
//  badminton score tracker (iOS)
//
//  Per-player aggregate stats and head-to-head breakdowns, dashboard-style:
//  a win-rate ring with the W–L record, a grid of stat cards, and avatar'd
//  head-to-head rows. All math lives in BadmintonCore.StatsCalculator (shared
//  with the Watch); this screen binds it to the selected player.
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

    private func rosterPlayer(_ name: String) -> Player? {
        roster.first(where: { $0.name == name })
    }

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
                statsList
            }
        }
        .navigationTitle("stats.title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedPlayer.isEmpty { selectedPlayer = myName }
        }
    }

    private var statsList: some View {
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

            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section {
                statGrid
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if !opponents.isEmpty {
                Section(header: Text("stats.head_to_head")) {
                    ForEach(opponents, id: \.self) { opp in
                        headToHeadRow(opp)
                    }
                }
            }
        }
    }

    // MARK: - Header (ring + record)

    private var header: some View {
        HStack(spacing: 20) {
            winRateRing
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "\(wins)W – \(losses)L")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    Text("stats.matches")
                    Text(verbatim: "\(totalMatches)").monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var winRateRing: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.001, winRate / 100))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(verbatim: String(format: "%.0f%%", winRate))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("stats.win_rate")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("stats.win_rate"))
        .accessibilityValue(Text(verbatim: String(format: "%.0f%%", winRate)))
    }

    // MARK: - Stat cards

    private var statGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            statCard(value: "\(wins)", labelKey: "stats.wins")
            statCard(value: "\(losses)", labelKey: "stats.losses")
            statCard(value: String(format: "%.1f", avgPointsScored), labelKey: "stats.avg_points")
            statCard(value: "\(longestStreak)", labelKey: "stats.best_streak")
            if avgMatchDuration > 0 {
                statCard(value: StatsCalculator.durationString(avgMatchDuration), labelKey: "stats.avg_duration")
            }
        }
    }

    private func statCard(value: String, labelKey: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(labelKey)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Head-to-head

    private func headToHeadRow(_ opponent: String) -> some View {
        let record = StatsCalculator.headToHead(player: activePlayer, opponent: opponent, history: history, roster: roster)
        let player = rosterPlayer(opponent)
        return HStack(spacing: 10) {
            AvatarView(name: Player.displayName(for: opponent),
                       color: player?.avatarColor ?? .gray,
                       size: 28,
                       iconName: player?.iconName)
            Text(Player.displayName(for: opponent))
            Spacer()
            Text(verbatim: "\(record.wins)W – \(record.losses)L")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(record.wins >= record.losses ? Color.accentColor : Color.secondary)
        }
    }
}
