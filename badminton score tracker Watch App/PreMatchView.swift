//
//  PreMatchView.swift
//  badminton score tracker Watch App
//
//  Two-step player selection (near side, then far side) before a match,
//  with head-to-head records surfaced against the chosen near-side player.
//

import SwiftUI
import BadmintonCore

struct PreMatchView: View {
    @Binding var currentView: ContentView.AppView
    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.matchMyName) private var matchMyName = ""
    @AppStorage(AppStorageKeys.matchOpponentName) private var matchOpponentName = ""
    @AppStorage(AppStorageKeys.matchMyPartnerName) private var matchMyPartnerName = ""
    @AppStorage(AppStorageKeys.matchOpponentPartnerName) private var matchOpponentPartnerName = ""
    @AppStorage(AppStorageKeys.matchClubId) private var matchClubId = ""
    @AppStorage(AppStorageKeys.gameMode) private var gameMode: SettingsView.GameMode = .singles
    @AppStorage(AppStorageKeys.playerSortOrder) private var playerSortOrder: Player.SortOrder = .name

    private var clubSelection: Binding<UUID?> {
        Binding(
            get: { UUID(uuidString: matchClubId) },
            set: { matchClubId = $0?.uuidString ?? "" }
        )
    }

    private var history: [MatchRecord] { appStore.history }

    @State private var step: Step = .pickMyPlayer
    @State private var showAddPlayer = false
    @EnvironmentObject private var storeManager: StoreManager
    @State private var newPlayerName = ""
    @State private var newPlayerColorIndex = 0
    @State private var newPlayerIconName: String? = nil

    /// The quick-add sheet stays friction-free: unentitled users just see the
    /// free avatar subset (no locks/paywall here — the full PlayerEditView
    /// carries those).
    private var quickAddAvatarImages: [String] {
        storeManager.entitlements.hasAllAvatars ? Player.avatarImageNames : Player.freeAvatarImageNames
    }

    private var quickAddSportIcons: [String] {
        storeManager.entitlements.hasAllAvatars ? Player.sportIcons : Player.freeSportIcons
    }

    enum Step { case pickMyPlayer, pickMyPartner, pickOpponent, pickOpponentPartner }

    private var isDoubles: Bool { gameMode == .doubles }

    private var roster: [Player] { appStore.roster }

    private func saveToRoster(name: String) {
        guard Player.shouldBeStoredAsSavedPlayer(name, currentUserName: myName) else { return }
        var r = roster
        if !r.contains(where: { $0.name == name }) {
            r.insert(Player(name: name, colorIndex: newPlayerColorIndex, clubId: UUID(uuidString: matchClubId)), at: 0)
            appStore.saveRoster(r)
        }
    }

    private func avatarColor(for name: String) -> Color {
        roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        roster.first(where: { $0.name == name })?.iconName
    }

    private func playerPicker(title: String, defaultLabel: String, defaultColor: Color, guestLabel: String, guestToken: String, excluding: [String] = [], showClubPicker: Bool = false, h2hAgainst: String? = nil, onSelect: @escaping (String) -> Void) -> some View {
        let selectedClubId = UUID(uuidString: matchClubId)
        let filteredRoster = Player.sortedPlayers(
            roster.filter { player in
                player.name != myName && !excluding.contains(player.name) && player.clubId == selectedClubId
            },
            order: playerSortOrder,
            history: history
        )
        let filteredFriends = selectedClubId == nil
            ? appStore.friends
                .filter { $0.displayName != myName && !excluding.contains($0.displayName) }
                .sorted { $0.displayName < $1.displayName }
            : []
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        return List {
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
            Section(header: Text(title)) {
                if !defaultLabel.isEmpty {
                    Button(action: { onSelect(defaultLabel) }) {
                        HStack {
                            AvatarView(name: defaultLabel, color: defaultColor, size: 24, iconName: avatarIcon(for: defaultLabel))
                            Text(defaultLabel)
                        }
                    }
                }
                Button(action: { onSelect(guestToken) }) {
                    HStack {
                        AvatarView(name: guestLabel, color: .gray, size: 24)
                        Text(guestLabel)
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
                        Button(action: { onSelect(player.name) }) {
                            HStack {
                                AvatarView(name: player.name, color: player.avatarColor, size: 24, iconName: player.iconName)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(player.name)
                                    if let against = h2hAgainst,
                                       let record = StatsCalculator.headToHeadIfAny(me: against, opponent: player.name, history: history, roster: roster) {
                                        Text("\(record.wins)W – \(record.losses)L")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if !filteredFriends.isEmpty {
                Section(header: Text("prematch.friends")) {
                    ForEach(filteredFriends, id: \.participantId) { friend in
                        Button(action: { onSelect(friend.displayName) }) {
                            HStack {
                                AvatarView(name: friend.displayName, color: .gray, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(friend.displayName)
                                    if let against = h2hAgainst,
                                       let record = StatsCalculator.headToHeadIfAny(me: against, opponent: friend.displayName, history: history, roster: roster) {
                                        Text("\(record.wins)W – \(record.losses)L")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Section {
                Button(action: { showAddPlayer = true }) {
                    Label("prematch.add_new", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPlayer) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("prematch.new_player")
                        .font(.headline)

                    HStack {
                        Spacer()
                        AvatarView(name: newPlayerName, color: Player.avatarColors[newPlayerColorIndex % Player.avatarColors.count], size: 40, iconName: newPlayerIconName)
                        Spacer()
                    }

                    TextField("prematch.name", text: $newPlayerName)

                    Text("playeredit.color")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Array(Player.avatarColors.enumerated()), id: \.offset) { index, color in
                            Circle()
                                .fill(color)
                                .frame(height: 24)
                                .overlay(
                                    Circle().stroke(Color.white, lineWidth: newPlayerColorIndex == index ? 2.5 : 0)
                                )
                                .onTapGesture { newPlayerColorIndex = index }
                        }
                    }

                    Text("playeredit.avatar")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(newPlayerIconName == nil ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.25))
                            Text("A")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .frame(height: 36)
                        .onTapGesture { newPlayerIconName = nil }

                        ForEach(quickAddAvatarImages, id: \.self) { imageName in
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(newPlayerIconName == imageName ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.25))
                                Image(imageName)
                                    .resizable()
                                    .scaledToFit()
                                    .padding(3)
                            }
                            .frame(height: 36)
                            .onTapGesture { newPlayerIconName = imageName }
                        }
                    }

                    Text("playeredit.icons")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(quickAddSportIcons, id: \.self) { icon in
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(newPlayerIconName == icon ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.25))
                                Image(systemName: icon)
                                    .font(.system(size: 14))
                                    .foregroundColor(.white)
                            }
                            .frame(height: 36)
                            .onTapGesture { newPlayerIconName = icon }
                        }
                    }

                    Button("prematch.add") {
                        let name = newPlayerName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            saveToRoster(name: name)
                            onSelect(name)
                            showAddPlayer = false
                            newPlayerName = ""
                            newPlayerColorIndex = 0
                            newPlayerIconName = nil
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 8)
            }
        }
    }

    var body: some View {
        Group {
            content
        }
        .onAppear {
            if !isDoubles {
                matchMyPartnerName = ""
                matchOpponentPartnerName = ""
            }
            if let id = UUID(uuidString: matchClubId), !appStore.clubs.contains(where: { $0.id == id }) {
                matchClubId = ""
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .pickMyPlayer:
            playerPicker(title: NSLocalizedString("prematch.near_side", comment: ""), defaultLabel: myName, defaultColor: avatarColor(for: myName), guestLabel: Player.guestNearLabel, guestToken: Player.guestNearToken, showClubPicker: true) { name in
                matchMyName = name
                step = isDoubles ? .pickMyPartner : .pickOpponent
            }
            .navigationTitle("prematch.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { currentView = .menu }
                }
            }

        case .pickMyPartner:
            playerPicker(title: NSLocalizedString("prematch.near_partner", comment: ""), defaultLabel: "", defaultColor: .gray, guestLabel: Player.guestNearLabel, guestToken: Player.guestNearToken, excluding: [matchMyName]) { name in
                matchMyPartnerName = name
                step = .pickOpponent
            }
            .navigationTitle("prematch.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { step = .pickMyPlayer }
                }
            }

        case .pickOpponent:
            let nearName = matchMyName.isEmpty ? myName : matchMyName
            let nearExclusions = [nearName, matchMyPartnerName].filter { !$0.isEmpty }
            playerPicker(title: NSLocalizedString("prematch.far_side", comment: ""), defaultLabel: "", defaultColor: .gray, guestLabel: Player.guestFarLabel, guestToken: Player.guestFarToken, excluding: nearExclusions, h2hAgainst: nearName) { name in
                matchOpponentName = name
                if isDoubles {
                    step = .pickOpponentPartner
                } else {
                    currentView = .game
                }
            }
            .navigationTitle("prematch.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { step = isDoubles ? .pickMyPartner : .pickMyPlayer }
                }
            }

        case .pickOpponentPartner:
            let nearName = matchMyName.isEmpty ? myName : matchMyName
            let exclusions = [nearName, matchMyPartnerName, matchOpponentName].filter { !$0.isEmpty }
            playerPicker(title: NSLocalizedString("prematch.far_partner", comment: ""), defaultLabel: "", defaultColor: .gray, guestLabel: Player.guestFarLabel, guestToken: Player.guestFarToken, excluding: exclusions) { name in
                matchOpponentPartnerName = name
                currentView = .game
            }
            .navigationTitle("prematch.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { step = .pickOpponent }
                }
            }
        }
    }
}
