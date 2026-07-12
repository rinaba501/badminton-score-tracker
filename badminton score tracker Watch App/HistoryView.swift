//
//  HistoryView.swift
//  badminton score tracker Watch App
//
//  Saved match list with date-range, match-type, and multi-player
//  filtering, date sort order, plus swipe-to-delete and clear-all.
//

import SwiftUI
import BadmintonCore

struct HistoryView: View {
    @Binding var currentView: ContentView.AppView
    @EnvironmentObject private var appStore: AppStore
    @State private var showingClearConfirmation = false
    @State private var pendingDeleteRecord: MatchRecord?
    @State private var showingFilters = false
    @State private var showingClubFilter = false
    /// Every name here must have participated (on either team) for a record
    /// to pass the filter — see StatsCalculator.filteredHistory.
    @State private var selectedPlayers: Set<String> = []
    @State private var dateRange: DateRange = .all
    @State private var newestFirst = true
    @State private var matchType: StatsCalculator.MatchTypeFilter = .all
    @State private var selectedClubId: UUID?

    enum DateRange: String, CaseIterable {
        case week, month, all
        var label: String {
            switch self {
            case .all:   return NSLocalizedString("history.filter_all", comment: "")
            case .week:  return NSLocalizedString("history.filter_week", comment: "")
            case .month: return NSLocalizedString("history.filter_month", comment: "")
            }
        }
    }

    private var history: [MatchRecord] { appStore.history.filter { $0.clubId == selectedClubId } }

    private var clubLabel: String {
        guard let selectedClubId else { return NSLocalizedString("clubs.filter_personal", comment: "") }
        return appStore.clubs.first { $0.id == selectedClubId }?.name ?? NSLocalizedString("clubs.filter_personal", comment: "")
    }

    private var allPlayers: [String] {
        StatsCalculator.participants(history: history)
    }

    /// The match-type row only makes sense to show once history actually
    /// contains a mix of Singles and Doubles matches.
    private var hasMixedMatchTypes: Bool {
        history.contains { $0.isDoubles } && history.contains { !$0.isDoubles }
    }

    private func matchTypeLabel(_ type: StatsCalculator.MatchTypeFilter) -> String {
        switch type {
        case .all:     return NSLocalizedString("history.filter_all_types", comment: "")
        case .singles: return NSLocalizedString("settings.singles", comment: "")
        case .doubles: return NSLocalizedString("settings.doubles", comment: "")
        }
    }

    private var sortLabel: String {
        newestFirst ? NSLocalizedString("history.sort_newest", comment: "") : NSLocalizedString("history.sort_oldest", comment: "")
    }

    private var playerFilterLabel: String {
        guard !selectedPlayers.isEmpty else {
            return NSLocalizedString("history.filter_all_players", comment: "")
        }
        let ordered = allPlayers.filter { selectedPlayers.contains($0) }
        return ordered.map { Player.displayName(for: $0) }.joined(separator: ", ")
    }

