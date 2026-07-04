//
//  GameViewModel.swift
//  badminton score tracker Watch App
//
//  Owns all match business logic extracted from GameView: scoring, undo,
//  time mode, haptics coordination, match persistence. GameView becomes
//  layout-only and delegates every action here.
//

import SwiftUI
import WatchKit
import BadmintonCore

@MainActor
final class GameViewModel: ObservableObject {

    // MARK: - Published state

    @Published private(set) var match: BadmintonMatch
    @Published private(set) var undoStack: [BadmintonMatch] = []
    @Published private(set) var savedCurrentMatch = false
    @Published private(set) var matchStartDate = Date()
    @Published var showDiscardAlert = false
    @Published private(set) var timeRemaining: TimeInterval = 0
    @Published private(set) var timeModeWinner: Side? = nil
    @Published private(set) var suddenDeath = false

    // MARK: - AppStorage (match config — drives newMatch / saveMatch)

    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.matchMyName) private var matchMyName = ""
    @AppStorage(AppStorageKeys.matchOpponentName) private var matchOpponentName = ""
    @AppStorage(AppStorageKeys.matchMyPartnerName) private var matchMyPartnerName = ""
    @AppStorage(AppStorageKeys.matchOpponentPartnerName) private var matchOpponentPartnerName = ""
    @AppStorage(AppStorageKeys.gameMode) private var gameMode: SettingsView.GameMode = .singles
    @AppStorage(AppStorageKeys.pointsToWin) private var pointsToWin: Int = 21
    @AppStorage(AppStorageKeys.gamesInMatch) private var gamesInMatch: Int = 3
    @AppStorage(AppStorageKeys.announceScore) private var announceScore = true
    @AppStorage(AppStorageKeys.enableSounds) private var enableSounds = true
    @AppStorage(AppStorageKeys.timeModeEnabled) private var timeModeEnabled = false
    @AppStorage(AppStorageKeys.timeLimitMinutes) private var timeLimitMinutes = 10

    // MARK: - Dependencies

    private let hapticsProvider: HapticsProvider
    private let soundPlayer: SoundPlayer
    private let announcer: ScoreAnnouncer
    private let appStore: AppStore
    private let workoutManager: WorkoutManager

    // MARK: - Init

    init(hapticsProvider: HapticsProvider = WatchHapticsProvider(), appStore: AppStore = .shared) {
        self.hapticsProvider = hapticsProvider
        self.soundPlayer = SoundPlayer()
        self.announcer = ScoreAnnouncer()
        self.workoutManager = WorkoutManager()
        self.appStore = appStore
        self.match = BadmintonMatch()
    }

    // MARK: - Derived names (read by view)

    var effectiveMyName: String { matchMyName.isEmpty ? myName : matchMyName }
    // Defensive fallback for the (practically unreachable) case where GameView
    // appears with no opponent selected. Falls back to the guest *token*, not
    // guestFarLabel — this value can be persisted into MatchRecord.opponentName,
    // and storing a localized label there would make the same guest compare as
    // a different identity depending on the device's locale at save time.
    var effectiveOpponentName: String { matchOpponentName.isEmpty ? Player.guestFarToken : matchOpponentName }

    // Guarded by `gameMode` (not just non-empty) so a stale partner name left
    // over from a previous doubles match is ignored the moment the user is
    // back in singles — matches the defensive clear in PreMatchView.onAppear.
    var effectiveMyPartnerName: String? {
        gameMode == .doubles && !matchMyPartnerName.isEmpty ? matchMyPartnerName : nil
    }
    var effectiveOpponentPartnerName: String? {
        gameMode == .doubles && !matchOpponentPartnerName.isEmpty ? matchOpponentPartnerName : nil
    }

    var timeExpiredWinner: Bool { timeModeWinner != nil }
    var isTimeModeEnabled: Bool { timeModeEnabled }

    func name(for side: Side) -> String {
        side == .me ? effectiveMyName : effectiveOpponentName
    }

    func partnerName(for side: Side) -> String? {
        side == .me ? effectiveMyPartnerName : effectiveOpponentPartnerName
    }

    // MARK: - Scoring actions

    func tap(_ side: Side) {
        guard match.gameWinner == nil, match.matchWinner == nil, !timeExpiredWinner else { return }
        undoStack.append(match)

        if timeModeEnabled && suddenDeath {
            match.score(side)
            if match.gameWinner == nil {
                match.recordSuddenDeathGame(winner: side)
            }
            suddenDeath = false
            resolveAfterGame()
            return
        }

        let wasGamePoint = match.isGamePoint
        match.score(side)

        let announcementDelay: Double
        if match.matchWinner != nil {
            hapticsProvider.play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.hapticsProvider.play(.success)
            }
            if enableSounds { soundPlayer.playMatchWin() }
            announcementDelay = enableSounds ? 0.7 : 0
            saveMatch()
        } else if match.gameWinner != nil {
            hapticsProvider.play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.hapticsProvider.play(.retry)
            }
            if enableSounds { soundPlayer.playGameWin() }
            announcementDelay = enableSounds ? 0.5 : 0
        } else if !wasGamePoint && match.isGamePoint {
            hapticsProvider.play(.notification)
            if enableSounds { soundPlayer.playGamePoint() }
            announcementDelay = enableSounds ? 0.25 : 0
        } else {
            hapticsProvider.play(.click)
            if enableSounds { soundPlayer.playScore() }
            announcementDelay = enableSounds ? 0.25 : 0
        }

        if announcementDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + announcementDelay) { [weak self] in
                self?.announceCurrentScore()
            }
        } else {
            announceCurrentScore()
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        match = previous
        hapticsProvider.play(.directionUp)
    }

    func startNextGame() {
        undoStack.removeAll()
        suddenDeath = false
        match.startNextGame()
        hapticsProvider.play(.start)
    }

    func newMatch() {
        match = BadmintonMatch(
            pointsToWin: pointsToWin,
            pointCap: pointsToWin + 9,
            gamesToWin: (gamesInMatch / 2) + 1
        )
        undoStack.removeAll()
        savedCurrentMatch = false
        timeModeWinner = nil
        suddenDeath = false
        timeRemaining = TimeInterval(timeLimitMinutes * 60)
        matchStartDate = Date()
    }

    func saveMatch() {
        let winner = match.matchWinner ?? timeModeWinner
        guard !savedCurrentMatch, let winner else { return }
        savedCurrentMatch = true
        saveToRoster(effectiveOpponentName)
        saveToRoster(effectiveMyName)
        if let partner = effectiveMyPartnerName { saveToRoster(partner) }
        if let partner = effectiveOpponentPartnerName { saveToRoster(partner) }
        let currentRoster = appStore.roster
        var games = match.completedGames
        if timeModeEnabled && match.matchWinner == nil && (match.myScore > 0 || match.opponentScore > 0) {
            games.append(GameScore(my: match.myScore, opponent: match.opponentScore))
        }
        var newHistory = appStore.history
        newHistory.append(MatchRecord(
            games: games,
            myGamesWon: match.myGamesWon,
            opponentGamesWon: match.opponentGamesWon,
            winner: name(for: winner),
            myName: effectiveMyName,
            opponentName: effectiveOpponentName,
            date: Date(),
            duration: Date().timeIntervalSince(matchStartDate),
            myPlayerId: resolvedPlayerId(for: effectiveMyName, isNearSide: true, roster: currentRoster),
            opponentPlayerId: resolvedPlayerId(for: effectiveOpponentName, isNearSide: false, roster: currentRoster),
            myPartnerName: effectiveMyPartnerName,
            opponentPartnerName: effectiveOpponentPartnerName,
            myPartnerPlayerId: resolvedPartnerPlayerId(for: effectiveMyPartnerName, roster: currentRoster),
            opponentPartnerPlayerId: resolvedPartnerPlayerId(for: effectiveOpponentPartnerName, roster: currentRoster)
        ))
        appStore.saveHistory(newHistory)
        Task { await workoutManager.endWorkout() }
    }

    func discard() async {
        await workoutManager.endWorkout()
    }

    // MARK: - Time mode

    func tickTimer() {
        guard timeModeEnabled, timeModeWinner == nil, !suddenDeath,
              match.matchWinner == nil else { return }
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            handleTimeUp()
        }
    }

    func handleTimeUp() {
        guard timeModeWinner == nil else { return }
        speak(NSLocalizedString("speech.time_up", comment: ""))
        if match.myGamesWon != match.opponentGamesWon {
            let w: Side = match.myGamesWon > match.opponentGamesWon ? .me : .opponent
            timeModeWinner = w
            hapticsProvider.play(.success)
            if enableSounds { soundPlayer.playMatchWin() }
            saveMatch()
        } else if match.myScore != match.opponentScore {
            let w: Side = match.myScore > match.opponentScore ? .me : .opponent
            timeModeWinner = w
            hapticsProvider.play(.success)
            if enableSounds { soundPlayer.playMatchWin() }
            saveMatch()
        } else {
            suddenDeath = true
            hapticsProvider.play(.notification)
        }
    }

    // MARK: - Lifecycle

    func onAppear() {
        guard match.completedGames.isEmpty && match.myScore == 0 && match.opponentScore == 0 else { return }
        match = BadmintonMatch(
            pointsToWin: pointsToWin,
            pointCap: pointsToWin + 9,
            gamesToWin: (gamesInMatch / 2) + 1
        )
        if timeModeEnabled { timeRemaining = TimeInterval(timeLimitMinutes * 60) }
        Task { await workoutManager.startWorkout(startDate: matchStartDate) }
    }

    // MARK: - Private helpers

    private func resolveAfterGame() {
        if let winner = match.matchWinner {
            timeModeWinner = winner
            hapticsProvider.play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.hapticsProvider.play(.success)
            }
            if enableSounds { soundPlayer.playMatchWin() }
            saveMatch()
        } else if match.isTied {
            timeModeWinner = .me  // placeholder — overlay will show "Tie"
            saveMatch()
        } else {
            hapticsProvider.play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.hapticsProvider.play(.retry)
            }
            if enableSounds { soundPlayer.playGameWin() }
        }
    }

    private func speak(_ text: String) {
        guard announceScore else { return }
        announcer.speak(text)
    }

    private func announceCurrentScore() {
        let text = ScoreCallFormatter.format(
            match: match,
            myName: teamDisplayName(for: .me),
            opponentName: teamDisplayName(for: .opponent),
            locale: .current
        )
        speak(text)
    }

    /// "Alice" for singles, "Alice & Bob" (localized) for doubles — used
    /// anywhere a team's full spoken/displayed name is needed as one string.
    func teamDisplayName(for side: Side) -> String {
        let primary = Player.displayName(for: name(for: side))
        guard let partner = partnerName(for: side) else { return primary }
        return String(format: NSLocalizedString("game.team_names_format", comment: ""), primary, Player.displayName(for: partner))
    }

    /// Resolves the stable identity to stamp on a `MatchRecord` field. The
    /// near side is "Me" when no explicit match player was chosen (or the
    /// choice matches the local display name) — that identity is
    /// `appStore.localPlayerId`, not a roster lookup, since "Me" is
    /// deliberately never added to the roster. A guest token intentionally
    /// resolves to `nil`: the token itself is already a locale-independent
    /// identity marker, so no per-match UUID is needed.
    private func resolvedPlayerId(for name: String, isNearSide: Bool, roster: [Player]) -> UUID? {
        if isNearSide && (matchMyName.isEmpty || matchMyName == myName) {
            return appStore.localPlayerId
        }
        if Player.isGuestName(name) { return nil }
        return roster.first(where: { $0.name == name })?.id
    }

    /// Partners are never "Me" (PreMatchView's partner steps never offer that
    /// option), so this needs none of `resolvedPlayerId`'s near-side handling.
    private func resolvedPartnerPlayerId(for name: String?, roster: [Player]) -> UUID? {
        guard let name, !Player.isGuestName(name) else { return nil }
        return roster.first(where: { $0.name == name })?.id
    }

    private func saveToRoster(_ name: String) {
        guard Player.shouldBeStoredAsSavedPlayer(name, currentUserName: myName) else { return }
        var roster = appStore.roster
        if !roster.contains(where: { $0.name == name }) {
            let colorIndex = roster.count % Player.avatarColors.count
            roster.insert(Player(name: name, colorIndex: colorIndex), at: 0)
            appStore.saveRoster(roster)
        }
    }
}
