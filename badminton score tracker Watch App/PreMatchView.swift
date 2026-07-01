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
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("matchMyName") private var matchMyName = ""
    @AppStorage("matchOpponentName") private var matchOpponentName = ""
    @AppStorage("playerRoster") private var rosterData: Data = Data()
    @AppStorage("matchHistory") private var matchHistoryData: Data = Data()

    private var history: [MatchRecord] {
        PersistenceStore.decodeHistory(matchHistoryData)
    }

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

    enum Step { case pickMyPlayer, pickOpponent }

    private var roster: [Player] {
        PersistenceStore.decodeRoster(rosterData)
    }

    private static let guestNames: Set<String> = ["Guest (Near)", "Guest (Far)"]

    private func saveToRoster(name: String) {
        guard !name.isEmpty, !Self.guestNames.contains(name) else { return }
        var r = roster
        if !r.contains(where: { $0.name == name }) {
            let colorIndex = r.count % Player.avatarColors.count
            r.insert(Player(name: name, colorIndex: colorIndex), at: 0)
            if let encoded = PersistenceStore.encodeRoster(r) { rosterData = encoded }
        }
    }

    private func avatarColor(for name: String) -> Color {
        roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        roster.first(where: { $0.name == name })?.iconName
    }

    private func playerPicker(title: String, defaultLabel: String, defaultColor: Color, guestLabel: String, excluding: String? = nil, h2hAgainst: String? = nil, onSelect: @escaping (String) -> Void) -> some View {
        let filteredRoster = roster.filter { $0.name != excluding }
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
            VStack(spacing: 12) {
                Text("prematch.new_player")
                    .font(.headline)
                TextField("prematch.name", text: $newPlayerName)
                Button("prematch.add") {
                    let name = newPlayerName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        saveToRoster(name: name)
                        onSelect(name)
                        showAddPlayer = false
                        newPlayerName = ""
                    }
                }
                .disabled(newPlayerName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
    }

    var body: some View {
        switch step {
        case .pickMyPlayer:
            playerPicker(title: NSLocalizedString("prematch.near_side", comment: ""), defaultLabel: myName, defaultColor: avatarColor(for: myName), guestLabel: "Guest (Near)") { name in
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
            playerPicker(title: NSLocalizedString("prematch.far_side", comment: ""), defaultLabel: "", defaultColor: .gray, guestLabel: "Guest (Far)", excluding: nearName, h2hAgainst: nearName) { name in
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
