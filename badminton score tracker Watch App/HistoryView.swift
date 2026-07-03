//
//  HistoryView.swift
//  badminton score tracker Watch App
//
//  Saved match list with date-range and per-player filtering, plus
//  swipe-to-delete and clear-all.
//

import SwiftUI
import BadmintonCore

struct HistoryView: View {
    @Binding var currentView: ContentView.AppView
    @EnvironmentObject private var appStore: AppStore
    @State private var showingClearConfirmation = false
    @State private var showingFilters = false
    @State private var selectedPlayer: String = ""
    @State private var dateRange: DateRange = .all

    enum DateRange: String, CaseIterable {
        case all, week, month
        var label: String {
            switch self {
            case .all:   return NSLocalizedString("history.filter_all", comment: "")
            case .week:  return NSLocalizedString("history.filter_week", comment: "")
            case .month: return NSLocalizedString("history.filter_month", comment: "")
            }
        }
    }

    private var history: [MatchRecord] { appStore.history }

    private var allPlayers: [String] {
        StatsCalculator.participants(history: history)
    }

    private var filteredHistory: [MatchRecord] {
        let cutoff: Date? = {
            switch dateRange {
            case .all:   return nil
            case .week:  return Calendar.current.date(byAdding: .day, value: -7, to: Date())
            case .month: return Calendar.current.date(byAdding: .month, value: -1, to: Date())
            }
        }()
        return StatsCalculator.filteredHistory(history, selectedPlayer: selectedPlayer, cutoff: cutoff)
    }

    private func save(_ records: [MatchRecord]) {
        appStore.saveHistory(records)
    }

    private func delete(_ record: MatchRecord) {
        var records = history
        records.removeAll { $0.id == record.id }
        save(records)
    }

    var body: some View {
        List {
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

                        if allPlayers.count > 1 {
                            Button(action: { showingFilters = true }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "person")
                                        .font(.system(size: 11))
                                        .foregroundColor(!selectedPlayer.isEmpty ? .yellow : .secondary)
                                    Text(selectedPlayer.isEmpty ? NSLocalizedString("history.filter_all_players", comment: "") : selectedPlayer)
                                        .font(.system(size: 11))
                                        .foregroundColor(!selectedPlayer.isEmpty ? .yellow : .secondary)
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
                                        delete(record)
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
            List {
                Section(header: Text("history.filter_player")) {
                    Button(action: { selectedPlayer = "" }) {
                        HStack {
                            Text("history.filter_all_players")
                            Spacer()
                            if selectedPlayer.isEmpty {
                                Image(systemName: "checkmark").foregroundColor(.yellow)
                            }
                        }
                    }
                    ForEach(allPlayers, id: \.self) { name in
                        Button(action: { selectedPlayer = name }) {
                            HStack {
                                Text(name)
                                Spacer()
                                if selectedPlayer == name {
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
    }
}

struct MatchHistoryRow: View {
    let record: MatchRecord

    private var iWon: Bool { record.winner == record.myName }

    private var gameLine: String {
        record.games.map { "\($0.my)-\($0.opponent)" }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Head-to-head score line
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.myName.isEmpty ? Player.defaultMyName : record.myName)
                        .font(.system(size: 12, weight: iWon ? .bold : .regular))
                        .lineLimit(1)
                    Text(record.opponentName.isEmpty ? NSLocalizedString("history.opponent_fallback", comment: "") : record.opponentName)
                        .font(.system(size: 12, weight: iWon ? .regular : .bold))
                        .lineLimit(1)
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
