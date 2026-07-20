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
//  Personal scope (selectedClubId == nil) also surfaces the "Share My History
//  with Friends" toggle inline (visible-text Switch, not icon-only like
//  ProfileView's — history is a bigger reveal than one profile field, so it
//  gets a more deliberate control) — same discoverability fix as ProfileView,
//  applied to a screen with no natural per-field home. toggleShareHistory-
//  WithFriends here is a deliberate duplicate of FriendSharingSettingsView's.
//  Lives inline atop the filter Section with no footer (the explainer text
//  lives in FriendSharingSettingsView already) and sort order lives in the
//  toolbar, not a third segmented control — both trim chrome above the first
//  match row on tall screens (#223).
//

import SwiftUI
import BadmintonCore

struct HistoryView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var storeManager: StoreManager
    @AppStorage(AppStorageKeys.shareHistoryWithFriends) private var shareHistoryWithFriends = false
    @State private var showingClearConfirmation = false
    @State private var pendingDeleteIds: Set<MatchRecord.ID>?
    @State private var isSelecting = false
    @State private var selectedIds: Set<MatchRecord.ID> = []
    /// Every name here must have participated (on either team) for a record
    /// to pass the filter — see StatsCalculator.filteredHistory.
    @State private var selectedPlayers: Set<String> = []
    @State private var dateRange: DateRange = .all
    @State private var newestFirst = true
    @State private var matchType: StatsCalculator.MatchTypeFilter = .all
    @State private var selectedClubId: UUID?

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

    private var history: [MatchRecord] { store.history.filter { $0.clubId == selectedClubId } }

    private var clubLabel: String {
        guard let selectedClubId else { return NSLocalizedString("clubs.filter_personal", comment: "") }
        return store.clubs.first { $0.id == selectedClubId }?.name ?? NSLocalizedString("clubs.filter_personal", comment: "")
    }

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

    private func deleteRecords(withIds ids: Set<MatchRecord.ID>) {
        store.saveHistory(history.filter { !ids.contains($0.id) })
    }

    private func exitSelection() {
        isSelecting = false
        selectedIds = []
    }

    private func toggleSelection(_ id: MatchRecord.ID) {
        if selectedIds.contains(id) {
            selectedIds.remove(id)
        } else {
            selectedIds.insert(id)
        }
    }

    private var allFilteredSelected: Bool {
        !filteredHistory.isEmpty && Set(filteredHistory.map(\.id)).isSubset(of: selectedIds)
    }

    private func toggleSelectAll() {
        if allFilteredSelected {
            selectedIds.subtract(filteredHistory.map(\.id))
        } else {
            selectedIds.formUnion(filteredHistory.map(\.id))
        }
    }

    private var deleteConfirmTitle: String {
        let count = pendingDeleteIds?.count ?? 0
        guard count > 1 else { return NSLocalizedString("history.delete_match_confirm", comment: "") }
        return String(format: NSLocalizedString("history.delete_selected_confirm", comment: ""), count)
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
                            if isSelecting {
                                Button(action: toggleSelectAll) {
                                    Text(allFilteredSelected ? "history.deselect_all" : "history.select_all")
                                }
                            }
                            ForEach(filteredHistory) { record in
                                HStack(spacing: 8) {
                                    if isSelecting {
                                        Image(systemName: selectedIds.contains(record.id) ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(selectedIds.contains(record.id) ? Color.accentColor : Color.secondary)
                                    }
                                    MatchHistoryRow(record: record)
                                }
                                .contentShape(Rectangle())
                                .accessibilityAddTraits(isSelecting && selectedIds.contains(record.id) ? .isSelected : [])
                                .onTapGesture {
                                    if isSelecting { toggleSelection(record.id) }
                                }
                                .swipeActions(edge: .trailing) {
                                    if !isSelecting {
                                        Button(role: .destructive) {
                                            pendingDeleteIds = [record.id]
                                        } label: {
                                            Label("history.clear", systemImage: "trash")
                                        }
                                    }
                                }
                                .contextMenu {
                                    if !isSelecting { shareButton(for: record) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("history.title")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if storeManager.entitlements.showsAds {
                AdBannerView()
            }
        }
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .topBarLeading) {
                    Button("history.cancel") { exitSelection() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        pendingDeleteIds = selectedIds.intersection(Set(filteredHistory.map(\.id)))
                    } label: {
                        Text(String(format: NSLocalizedString("history.delete_selected", comment: ""),
                                    selectedIds.intersection(Set(filteredHistory.map(\.id))).count))
                    }
                    .disabled(selectedIds.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(allFilteredSelected ? "history.deselect_all" : "history.select_all") { toggleSelectAll() }
                }
            } else {
                if !store.clubs.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { clubFilterMenu }
                }
                if !history.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { playerFilterMenu }
                    ToolbarItem(placement: .topBarTrailing) { moreMenu }
                }
            }
        }
        .alert(Text("history.clear_title"), isPresented: $showingClearConfirmation) {
            Button("history.cancel", role: .cancel) { }
            Button("history.clear", role: .destructive) { store.clearHistory() }
        } message: {
            Text("history.clear_confirm")
        }
        .confirmationDialog(
            deleteConfirmTitle,
            isPresented: Binding(
                get: { pendingDeleteIds != nil },
                set: { if !$0 { pendingDeleteIds = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("history.clear", role: .destructive) {
                if let pendingDeleteIds {
                    deleteRecords(withIds: pendingDeleteIds)
                    exitSelection()
                }
            }
        }
    }

    @ViewBuilder private var filterSection: some View {
        Section {
            if selectedClubId == nil {
                Toggle("friends.share_history_toggle", isOn: $shareHistoryWithFriends)
                    .onChange(of: shareHistoryWithFriends) { _, isOn in toggleShareHistoryWithFriends(isOn) }
            }

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
        }
    }

    @ViewBuilder private var clubFilterMenu: some View {
        Menu {
            Button {
                selectedClubId = nil
            } label: {
                if selectedClubId == nil {
                    Label("clubs.filter_personal", systemImage: "checkmark")
                } else {
                    Text("clubs.filter_personal")
                }
            }
            Divider()
            ForEach(store.clubs) { club in
                Button {
                    selectedClubId = club.id
                } label: {
                    if selectedClubId == club.id {
                        Label(club.name, systemImage: "checkmark")
                    } else {
                        Text(club.name)
                    }
                }
            }
        } label: {
            Image(systemName: selectedClubId == nil ? "person.3" : "person.3.fill")
        }
        .accessibilityLabel(Text("clubs.filter_label"))
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

    /// Folds sort (a nested Menu) and clear-all (a destructive Button, still
    /// gated by the confirmation alert below) into one trailing "…" menu —
    /// keeps the toolbar to at most 3 items so the "History" title has room
    /// to show (#237).
    @ViewBuilder private var moreMenu: some View {
        Menu {
            Menu {
                Button {
                    newestFirst = true
                } label: {
                    if newestFirst {
                        Label("history.sort_newest", systemImage: "checkmark")
                    } else {
                        Text("history.sort_newest")
                    }
                }
                Button {
                    newestFirst = false
                } label: {
                    if !newestFirst {
                        Label("history.sort_oldest", systemImage: "checkmark")
                    } else {
                        Text("history.sort_oldest")
                    }
                }
            } label: {
                Label("history.sort_label", systemImage: "arrow.up.arrow.down")
            }
            Divider()
            Button {
                isSelecting = true
            } label: {
                Label("history.select", systemImage: "checkmark.circle")
            }
            Button(role: .destructive) {
                showingClearConfirmation = true
            } label: {
                Label("history.clear_title", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel(Text("history.more_options"))
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

    // See FriendSharingSettingsView's matching handler — the settings write
    // is the complete access change.
    private func toggleShareHistoryWithFriends(_ isOn: Bool) {
        AppStore.shared.enqueueSettingsChange()
    }
}

struct MatchHistoryRow: View {
    let record: MatchRecord

    @EnvironmentObject private var store: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName

    private var iWon: Bool { record.winner == .near }

    /// Small badge marking a name as "me" — needed once club history can
    /// contain matches recorded by other members (record.myName is then
    /// someone else's name), same treatment as ClubDetailView's youBadge.
    private var youBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption2)
            .foregroundColor(.secondary)
            .accessibilityLabel("clubs.you")
    }

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

    // Roster lookups by raw (stored) name — a guest falls back to its fixed
    // bird color (see Player.guestAvatarColor); any other unknown name falls
    // back to gray, matching the rest of the app's avatar behavior.
    private func rosterPlayer(_ rawName: String) -> Player? {
        store.roster.first(where: { $0.name == rawName })
    }

    private func avatarColor(rawName: String, player: Player?) -> Color {
        if let player { return player.avatarColor }
        return Player.isGuestName(rawName) ? Player.guestAvatarColor(for: rawName) : .gray
    }

    private func teamAvatars(rawName: String, fallbackLabel: String, rawPartner: String?) -> some View {
        let player = rosterPlayer(rawName)
        return HStack(spacing: rawPartner == nil ? 0 : -8) {
            AvatarView(name: Player.displayName(for: rawName.isEmpty ? fallbackLabel : rawName),
                       color: avatarColor(rawName: rawName, player: player),
                       size: 26,
                       iconName: player?.iconName)
            if let rawPartner {
                let partner = rosterPlayer(rawPartner)
                AvatarView(name: Player.displayName(for: rawPartner),
                           color: avatarColor(rawName: rawPartner, player: partner),
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
                .lineLimit(2)
            if rawName == myName { youBadge }
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