    private func togglePlayer(_ name: String) {
        if selectedPlayers.contains(name) {
            selectedPlayers.remove(name)
        } else {
            selectedPlayers.insert(name)
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

    private func save(_ records: [MatchRecord]) {
        appStore.saveHistory(records)
    }

    private func delete(_ record: MatchRecord) {
        var records = history
        records.removeAll { $0.id == record.id }
        save(records)
    }

    private var clubMenu: some View {
        Button(action: { showingClubFilter = true }) {
            HStack(spacing: 4) {
                Image(systemName: "person.3")
                    .font(.system(size: 11))
                    .foregroundColor(selectedClubId != nil ? .yellow : .secondary)
                Text(clubLabel)
                    .font(.system(size: 11))
                    .foregroundColor(selectedClubId != nil ? .yellow : .secondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("clubs.filter_label"))
    }

    var body: some View {
        List {
            if !appStore.clubs.isEmpty {
                Section {
                    clubMenu
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .listSectionSpacing(0)
            }

            if history.isEmpty {
                Section {
                    Text("history.empty")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            ForEach(DateRange.allCases, id: \.self) { range in
                                Button(action: { dateRange = range }) {
                                    Text(range.label)
                                        .font(.system(size: 11, weight: dateRange == range ? .semibold : .regular))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 4)
                                        .background(dateRange == range ? Color.yellow.opacity(0.25) : Color.secondary.opacity(0.15))
                                        .foregroundColor(dateRange == range ? .yellow : .primary)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if hasMixedMatchTypes {
                            HStack(spacing: 4) {
                                ForEach(StatsCalculator.MatchTypeFilter.allCases, id: \.self) { type in
                                    Button(action: { matchType = type }) {
                                        Text(matchTypeLabel(type))
                                            .font(.system(size: 11, weight: matchType == type ? .semibold : .regular))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 4)
                                            .background(matchType == type ? Color.yellow.opacity(0.25) : Color.secondary.opacity(0.15))
                                            .foregroundColor(matchType == type ? .yellow : .primary)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        HStack(spacing: 4) {
                            Button(action: { newestFirst.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: newestFirst ? "arrow.down" : "arrow.up")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                    Text(sortLabel)
                                        .font(.system(size: 11))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.history_sort_toggle", comment: ""), sortLabel)))
                            .accessibilityHint(Text("a11y.history_sort_hint"))

                            if allPlayers.count > 1 {
                                Button(action: { showingFilters = true }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "person")
                                            .font(.system(size: 11))
                                            .foregroundColor(!selectedPlayers.isEmpty ? .yellow : .secondary)
                                        Text(playerFilterLabel)
                                            .font(.system(size: 11))
                                            .foregroundColor(!selectedPlayers.isEmpty ? .yellow : .secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.15))
                                    .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                .listSectionSpacing(0)

                if filteredHistory.isEmpty {
                    Section {
                        Text("history.empty")
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                    .listSectionSpacing(0)
                } else {
                    Section {
                        ForEach(filteredHistory) { record in
                            MatchHistoryRow(record: record)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        pendingDeleteRecord = record
                                    } label: {
                                        Label("history.clear", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
            }
        }
        .navigationTitle("history.title")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("history.back") { currentView = .menu }
            }
            if !history.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingClearConfirmation = true }) {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                }
            }
        }
        .sheet(isPresented: $showingFilters) {
            // No explicit dismiss control: the sheet's own top-leading close
            // button (added automatically by watchOS) closes it, and the
            // multi-select toggles apply live to the parent's filter state.
            List {
                Section(header: Text("history.filter_player")) {
                    Button(action: { selectedPlayers = []; showingFilters = false }) {
                        HStack {
                            Text("history.filter_all_players")
                            Spacer()
                            if selectedPlayers.isEmpty {
                                Image(systemName: "checkmark").foregroundColor(.yellow)
                            }
                        }
                    }
                    ForEach(allPlayers, id: \.self) { name in
                        Button(action: { togglePlayer(name) }) {
                            HStack {
                                Text(Player.displayName(for: name))
                                Spacer()
                                if selectedPlayers.contains(name) {
                                    Image(systemName: "checkmark").foregroundColor(.yellow)
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingClubFilter) {
            List {
                Section(header: Text("clubs.filter_label")) {
                    Button(action: { selectedClubId = nil; showingClubFilter = false }) {
                        HStack {
                            Text("clubs.filter_personal")
                            Spacer()
                            if selectedClubId == nil {
                                Image(systemName: "checkmark").foregroundColor(.yellow)
                            }
                        }
                    }
                    ForEach(appStore.clubs) { club in
                        Button(action: { selectedClubId = club.id; showingClubFilter = false }) {
                            HStack {
                                Text(club.name)
                                Spacer()
                                if selectedClubId == club.id {
                                    Image(systemName: "checkmark").foregroundColor(.yellow)
                                }
                            }
                        }
                    }
                }
            }
        }
        .alert(Text("history.clear_title"), isPresented: $showingClearConfirmation) {
            Button("history.cancel", role: .cancel) { }
            Button("history.clear", role: .destructive) { appStore.clearHistory() }
        } message: {
            Text("history.clear_confirm")
        }
        .confirmationDialog(
            "history.delete_match_confirm",
            isPresented: Binding(
                get: { pendingDeleteRecord != nil },
                set: { if !$0 { pendingDeleteRecord = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("history.clear", role: .destructive) {
                if let pendingDeleteRecord { delete(pendingDeleteRecord) }
            }
        }
    }
}

struct MatchHistoryRow: View {
    let record: MatchRecord

    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName

    private var iWon: Bool { record.winner == .near }

    /// Small badge marking a name as "me" — needed once club history can
    /// contain matches recorded by other members (record.myName is then
    /// someone else's name), same treatment as ClubDetailView's youBadge.
    private var youBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: 9))
            .foregroundColor(.secondary)
            .accessibilityLabel("clubs.you")
    }

    private var gameLine: String {
        record.games.map { "\($0.my)-\($0.opponent)" }.joined(separator: ", ")
    }

    /// Combines a team's representative name with its partner's, when
    /// present, using the same "%1$@ & %2$@" format the Game screen uses.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Head-to-head score line
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 3) {
                        Text(myLabel)
                            .font(.system(size: 12, weight: iWon ? .bold : .regular))
                            .lineLimit(1)
                        if record.myName == myName { youBadge }
                    }
                    HStack(spacing: 3) {
                        Text(opponentLabel)
                            .font(.system(size: 12, weight: iWon ? .regular : .bold))
                            .lineLimit(1)
                        if record.opponentName == myName { youBadge }
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(record.myGamesWon)")
                        .font(.system(size: 14, weight: iWon ? .bold : .regular, design: .rounded))
                        .foregroundColor(iWon ? .green : .primary)
                    Text("\(record.opponentGamesWon)")
                        .font(.system(size: 14, weight: iWon ? .regular : .bold, design: .rounded))
                        .foregroundColor(iWon ? .primary : .orange)
                }
            }

            // Per-game scores
            if !gameLine.isEmpty {
                Text(gameLine)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Date + duration
            HStack(spacing: 4) {
                Text(record.date, format: .dateTime.month().day().hour().minute())
                if record.duration > 0 {
                    Text("·")
                    Text(StatsCalculator.durationString(record.duration))
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}
