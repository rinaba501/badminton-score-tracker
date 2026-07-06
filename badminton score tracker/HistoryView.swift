//
//  HistoryView.swift
//  badminton score tracker (iOS)
//
//  Saved match list with date-range, match-type, sort, and multi-player
//  filtering, plus swipe-to-delete and clear-all. All filtering/derivation
//  lives in BadmintonCore.StatsCalculator (shared with the Watch); this screen
//  is layout + selection state only, restyled for iPhone width and pushed via
//  NavigationStack (no currentView binding — back is automatic).
//

import SwiftUI
import BadmintonCore

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingClearConfirmation = false
    /// Every name here must have participated (on either team) for a record
    /// to pass the filter — see StatsCalculator.filteredHistory.
    @State private var selectedPlayers: Set<String> = []
    @State private var dateRange: DateRange = .all
    @State private var newestFirst = true
    @State private var matchType: StatsCalculator.MatchTypeFilter = .all

    enum DateRange: String, CaseIterable {
        case week, month, all
        var labelKey: LocalizedStringKey {
            switch self {
            case .all:   "history.filter_all"
            case .week:  "history.filter_week"
            case .month: "history.filter_month"
            }
        }
    }

    private var history: [MatchRecord] { store.history }

    private var allPlayers: [String] {
        StatsCalculator.participants(history: history)
    }

    /// The match-type control only makes sense once history contains a mix of
    /// Singles and Doubles matches.
    private var hasMixedMatchTypes: Bool {
        history.contains { $0.isDoubles } && history.contains { !$0.isDoubles }
    }

    private func matchTypeLabel(_ type: StatsCalculator.MatchTypeFilter) -> LocalizedStringKey {
        switch type {
        case .all:     "history.filter_all_types"
        case .singles: "settings.singles"
        case .doubles: "settings.doubles"
        }
    }

    private var filteredHistory: [MatchRecord] {
        let cutoff: Date? = {
            switch dateRange {
            case .all:   return nil
            case .week:  return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .month: return Calendar.current.date(byAdding: .month, value: -1, to: Date())
            }
        }()
        return StatsCalculator.filteredHistory(history, selectedPlayers: selectedPlayers, cutoff: cutoff,
                                               newestFirst: newestFirst, matchType: matchType)
    }

    private func delete(_ record: MatchRecord) {
        var records = history
        records.removeAll { $0.id == record.id }
        store.saveHistory(records)
    }

    private func togglePlayer(_ name: String) {
        if selectedPlayers.contains(name) {
            selectedPlayers.remove(name)
        } else {
            selectedPlayers.insert(name)
        }
    }

    var body: some View {
        Group {
            if history.isEmpty {
                emptyState(key: "history.empty")
            } else {
                List {
                    filterSection
                    if filteredHistory.isEmpty {
                        Section { centeredMessage("history.empty") }
                    } else {
                        Section {
                            ForEach(filteredHistory) { record in
                                MatchHistoryRow(record: record)
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            delete(record)
                                        } label: {
                                            Label("history.clear", systemImage: "trash")
                                        }
                                    }
                                    .contextMenu { shareButton(for: record) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("history.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !history.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { playerFilterMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(Text("history.clear_title"))
                }
            }
        }
        .alert(Text("history.clear_title"), isPresented: $showingClearConfirmation) {
            Button("history.cancel", role: .cancel) { }
            Button("history.clear", role: .destructive) { store.clearHistory() }
        } message: {
            Text("history.clear_confirm")
        }
    }

    @ViewBuilder private var filterSection: some View {
        Section {
            Picker("history.filter_all", selection: $dateRange) {
                ForEach(DateRange.allCases, id: \.self) { range in
                    Text(range.labelKey).tag(range)
                }
            }
            .pickerStyle(.segmented)

            if hasMixedMatchTypes {
                Picker("history.filter_all_types", selection: $matchType) {
                    ForEach(StatsCalculator.MatchTypeFilter.allCases, id: \.self) { type in
                        Text(matchTypeLabel(type)).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }

            Picker("history.sort_newest", selection: $newestFirst) {
                Text("history.sort_newest").tag(true)
                Text("history.sort_oldest").tag(false)
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder private var playerFilterMenu: some View {
        if allPlayers.count > 1 {
            Menu {
                Button {
                    selectedPlayers = []
                } label: {
                    if selectedPlayers.isEmpty {
                        Label("history.filter_all_players", systemImage: "checkmark")
                    } else {
                        Text("history.filter_all_players")
                    }
                }
                Divider()
                ForEach(allPlayers, id: \.self) { name in
                    Button {
                        togglePlayer(name)
                    } label: {
                        if selectedPlayers.contains(name) {
                            Label(Player.displayName(for: name), systemImage: "checkmark")
                        } else {
                            Text(Player.displayName(for: name))
                        }
                    }
                }
            } label: {
                Image(systemName: selectedPlayers.isEmpty ? "person" : "person.fill")
            }
            .accessibilityLabel(Text("history.filter_player"))
        }
    }

    @ViewBuilder private func shareButton(for record: MatchRecord) -> some View {
        if let share = MatchCardShare.make(for: record) {
            ShareLink(item: share.item,
                      preview: SharePreview(record.shareSummaryText, image: share.preview)) {
                Label("ios.share", systemImage: "square.and.arrow.up")
            }
        }
    }

    private func centeredMessage(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .listRowBackground(Color.clear)
    }

    private func emptyState(key: LocalizedStringKey) -> some View {
        VStack {
            Spacer()
            Text(key).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

struct MatchHistoryRow: View {
    let record: MatchRecord

    @EnvironmentObject private var store: AppStore

    private var iWon: Bool { record.winner == .near }

    private var gameLine: String {
        record.games.map { "\($0.my)-\($0.opponent)" }.joined(separator: ", ")
    }

    /// Combines a team's representative name with its partner's, when present,
    /// using the same "%1$@ & %2$@" format the Game screen uses.
    private func teamLabel(name: String, partnerName: String?) -> String {
        guard let partnerName else { return name }
        return String(format: NSLocalizedString("game.team_names_format", comment: ""), name, Player.displayName(for: partnerName))
    }

    private var myLabel: String {
        teamLabel(name: record.myName.isEmpty ? Player.defaultMyName : Player.displayName(for: record.myName),
                  partnerName: record.myPartnerName)
    }

    private var opponentLabel: String {
        let fallback = NSLocalizedString("history.opponent_fallback", comment: "")
        let name = record.opponentName.isEmpty ? fallback : Player.displayName(for: record.opponentName)
        return teamLabel(name: name, partnerName: record.opponentPartnerName)
    }

    // Roster lookups by raw (stored) name — guests/unknowns fall back to gray
    // initials, matching the rest of the app's avatar behavior.
    private func rosterPlayer(_ rawName: String) -> Player? {
        store.roster.first(where: { $0.name == rawName })
    }

    private func teamAvatars(rawName: String, fallbackLabel: String, rawPartner: String?) -> some View {
        let player = rosterPlayer(rawName)
        return HStack(spacing: rawPartner == nil ? 0 : -8) {
            AvatarView(name: Player.displayName(for: rawName.isEmpty ? fallbackLabel : rawName),
                       color: player?.avatarColor ?? .gray,
                       size: 26,
                       iconName: player?.iconName)
            if let rawPartner {
                let partner = rosterPlayer(rawPartner)
                AvatarView(name: Player.displayName(for: rawPartner),
                           color: partner?.avatarColor ?? .gray,
                           size: 26,
                           iconName: partner?.iconName)
            }
        }
    }

    private func teamRow(rawName: String, rawPartner: String?,
                         label: String, games: Int, won: Bool) -> some View {
        HStack(spacing: 10) {
            teamAvatars(rawName: rawName, fallbackLabel: label, rawPartner: rawPartner)
            Text(label)
                .fontWeight(won ? .semibold : .regular)
                .lineLimit(1)
            Spacer()
            Text("\(games)")
                .font(.system(.title3, design: .rounded).weight(won ? .bold : .regular))
                .foregroundStyle(won ? Color.accentColor : Color.secondary)
                .monospacedDigit()
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            teamRow(rawName: record.myName, rawPartner: record.myPartnerName,
                    label: myLabel, games: record.myGamesWon, won: iWon)
            teamRow(rawName: record.opponentName, rawPartner: record.opponentPartnerName,
                    label: opponentLabel, games: record.opponentGamesWon, won: !iWon)

            HStack(spacing: 5) {
                if !gameLine.isEmpty {
                    Text(gameLine).monospacedDigit()
                    Text(verbatim: "·")
                }
                Text(record.date, format: .dateTime.month().day().hour().minute())
                if record.duration > 0 {
                    Text(verbatim: "·")
                    Text(StatsCalculator.durationString(record.duration))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 36)
        }
        .padding(.vertical, 5)
    }
}
