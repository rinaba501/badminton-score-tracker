//
//  PreMatchView.swift
//  badminton score tracker (iOS)
//
//  Player selection before a match: pick singles/doubles, then the near side
//  (and partner), then the far side (and partner), with head-to-head records
//  surfaced against the chosen near player. iOS restyle of the Watch's
//  PreMatchView — same match-config @AppStorage keys and guest-token identity,
//  driven by onReady/onCancel closures (no currentView binding). Adding a new
//  player reuses the iOS PlayerEditView.
//

import SwiftUI
import BadmintonCore

struct PreMatchView: View {
    let onReady: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.matchMyName) private var matchMyName = ""
    @AppStorage(AppStorageKeys.matchOpponentName) private var matchOpponentName = ""
    @AppStorage(AppStorageKeys.matchMyPartnerName) private var matchMyPartnerName = ""
    @AppStorage(AppStorageKeys.matchOpponentPartnerName) private var matchOpponentPartnerName = ""
    @AppStorage(AppStorageKeys.matchClubId) private var matchClubId = ""
    @AppStorage(AppStorageKeys.gameMode) private var gameMode: GameMode = .singles
    @AppStorage(AppStorageKeys.playerSortOrder) private var playerSortOrder: Player.SortOrder = .name

    @State private var step: Step = .pickMyPlayer
    @State private var showAddPlayer = false

    enum Step { case pickMyPlayer, pickMyPartner, pickOpponent, pickOpponentPartner }

    private var clubSelection: Binding<UUID?> {
        Binding(
            get: { UUID(uuidString: matchClubId) },
            set: { matchClubId = $0?.uuidString ?? "" }
        )
    }

    private var history: [MatchRecord] { appStore.history }
    private var roster: [Player] { appStore.roster }
    private var isDoubles: Bool { gameMode == .doubles }

    // MARK: - Roster helpers

    private func avatarColor(for name: String) -> Color {
        roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        roster.first(where: { $0.name == name })?.iconName
    }

    /// Same "me" marker ClubDetailView uses — `defaultLabel` is only ever
    /// non-empty for the near-side step, so whenever it's shown it's always
    /// your own name.
    private var youBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("clubs.you")
    }

    private func addPlayer(_ player: Player, thenSelect select: (String) -> Void) {
        var r = roster
        if !r.contains(where: { $0.name == player.name }) {
            r.insert(player, at: 0)
            appStore.saveRoster(r)
        }
        select(player.name)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("prematch.title")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    // Unconditionally cleared (not just when switching to
                    // singles): these 3 fields are read as "already used
                    // this match" input to the guest-token draw (see
                    // picker's usedGuestTokens) at steps earlier than the
                    // one that sets them, so a leftover value from the
                    // *previous* match would otherwise be mistaken for a
                    // pick already made in this one.
                    matchMyPartnerName = ""
                    matchOpponentName = ""
                    matchOpponentPartnerName = ""
                    if let id = UUID(uuidString: matchClubId), !appStore.clubs.contains(where: { $0.id == id }) {
                        matchClubId = ""
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .pickMyPlayer:
            let usedGuestTokens = Set([matchMyPartnerName, matchOpponentName, matchOpponentPartnerName].filter(Player.isGuestName))
            picker(titleKey: "prematch.near_side",
                   defaultLabel: myName, defaultColor: avatarColor(for: myName),
                   usedGuestTokens: usedGuestTokens,
                   showModePicker: true, showClubPicker: true) { name in
                matchMyName = name
                step = isDoubles ? .pickMyPartner : .pickOpponent
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back", action: onCancel)
                }
            }

        case .pickMyPartner:
            let usedGuestTokens = Set([matchMyName, matchOpponentName, matchOpponentPartnerName].filter(Player.isGuestName))
            picker(titleKey: "prematch.near_partner",
                   defaultLabel: nil, defaultColor: .gray,
                   usedGuestTokens: usedGuestTokens,
                   excluding: [matchMyName]) { name in
                matchMyPartnerName = name
                step = .pickOpponent
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { step = .pickMyPlayer }
                }
            }

        case .pickOpponent:
            let nearName = matchMyName.isEmpty ? myName : matchMyName
            let usedGuestTokens = Set([matchMyName, matchMyPartnerName, matchOpponentPartnerName].filter(Player.isGuestName))
            picker(titleKey: "prematch.far_side",
                   defaultLabel: nil, defaultColor: .gray,
                   usedGuestTokens: usedGuestTokens,
                   excluding: [nearName, matchMyPartnerName].filter { !$0.isEmpty },
                   h2hAgainst: nearName) { name in
                matchOpponentName = name
                if isDoubles { step = .pickOpponentPartner } else { onReady() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { step = isDoubles ? .pickMyPartner : .pickMyPlayer }
                }
            }

        case .pickOpponentPartner:
            let nearName = matchMyName.isEmpty ? myName : matchMyName
            let usedGuestTokens = Set([matchMyName, matchMyPartnerName, matchOpponentName].filter(Player.isGuestName))
            picker(titleKey: "prematch.far_partner",
                   defaultLabel: nil, defaultColor: .gray,
                   usedGuestTokens: usedGuestTokens,
                   excluding: [nearName, matchMyPartnerName, matchOpponentName].filter { !$0.isEmpty }) { name in
                matchOpponentPartnerName = name
                onReady()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { step = .pickOpponent }
                }
            }
        }
    }

    // MARK: - Reusable picker

    private func picker(titleKey: LocalizedStringKey,
                        defaultLabel: String?,
                        defaultColor: Color,
                        usedGuestTokens: Set<String>,
                        excluding: [String] = [],
                        showModePicker: Bool = false,
                        showClubPicker: Bool = false,
                        h2hAgainst: String? = nil,
                        onSelect: @escaping (String) -> Void) -> some View {
        let selectedClubId = UUID(uuidString: matchClubId)
        let guestToken = Player.randomGuestToken(excluding: usedGuestTokens)
        let guestLabel = Player.displayName(for: guestToken)
        let filteredRoster = Player.sortedPlayers(
            roster.filter { $0.name != myName && !excluding.contains($0.name) && $0.clubId == selectedClubId },
            order: playerSortOrder,
            history: history
        )
        let filteredFriends = selectedClubId == nil
            ? appStore.friends
                .filter { $0.displayName != myName && !excluding.contains($0.displayName) }
                .sorted { $0.displayName < $1.displayName }
            : []
        return List {
            if showModePicker {
                Section {
                    Picker("settings.mode", selection: $gameMode) {
                        Text("settings.singles").tag(GameMode.singles)
                        Text("settings.doubles").tag(GameMode.doubles)
                    }
                    .pickerStyle(.segmented)
                }
            }

            if showClubPicker && !appStore.clubs.isEmpty {
                Section {
                    Picker("playeredit.club", selection: clubSelection) {
                        Text("playeredit.club_personal").tag(UUID?.none)
                        ForEach(appStore.clubs) { club in
                            Text(club.name).tag(UUID?.some(club.id))
                        }
                    }
                }
            }

            Section(header: Text(titleKey)) {
                if let defaultLabel, !defaultLabel.isEmpty {
                    Button { onSelect(defaultLabel) } label: {
                        HStack(spacing: 10) {
                            playerRow(name: defaultLabel, color: defaultColor, icon: avatarIcon(for: defaultLabel))
                            youBadge
                        }
                    }
                }
                Button { onSelect(guestToken) } label: {
                    HStack(spacing: 10) {
                        AvatarView(name: guestLabel, color: Player.guestAvatarColor(for: guestToken), size: 28, iconName: nil)
                        Text(Player.guestButtonLabel)
                        Spacer()
                    }
                }
            }

            if !filteredRoster.isEmpty {
                Section(header: Text("prematch.saved")) {
                    Picker("settings.sort_order", selection: $playerSortOrder) {
                        Text("settings.sort_name").tag(Player.SortOrder.name)
                        Text("settings.sort_most_played").tag(Player.SortOrder.mostPlayed)
                        Text("settings.sort_recently_used").tag(Player.SortOrder.recentlyUsed)
                        Text("settings.sort_created").tag(Player.SortOrder.created)
                        Text("settings.sort_name_desc").tag(Player.SortOrder.nameDescending)
                    }
                    ForEach(filteredRoster) { player in
                        Button { onSelect(player.name) } label: {
                            HStack {
                                playerRow(name: player.name, color: player.avatarColor, icon: player.iconName)
                                if let against = h2hAgainst,
                                   let record = StatsCalculator.headToHeadIfAny(me: against, opponent: player.name, history: history, roster: roster) {
                                    Text("\(record.wins)W – \(record.losses)L")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            if !filteredFriends.isEmpty {
                Section(header: Text("prematch.friends")) {
                    ForEach(filteredFriends, id: \.participantId) { friend in
                        Button { onSelect(friend.displayName) } label: {
                            HStack {
                                playerRow(name: friend.displayName, color: .gray, icon: nil)
                                if let against = h2hAgainst,
                                   let record = StatsCalculator.headToHeadIfAny(me: against, opponent: friend.displayName, history: history, roster: roster) {
                                    Text("\(record.wins)W – \(record.losses)L")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Button { showAddPlayer = true } label: {
                    Label("prematch.add_new", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPlayer) {
            let appearance = Player.randomDefaultAppearance()
            let defaultPlayer = Player(
                name: "",
                colorIndex: appearance.colorIndex,
                iconName: appearance.iconName,
                clubId: selectedClubId
            )
            PlayerEditView(initialPlayer: defaultPlayer, existingNames: roster.map(\.name)) { newPlayer in
                addPlayer(newPlayer, thenSelect: onSelect)
                showAddPlayer = false
            }
        }
    }

    private func playerRow(name: String, color: Color, icon: String?) -> some View {
        HStack(spacing: 10) {
            AvatarView(name: name, color: color, size: 28, iconName: icon)
            Text(name)
            Spacer()
        }
    }
}
