//
//  AddMatchView.swift
//  badminton score tracker (iOS)
//
//  Issue #278: log a match's final result without playing it live (scored on
//  paper, or the app wasn't running during play). iOS-only — manual score
//  entry only needs Steppers/TextFields, but the date field needs a
//  DatePicker, and this target has no DatePicker-editing precedent on Watch
//  (see ClubDetailView's Season section, ProfileView's birthday field). A
//  standalone sheet rather than a reuse of PreMatchView: PreMatchView drives
//  the *next* live match via AppStorage match-config keys and a forced
//  near→far step sequence, while this form edits a one-off past MatchRecord
//  with local @State and lets every slot be picked in any order. The player
//  picker below is a deliberate, trimmed duplicate of PreMatchView's (no
//  head-to-head, no mode/club pickers — those live in this form already).
//

import SwiftUI
import BadmintonCore

struct AddMatchView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName

    /// Upper bound for the Games Stepper — generous enough for any real
    /// Match Format (the highest is Best of 5) plus room for an unusual
    /// manually-entered result, not a rule about how many games a match
    /// "should" have. Games actually played can legitimately be even (a
    /// straight-sets sweep) or odd (a match that went to a decider) — see
    /// `enteredGames`'s even-count warning below, which flags rather than
    /// blocks, since even is common, not wrong.
    private static let maxGames = 7

    @State private var gameMode: GameMode = .singles
    @State private var nearName = ""
    @State private var nearPartnerName = ""
    @State private var farName = ""
    @State private var farPartnerName = ""
    @State private var games: [EditableGameScore]
    @State private var date = Date()
    @State private var clubId: UUID?
    @State private var isOfficial = true
    @State private var opponentParticipantId: String?
    @State private var activePicker: PickerSlot?

    struct EditableGameScore: Identifiable {
        let id = UUID()
        var my: Int = 0
        var opponent: Int = 0
    }

    /// Starts with just enough rows to decide a match in the fewest games
    /// under the device's current Match Format (e.g. Best of 1 → 1 row, Best
    /// of 3 → 2 rows) rather than a fixed count — a single-game result is the
    /// default when that's what the format is, not something to delete a row
    /// to reach.
    init() {
        let storedGamesInMatch = UserDefaults.standard.integer(forKey: AppStorageKeys.gamesInMatch)
        let initialGamesInMatch = storedGamesInMatch == 0 ? 3 : storedGamesInMatch
        let gamesToWin = (initialGamesInMatch / 2) + 1
        _games = State(initialValue: Array(repeating: EditableGameScore(), count: gamesToWin))
    }

    private enum PickerSlot: Identifiable {
        case near, nearPartner, far, farPartner
        var id: Self { self }
    }

    private var nearDisplayName: String { nearName.isEmpty ? myName : nearName }
    private var roster: [Player] { appStore.roster }

    /// Every non-empty score row, as immutable `GameScore`s — a row left at
    /// 0-0 reads as "not entered", since no completed badminton game can
    /// actually end 0-0.
    private var enteredGames: [GameScore] {
        games.filter { $0.my != 0 || $0.opponent != 0 }.map { GameScore(my: $0.my, opponent: $0.opponent) }
    }

    private var derivedResult: MatchRecord.ManualResult? {
        MatchRecord.resultFromManualGames(enteredGames)
    }

    private var selectedClubTracksStandings: Bool {
        guard let clubId else { return false }
        return appStore.clubs.first(where: { $0.id == clubId })?.trackStandings ?? true
    }

    private var isValid: Bool {
        guard !farName.isEmpty, derivedResult != nil else { return false }
        if gameMode == .doubles {
            return !nearPartnerName.isEmpty && !farPartnerName.isEmpty
        }
        return true
    }

    var body: some View {
        NavigationStack {
            Form {
                playersSection
                gamesSection
                detailsSection
            }
            .navigationTitle("addmatch.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("history.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("addmatch.save") { save() }
                        .disabled(!isValid)
                }
            }
            .sheet(item: $activePicker) { slot in
                AddMatchPlayerPicker(
                    titleKey: pickerTitle(for: slot),
                    meLabel: pickerMeLabel(for: slot),
                    excluding: pickerExcluding(for: slot),
                    usedGuestTokens: pickerUsedGuestTokens(for: slot),
                    clubId: clubId,
                    onSelect: { name, participantId in setName(name, participantId: participantId, for: slot) }
                )
            }
        }
    }

    // MARK: - Players section

    private var playersSection: some View {
        Section(header: Text("addmatch.players_section")) {
            Picker("settings.mode", selection: $gameMode) {
                Text("settings.singles").tag(GameMode.singles)
                Text("settings.doubles").tag(GameMode.doubles)
            }
            .pickerStyle(.segmented)
            .onChange(of: gameMode) { _, newValue in
                if newValue == .singles {
                    nearPartnerName = ""
                    farPartnerName = ""
                }
            }

            playerRow(titleKey: "prematch.near_side", value: nearDisplayName, placeholder: false, slot: .near)
            if gameMode == .doubles {
                playerRow(titleKey: "prematch.near_partner", value: nearPartnerName,
                          placeholder: nearPartnerName.isEmpty, slot: .nearPartner)
            }
            playerRow(titleKey: "prematch.far_side", value: farName, placeholder: farName.isEmpty, slot: .far)
            if gameMode == .doubles {
                playerRow(titleKey: "prematch.far_partner", value: farPartnerName,
                          placeholder: farPartnerName.isEmpty, slot: .farPartner)
            }
        }
    }

    private func avatarColor(for name: String) -> Color {
        roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        roster.first(where: { $0.name == name })?.iconName
    }

    private func playerRow(titleKey: LocalizedStringKey, value: String, placeholder: Bool, slot: PickerSlot) -> some View {
        let displayName = Player.displayName(for: value)
        let color = Player.isGuestName(value) ? Player.guestAvatarColor(for: value) : avatarColor(for: value)
        return Button {
            activePicker = slot
        } label: {
            HStack(spacing: 10) {
                if !placeholder {
                    AvatarView(name: displayName, color: color, size: 28,
                               iconName: Player.isGuestName(value) ? nil : avatarIcon(for: value))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(titleKey).font(.caption).foregroundStyle(.secondary)
                    Text(placeholder ? NSLocalizedString("addmatch.select_player", comment: "") : displayName)
                        .foregroundStyle(placeholder ? AnyShapeStyle(.secondary) : AnyShapeStyle(HierarchicalShapeStyle.primary))
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Games section

    private var gamesSection: some View {
        Section {
            Stepper(value: gameCountBinding, in: 1...Self.maxGames) {
                Text(String(format: NSLocalizedString("addmatch.game_count_label", comment: ""), games.count))
            }

            ForEach(games.indices, id: \.self) { idx in
                HStack {
                    Text(String(format: NSLocalizedString("addmatch.game_number", comment: ""), idx + 1))
                        .foregroundStyle(.secondary)
                    Spacer()
                    scoreField(value: $games[idx].my)
                    Text(verbatim: "–").foregroundStyle(.secondary)
                    scoreField(value: $games[idx].opponent)
                }
            }
            .onDelete(perform: deleteGames)
        } header: {
            Text("addmatch.games_section")
        } footer: {
            if derivedResult == nil {
                Text("addmatch.result_error")
            } else if enteredGames.count % 2 == 0 {
                Text("addmatch.even_games_warning")
            }
        }
    }

    /// The Stepper controls total row *count*, not any particular row's
    /// identity — growing appends fresh empty rows at the end, shrinking
    /// removes from the end. Swiping a specific row still works
    /// independently (`deleteGames`) for removing a wrongly-added row
    /// that isn't the last one.
    private var gameCountBinding: Binding<Int> {
        Binding(
            get: { games.count },
            set: { newValue in
                let clamped = max(1, min(newValue, Self.maxGames))
                if clamped > games.count {
                    games.append(contentsOf: (games.count..<clamped).map { _ in EditableGameScore() })
                } else if clamped < games.count {
                    games.removeLast(games.count - clamped)
                }
            }
        )
    }

    private func scoreField(value: Binding<Int>) -> some View {
        TextField("0", value: Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = max(0, min($0, 99)) }
        ), format: .number)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .frame(width: 44)
    }

    private func deleteGames(at offsets: IndexSet) {
        guard games.count - offsets.count >= 1 else { return }
        games.remove(atOffsets: offsets)
    }

    // MARK: - Details section

    private var detailsSection: some View {
        Section {
            DatePicker("addmatch.date_label", selection: $date, in: ...Date())
            if !appStore.clubs.isEmpty {
                Picker("playeredit.club", selection: $clubId) {
                    Text("playeredit.club_personal").tag(UUID?.none)
                    ForEach(appStore.clubs) { club in
                        Text(club.name).tag(UUID?.some(club.id))
                    }
                }
                .onChange(of: clubId) { _, _ in
                    if !selectedClubTracksStandings { isOfficial = true }
                }
                if selectedClubTracksStandings {
                    Toggle("prematch.official_match", isOn: $isOfficial)
                }
            }
        } footer: {
            if selectedClubTracksStandings {
                Text("prematch.official_match_footer")
            }
        }
    }

    // MARK: - Picker slot resolution

    private func currentNames(excludingSlot slot: PickerSlot) -> [String] {
        var names: [String] = []
        if slot != .near { names.append(nearDisplayName) }
        if slot != .nearPartner && gameMode == .doubles { names.append(nearPartnerName) }
        if slot != .far { names.append(farName) }
        if slot != .farPartner && gameMode == .doubles { names.append(farPartnerName) }
        return names.filter { !$0.isEmpty }
    }

    private func pickerTitle(for slot: PickerSlot) -> LocalizedStringKey {
        switch slot {
        case .near: "prematch.near_side"
        case .nearPartner: "prematch.near_partner"
        case .far: "prematch.far_side"
        case .farPartner: "prematch.far_partner"
        }
    }

    private func pickerMeLabel(for slot: PickerSlot) -> String? {
        currentNames(excludingSlot: slot).contains(myName) ? nil : myName
    }

    private func pickerExcluding(for slot: PickerSlot) -> [String] {
        currentNames(excludingSlot: slot)
    }

    private func pickerUsedGuestTokens(for slot: PickerSlot) -> Set<String> {
        Set(currentNames(excludingSlot: slot).filter(Player.isGuestName))
    }

    private func setName(_ name: String, participantId: String?, for slot: PickerSlot) {
        switch slot {
        case .near: nearName = name
        case .nearPartner: nearPartnerName = name
        case .far:
            farName = name
            opponentParticipantId = participantId
        case .farPartner: farPartnerName = name
        }
    }

    // MARK: - Save

    private func resolvedPlayerId(for name: String, isNearSide: Bool, roster: [Player]) -> UUID? {
        if isNearSide && (nearName.isEmpty || nearName == myName) {
            return appStore.localPlayerId
        }
        if Player.isGuestName(name) { return nil }
        return roster.first(where: { $0.name == name })?.id
    }

    private func resolvedPartnerPlayerId(for name: String?, roster: [Player]) -> UUID? {
        guard let name, !Player.isGuestName(name) else { return nil }
        return roster.first(where: { $0.name == name })?.id
    }

    private func saveToRoster(_ name: String) {
        guard Player.shouldBeStoredAsSavedPlayer(name, currentUserName: myName) else { return }
        var roster = appStore.roster
        if !roster.contains(where: { $0.name == name }) {
            let appearance = Player.randomDefaultAppearance()
            roster.insert(Player(name: name, colorIndex: appearance.colorIndex, iconName: appearance.iconName), at: 0)
            appStore.saveRoster(roster)
        }
    }

    private func save() {
        guard let result = derivedResult else { return }
        let effectiveNear = nearDisplayName
        let effectiveFar = farName
        let effectiveNearPartner = gameMode == .doubles && !nearPartnerName.isEmpty ? nearPartnerName : nil
        let effectiveFarPartner = gameMode == .doubles && !farPartnerName.isEmpty ? farPartnerName : nil

        saveToRoster(effectiveFar)
        saveToRoster(effectiveNear)
        if let partner = effectiveNearPartner { saveToRoster(partner) }
        if let partner = effectiveFarPartner { saveToRoster(partner) }

        let currentRoster = appStore.roster
        let record = MatchRecord(
            games: enteredGames,
            myGamesWon: result.myGamesWon,
            opponentGamesWon: result.opponentGamesWon,
            winner: result.winner,
            myName: effectiveNear,
            opponentName: effectiveFar,
            date: date,
            duration: 0,
            myPlayerId: resolvedPlayerId(for: effectiveNear, isNearSide: true, roster: currentRoster),
            opponentPlayerId: resolvedPlayerId(for: effectiveFar, isNearSide: false, roster: currentRoster),
            myPartnerName: effectiveNearPartner,
            opponentPartnerName: effectiveFarPartner,
            myPartnerPlayerId: resolvedPartnerPlayerId(for: effectiveNearPartner, roster: currentRoster),
            opponentPartnerPlayerId: resolvedPartnerPlayerId(for: effectiveFarPartner, roster: currentRoster),
            clubId: clubId,
            isOfficial: selectedClubTracksStandings ? isOfficial : true,
            opponentParticipantId: (gameMode == .singles && clubId == nil) ? opponentParticipantId : nil
        )
        appStore.saveHistory(appStore.history + [record])
        dismiss()
    }
}

/// A trimmed duplicate of PreMatchView's roster/friends/guest picker — see
/// this file's header comment for why it isn't shared directly.
private struct AddMatchPlayerPicker: View {
    let titleKey: LocalizedStringKey
    let meLabel: String?
    let excluding: [String]
    let usedGuestTokens: Set<String>
    let clubId: UUID?
    let onSelect: (String, String?) -> Void

    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKeys.playerSortOrder) private var playerSortOrder: Player.SortOrder = .name
    @State private var showAddPlayer = false

    private var roster: [Player] { appStore.roster }

    private func avatarColor(for name: String) -> Color {
        roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        roster.first(where: { $0.name == name })?.iconName
    }

    private func select(_ name: String, participantId: String? = nil) {
        onSelect(name, participantId)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle(titleKey)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("history.cancel") { dismiss() }
                    }
                }
        }
    }

    private var list: some View {
        let guestToken = Player.randomGuestToken(excluding: usedGuestTokens)
        let guestLabel = Player.displayName(for: guestToken)
        let filteredRoster = Player.sortedPlayers(
            roster.filter { !excluding.contains($0.name) && $0.clubId == clubId },
            order: playerSortOrder
        )
        let filteredFriends = clubId == nil
            ? appStore.friends
                .filter { !excluding.contains($0.displayName) }
                .sorted { $0.displayName < $1.displayName }
            : []

        return List {
            Section(header: Text(titleKey)) {
                if let meLabel {
                    Button { select(meLabel) } label: {
                        HStack(spacing: 10) {
                            playerRow(name: meLabel, color: avatarColor(for: meLabel), icon: avatarIcon(for: meLabel), emphasized: true)
                            youBadge
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { select(guestToken) } label: {
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
                    ForEach(filteredRoster) { player in
                        Button { select(player.name) } label: {
                            playerRow(name: player.name, color: player.avatarColor, icon: player.iconName)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !filteredFriends.isEmpty {
                Section(header: Text("prematch.friends")) {
                    ForEach(filteredFriends, id: \.participantId) { friend in
                        Button { select(friend.displayName, participantId: friend.participantId) } label: {
                            playerRow(name: friend.displayName, color: .gray, icon: nil)
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
            let defaultPlayer = Player(name: "", colorIndex: appearance.colorIndex, iconName: appearance.iconName, clubId: clubId)
            PlayerEditView(initialPlayer: defaultPlayer, existingNames: roster.map(\.name)) { newPlayer in
                var r = roster
                if !r.contains(where: { $0.name == newPlayer.name }) {
                    r.insert(newPlayer, at: 0)
                    appStore.saveRoster(r)
                }
                select(newPlayer.name)
                showAddPlayer = false
            }
        }
    }

    private var youBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption)
            .foregroundStyle(.tint)
            .accessibilityLabel("clubs.you")
    }

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
