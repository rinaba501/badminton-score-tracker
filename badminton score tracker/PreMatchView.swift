//
//  PreMatchView.swift
//  badminton score tracker (iOS)
//
//  Player selection before a match: near side, then far side, with
//  head-to-head records surfaced against the chosen near-side player.
//  Diverges from the Watch's PreMatchView here: the Watch steps through one
//  player per pushed screen, while iOS keeps a side's player and partner on
//  the same screen — picking the player swaps the same list in place to
//  prompt for the partner (no sheet, no extra "next" tap; a summary banner
//  keeps the already-picked player visible) instead of pushing a new
//  screen. Same match-config @AppStorage keys and guest-token identity,
//  driven by onReady/onCancel closures (no currentView binding). Adding a
//  new player reuses the iOS PlayerEditView.
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
    @AppStorage(AppStorageKeys.matchOpponentParticipantId) private var matchOpponentParticipantId = ""
    @AppStorage(AppStorageKeys.matchMyPartnerName) private var matchMyPartnerName = ""
    @AppStorage(AppStorageKeys.matchOpponentPartnerName) private var matchOpponentPartnerName = ""
    @AppStorage(AppStorageKeys.matchClubId) private var matchClubId = ""
    @AppStorage(AppStorageKeys.matchIsOfficial) private var matchIsOfficial = true
    @AppStorage(AppStorageKeys.gameMode) private var gameMode: GameMode = .singles
    @AppStorage(AppStorageKeys.playerSortOrder) private var playerSortOrder: Player.SortOrder = .name

    @State private var step: Step = .near
    /// Which slot of the current side is being picked. Doubles only ever
    /// reaches `.partner`; singles stays on `.player` the whole time.
    @State private var subStep: SubStep = .player
    @State private var showAddPlayer = false

    enum Step { case near, far }
    enum SubStep { case player, partner }

    private var clubSelection: Binding<UUID?> {
        Binding(
            get: { UUID(uuidString: matchClubId) },
            set: { matchClubId = $0?.uuidString ?? "" }
        )
    }

    /// False when no club is selected (Personal has no official/practice
    /// distinction) or the selected club has Standings tracking off (the
    /// distinction is moot with nothing to count toward) — gates whether
    /// the Official Match toggle shows at all.
    private var selectedClubTracksStandings: Bool {
        guard let id = clubSelection.wrappedValue else { return false }
        return appStore.clubs.first(where: { $0.id == id })?.trackStandings ?? true
    }

    private var history: [MatchRecord] { appStore.history }
    private var roster: [Player] { appStore.roster }
    private var isDoubles: Bool { gameMode == .doubles }
    private var nearDisplayName: String { matchMyName.isEmpty ? myName : matchMyName }

    // MARK: - Roster helpers

    private func avatarColor(for name: String) -> Color {
        roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        roster.first(where: { $0.name == name })?.iconName
    }

    private func avatarColor(forParticipant participantId: String) -> Color {
        guard let colorIndex = appStore.friendIdentities[participantId]?.colorIndex else { return .gray }
        return Player.avatarColors[colorIndex % Player.avatarColors.count]
    }

    private func avatarIcon(forParticipant participantId: String) -> String? {
        appStore.friendIdentities[participantId]?.iconName
    }

    private func addPlayer(_ player: Player, thenSelect select: (String, String?) -> Void) {
        var r = roster
        if !r.contains(where: { $0.name == player.name }) {
            r.insert(player, at: 0)
            appStore.saveRoster(r)
        }
        select(player.name, nil)
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
                    // picker's usedGuestTokens) at slots earlier than the
                    // one that sets them, so a leftover value from the
                    // *previous* match would otherwise be mistaken for a
                    // pick already made in this one.
                    matchMyPartnerName = ""
                    matchOpponentName = ""
                    matchOpponentParticipantId = ""
                    matchOpponentPartnerName = ""
                    if let id = UUID(uuidString: matchClubId), !appStore.clubs.contains(where: { $0.id == id }) {
                        matchClubId = ""
                    }
                    if !selectedClubTracksStandings {
                        matchIsOfficial = true
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .near:
            switch subStep {
            case .player:
                let usedGuestTokens = Set([matchMyPartnerName, matchOpponentName, matchOpponentPartnerName].filter(Player.isGuestName))
                picker(titleKey: "prematch.near_side",
                       defaultLabel: myName, defaultColor: avatarColor(for: myName),
                       usedGuestTokens: usedGuestTokens,
                       showModePicker: true, showClubPicker: true) { name, _ in
                    matchMyName = name
                    if isDoubles { subStep = .partner } else { step = .far }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("prematch.back", action: onCancel)
                    }
                }

            case .partner:
                let usedGuestTokens = Set([matchMyName, matchOpponentName, matchOpponentPartnerName].filter(Player.isGuestName))
                let excludingNames = [nearDisplayName]
                let meLabel = excludingNames.contains(myName) ? nil : myName
                picker(titleKey: "prematch.near_partner",
                       defaultLabel: meLabel, defaultColor: avatarColor(for: myName),
                       usedGuestTokens: usedGuestTokens,
                       excluding: excludingNames) { name, _ in
                    matchMyPartnerName = name
                    step = .far
                    subStep = .player
                }
                .safeAreaInset(edge: .top) {
                    summaryBanner(name: nearDisplayName) { subStep = .player }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("prematch.back") { subStep = .player }
                    }
                }
            }

        case .far:
            switch subStep {
            case .player:
                let usedGuestTokens = Set([matchMyName, matchMyPartnerName, matchOpponentPartnerName].filter(Player.isGuestName))
                let excludingNames = [nearDisplayName, matchMyPartnerName].filter { !$0.isEmpty }
                let meLabel = excludingNames.contains(myName) ? nil : myName
                picker(titleKey: "prematch.far_side",
                       defaultLabel: meLabel, defaultColor: avatarColor(for: myName),
                       usedGuestTokens: usedGuestTokens,
                       excluding: excludingNames,
                       h2hAgainst: nearDisplayName) { name, participantId in
                    matchOpponentName = name
                    matchOpponentParticipantId = participantId ?? ""
                    if isDoubles { subStep = .partner } else { onReady() }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("prematch.back") {
                            step = .near
                            subStep = isDoubles ? .partner : .player
                        }
                    }
                }

            case .partner:
                let usedGuestTokens = Set([matchMyName, matchMyPartnerName, matchOpponentName].filter(Player.isGuestName))
                let excludingNames = [nearDisplayName, matchMyPartnerName, matchOpponentName].filter { !$0.isEmpty }
                let meLabel = excludingNames.contains(myName) ? nil : myName
                picker(titleKey: "prematch.far_partner",
                       defaultLabel: meLabel, defaultColor: avatarColor(for: myName),
                       usedGuestTokens: usedGuestTokens,
                       excluding: excludingNames) { name, _ in
                    matchOpponentPartnerName = name
                    onReady()
                }
                .safeAreaInset(edge: .top) {
                    summaryBanner(name: matchOpponentName) { subStep = .player }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("prematch.back") { subStep = .player }
                    }
                }
            }
        }
    }

    /// Keeps the side's already-picked player visible while choosing their
    /// partner, so both slots read as one screen instead of two.
    private func summaryBanner(name: String, onChange: @escaping () -> Void) -> some View {
        let displayLabel = Player.displayName(for: name)
        let color = Player.isGuestName(name) ? Player.guestAvatarColor(for: name) : avatarColor(for: name)
        let icon = Player.isGuestName(name) ? nil : avatarIcon(for: name)
        return Button(action: onChange) {
            HStack(spacing: 10) {
                AvatarView(name: displayLabel, color: color, size: 24, iconName: icon)
                Text(displayLabel)
                Spacer()
                Text("ios.change_player")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .buttonStyle(.plain)
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
                        onSelect: @escaping (String, String?) -> Void) -> some View {
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
                    if selectedClubTracksStandings {
                        Toggle("prematch.official_match", isOn: $matchIsOfficial)
                    }
                } footer: {
                    if selectedClubTracksStandings {
                        Text("prematch.official_match_footer")
                    }
                }
            }

            Section(header: Text(titleKey)) {
                if let defaultLabel, !defaultLabel.isEmpty {
                    Button { onSelect(defaultLabel, nil) } label: {
                        HStack(spacing: 10) {
                            playerRow(name: defaultLabel, color: defaultColor,
                                      icon: avatarIcon(for: defaultLabel), emphasized: true)
                            youBadge
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { onSelect(guestToken, nil) } label: {
                    HStack(spacing: 10) {
                        AvatarView(name: guestLabel, color: Player.guestAvatarColor(for: guestToken), size: 28, iconName: nil)
                        Text(Player.guestButtonLabel)
                        Spacer()
                    }
                    .foregroundStyle(.primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                        Button { onSelect(player.name, nil) } label: {
                            HStack {
                                playerRow(name: player.name, color: player.avatarColor, icon: player.iconName)
                                if let against = h2hAgainst,
                                   let record = StatsCalculator.headToHeadIfAny(me: against, opponent: player.name, history: history, roster: roster) {
                                    Text("\(record.wins)W – \(record.losses)L")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !filteredFriends.isEmpty {
                Section(header: Text("prematch.friends")) {
                    ForEach(filteredFriends, id: \.participantId) { friend in
                        Button { onSelect(friend.displayName, friend.participantId) } label: {
                            HStack {
                                playerRow(
                                    name: friend.displayName,
                                    color: avatarColor(forParticipant: friend.participantId),
                                    icon: avatarIcon(forParticipant: friend.participantId)
                                )
                                if let against = h2hAgainst,
                                   let record = StatsCalculator.headToHeadIfAny(me: against, opponent: friend.displayName, history: history, roster: roster) {
                                    Text("\(record.wins)W – \(record.losses)L")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

    /// Same "me" marker ClubDetailView uses — `defaultLabel` is a pinned
    /// "Me" shortcut shown on any slot where you haven't already been
    /// placed in another slot this match.
    private var youBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption)
            .foregroundStyle(.tint)
            .accessibilityLabel("clubs.you")
    }

    /// Every row is a `Button`, so its label would otherwise inherit the
    /// accent tint and the whole list would read as links with nothing
    /// standing out. Names render in the primary label color; the accent is
    /// reserved for the pinned "you" row (`emphasized`), whose name is
    /// tinted alongside its `youBadge`.
    private func playerRow(name: String, color: Color, icon: String?, emphasized: Bool = false) -> some View {
        HStack(spacing: 10) {
            AvatarView(name: name, color: color, size: 28, iconName: icon)
            Text(name)
                .fontWeight(emphasized ? .semibold : .regular)
                .foregroundStyle(emphasized ? AnyShapeStyle(.tint) : AnyShapeStyle(HierarchicalShapeStyle.primary))
            Spacer()
        }
    }
}
