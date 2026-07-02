//
//  PreMatchView.swift
//  badminton score tracker Watch App
//
//  Two-step player selection (near side, then far side) before a match,
//  with head-to-head records surfaced against the chosen near-side player.
//

import SwiftUI

struct PreMatchView: View {
    @Binding var currentView: ContentView.AppView
    @EnvironmentObject private var appStore: AppStore
    @AppStorage("myName") private var myName = Player.defaultMyName
    @AppStorage("matchMyName") private var matchMyName = ""
    @AppStorage("matchOpponentName") private var matchOpponentName = ""

    private var history: [MatchRecord] { appStore.history }

    private func h2h(me: String, opponent: String) -> (wins: Int, losses: Int)? {
        let mePlayer = roster.first(where: { $0.name == me })
        let oppPlayer = roster.first(where: { $0.name == opponent })
        let relevant = history.filter { record in
            let namesMatch = (record.myName == me && record.opponentName == opponent) ||
                             (record.myName == opponent && record.opponentName == me)
            let idsMatch: Bool = {
                guard let meId = mePlayer?.id, let oppId = oppPlayer?.id else { return false }
                return (record.myPlayerId == meId && record.opponentPlayerId == oppId) ||
                       (record.myPlayerId == oppId && record.opponentPlayerId == meId)
            }()
            return namesMatch || idsMatch
        }
        guard !relevant.isEmpty else { return nil }
        let wins = relevant.filter { record in
            (record.myName == me || record.myPlayerId == mePlayer?.id) && record.winner == me
        }.count
        return (wins: wins, losses: relevant.count - wins)
    }

    @State private var step: Step = .pickMyPlayer
    @State private var showAddPlayer = false
    @State private var newPlayerName = ""
    @State private var newPlayerColorIndex = 0
    @State private var newPlayerIconName: String? = nil

    enum Step { case pickMyPlayer, pickOpponent }

    private var roster: [Player] { appStore.roster }

    private func saveToRoster(name: String) {
        guard Player.shouldBeStoredAsSavedPlayer(name, currentUserName: myName) else { return }
        var r = roster
        if !r.contains(where: { $0.name == name }) {
            let colorIndex = r.count % Player.avatarColors.count
            r.insert(Player(name: name, colorIndex: newPlayerColorIndex), at: 0)
            appStore.saveRoster(r)
        }
    }

    private func avatarColor(for name: String) -> Color {
        roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        roster.first(where: { $0.name == name })?.iconName
    }

    private func playerPicker(title: String, defaultLabel: String, defaultColor: Color, guestLabel: String, excluding: String? = nil, h2hAgainst: String? = nil, onSelect: @escaping (String) -> Void) -> some View {
        let filteredRoster = roster.filter { player in
            player.name != myName && player.name != excluding
        }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
        return List {
            Section(header: Text(title)) {
                if !defaultLabel.isEmpty {
                    Button(action: { onSelect(defaultLabel) }) {
                        HStack {
                            AvatarView(name: defaultLabel, color: defaultColor, size: 24, iconName: avatarIcon(for: defaultLabel))
                            Text(defaultLabel)
                        }
                    }
                }
                Button(action: { onSelect(guestLabel) }) {
                    HStack {
                        AvatarView(name: guestLabel, color: .gray, size: 24)
                        Text(guestLabel)
                    }
                }
            }
            if !filteredRoster.isEmpty {
                Section(header: Text("prematch.saved")) {
                    ForEach(filteredRoster) { player in
                        Button(action: { onSelect(player.name) }) {
                            HStack {
                                AvatarView(name: player.name, color: player.avatarColor, size: 24, iconName: player.iconName)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(player.name)
                                    if let against = h2hAgainst,
                                       let record = h2h(me: against, opponent: player.name) {
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

                        ForEach(Player.avatarImageNames, id: \.self) { imageName in
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
                        ForEach(Player.sportIcons, id: \.self) { icon in
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
        switch step {
        case .pickMyPlayer:
            playerPicker(title: NSLocalizedString("prematch.near_side", comment: ""), defaultLabel: myName, defaultColor: avatarColor(for: myName), guestLabel: Player.guestNearLabel) { name in
                matchMyName = name
                step = .pickOpponent
            }
            .navigationTitle("prematch.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { currentView = .menu }
                }
            }

        case .pickOpponent:
            let nearName = matchMyName.isEmpty ? myName : matchMyName
            playerPicker(title: NSLocalizedString("prematch.far_side", comment: ""), defaultLabel: "", defaultColor: .gray, guestLabel: Player.guestFarLabel, excluding: nearName, h2hAgainst: nearName) { name in
                matchOpponentName = name
                currentView = .game
            }
            .navigationTitle("prematch.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { step = .pickMyPlayer }
                }
            }
        }
    }
}
