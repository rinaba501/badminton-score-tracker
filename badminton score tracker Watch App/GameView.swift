//
//  GameView.swift
//  badminton score tracker Watch App
//
//  The live scoring screen: tap/crown scoring, serve tracking, haptics,
//  sound, spoken announcements, optional match timer, and the game/match
//  over overlays. All rules live in the pure `BadmintonMatch` value type.
//

import SwiftUI
import WatchKit

// MARK: - Spoken score formatting helpers

private let katakanaNumbers = [
    "ラブ", "ワン", "ツー", "スリー", "フォー",
    "ファイブ", "シックス", "セブン", "エイト", "ナイン",
    "テン", "イレブン", "トゥエルブ", "サーティーン", "フォーティーン",
    "フィフティーン", "シックスティーン", "セブンティーン", "エイティーン", "ナインティーン",
    "トゥエンティ", "トゥエンティワン", "トゥエンティツー", "トゥエンティスリー", "トゥエンティフォー",
    "トゥエンティファイブ", "トゥエンティシックス", "トゥエンティセブン", "トゥエンティエイト", "トゥエンティナイン",
    "サーティ"
]

private func katakana(_ n: Int) -> String {
    guard n >= 0 && n < katakanaNumbers.count else { return "\(n)" }
    return katakanaNumbers[n]
}

private func loveScore(_ n: Int) -> String {
    n == 0 ? "love" : "\(n)"
}

// MARK: - Onboarding

struct OnboardingView: View {
    private struct Hint: Identifiable {
        let id = UUID()
        let icon: String
        let key: String
    }

    private let hints: [Hint] = [
        Hint(icon: "hand.tap",                      key: "onboarding.hint_tap"),
        Hint(icon: "digitalcrown.horizontal.press", key: "onboarding.hint_crown_cw"),
        Hint(icon: "digitalcrown.horizontal.press", key: "onboarding.hint_crown_ccw"),
        Hint(icon: "arrow.uturn.backward",          key: "onboarding.hint_undo"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(hints) { hint in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: hint.icon)
                            .font(.system(size: 16))
                            .foregroundColor(.yellow)
                            .frame(width: 22)
                        Text(LocalizedStringKey(hint.key))
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(LocalizedStringKey("onboarding.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Game

struct GameView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("matchMyName") private var matchMyName = ""
    @AppStorage("matchOpponentName") private var matchOpponentName = ""
    @AppStorage("playerRoster") private var rosterData: Data = Data()
    @AppStorage("matchHistory") private var matchHistoryData: Data = Data()
    @AppStorage("pointsToWin") private var pointsToWin: Int = 21
    @AppStorage("gamesInMatch") private var gamesInMatch: Int = 3
    @AppStorage("courtTheme") private var courtTheme: CourtTheme = .green

    @AppStorage("announceScore") private var announceScore = true
    @AppStorage("enableSounds") private var enableSounds = true
    @AppStorage("enableCrownScoring") private var enableCrownScoring = true
    @AppStorage("timeModeEnabled") private var timeModeEnabled = false
    @AppStorage("timeLimitMinutes") private var timeLimitMinutes = 10
    @StateObject private var soundPlayer = SoundPlayer()
    @StateObject private var workoutManager = WorkoutManager()

    @State private var match = BadmintonMatch()
    @State private var undoStack: [BadmintonMatch] = []
    @State private var savedCurrentMatch = false
    @State private var matchStartDate = Date()
    @State private var crownValue: Double = 0
    @State private var showDiscardAlert = false
    @State private var lastCrownScore: Double = 0
    @StateObject private var announcer = ScoreAnnouncer()
    private let crownThreshold: Double = 1.0

    // Time mode
    @State private var timeRemaining: TimeInterval = 0
    @State private var timeModeWinner: Side? = nil
    @State private var suddenDeath = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var effectiveMyName: String { matchMyName.isEmpty ? myName : matchMyName }
    private var effectiveOpponentName: String { matchOpponentName.isEmpty ? "Guest" : matchOpponentName }

    private func name(for side: Side) -> String {
        side == .me ? effectiveMyName : effectiveOpponentName
    }

    private static let guestNames: Set<String> = ["Guest (Near)", "Guest (Far)"]

    private func saveToRoster(_ name: String) {
        guard !name.isEmpty, !Self.guestNames.contains(name) else { return }
        var roster = PersistenceStore.decodeRoster(rosterData)
        if !roster.contains(where: { $0.name == name }) {
            let colorIndex = roster.count % Player.avatarColors.count
            roster.insert(Player(name: name, colorIndex: colorIndex), at: 0)
            if let encoded = PersistenceStore.encodeRoster(roster) { rosterData = encoded }
        }
    }

    private func avatarColor(for name: String) -> Color {
        PersistenceStore.decodeRoster(rosterData).first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        PersistenceStore.decodeRoster(rosterData).first(where: { $0.name == name })?.iconName
    }

    private func tap(_ side: Side) {
        guard match.gameWinner == nil, match.matchWinner == nil, !timeExpiredWinner else { return }
        undoStack.append(match)

        if timeModeEnabled && suddenDeath {
            // Sudden death: this point ends the current game immediately
            match.score(side)
            if match.gameWinner == nil {
                // Point didn't naturally end the game — force it
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
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                WKInterfaceDevice.current().play(.success)
            }
            if enableSounds { soundPlayer.playMatchWin() }
            announcementDelay = enableSounds ? 0.7 : 0
            saveMatch()
        } else if match.gameWinner != nil {
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WKInterfaceDevice.current().play(.retry)
            }
            if enableSounds { soundPlayer.playGameWin() }
            announcementDelay = enableSounds ? 0.5 : 0
        } else if !wasGamePoint && match.isGamePoint {
            WKInterfaceDevice.current().play(.notification)
            if enableSounds { soundPlayer.playGamePoint() }
            announcementDelay = enableSounds ? 0.25 : 0
        } else {
            WKInterfaceDevice.current().play(.click)
            if enableSounds { soundPlayer.playScore() }
            announcementDelay = enableSounds ? 0.25 : 0
        }
        if announcementDelay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + announcementDelay) { announceCurrentScore() }
        } else {
            announceCurrentScore()
        }
    }

    /// Called after a sudden-death game resolves — checks match state and plays appropriate sounds.
    private func resolveAfterGame() {
        if let winner = match.matchWinner {
            timeModeWinner = winner
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { WKInterfaceDevice.current().play(.success) }
            if enableSounds { soundPlayer.playMatchWin() }
            saveMatch()
        } else if match.isTied {
            // Edge case: equal games, no further games possible
            timeModeWinner = .me  // placeholder — overlay will show "Tie"
            saveMatch()
        } else {
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { WKInterfaceDevice.current().play(.retry) }
            if enableSounds { soundPlayer.playGameWin() }
        }
    }

    // True once time has expired and a winner was determined (blocks further scoring)
    private var timeExpiredWinner: Bool { timeModeWinner != nil }

    private func handleTimeUp() {
        guard timeModeWinner == nil else { return }
        speak(NSLocalizedString("speech.time_up", comment: ""))
        if match.myGamesWon != match.opponentGamesWon {
            let w: Side = match.myGamesWon > match.opponentGamesWon ? .me : .opponent
            timeModeWinner = w
            WKInterfaceDevice.current().play(.success)
            if enableSounds { soundPlayer.playMatchWin() }
            saveMatch()
        } else if match.myScore != match.opponentScore {
            let w: Side = match.myScore > match.opponentScore ? .me : .opponent
            timeModeWinner = w
            WKInterfaceDevice.current().play(.success)
            if enableSounds { soundPlayer.playMatchWin() }
            saveMatch()
        } else {
            suddenDeath = true
            WKInterfaceDevice.current().play(.notification)
        }
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        match = previous
        // Distinct upward pulse so undo feels different from scoring
        WKInterfaceDevice.current().play(.directionUp)
    }

    private func speak(_ text: String) {
        guard announceScore else { return }
        announcer.speak(text)
    }

    private func announceCurrentScore() {
        let serverScore = match.serverIsMe ? match.myScore : match.opponentScore
        let receiverScore = match.serverIsMe ? match.opponentScore : match.myScore
        let tied = serverScore == receiverScore
        let langCode = Locale.current.language.languageCode?.identifier ?? "en"
        let isJapanese = langCode == "ja"
        let isZhHans = langCode == "zh"

        func fmt(_ key: String, _ a: Int, _ b: Int) -> String {
            if isJapanese {
                return String(format: NSLocalizedString(key, comment: ""), katakana(a), katakana(b))
            }
            if isZhHans {
                return String(format: NSLocalizedString(key, comment: ""), a, b)
            }
            return String(format: NSLocalizedString(key, comment: ""), loveScore(a), loveScore(b))
        }

        func fmtTied(_ key: String, _ n: Int) -> String {
            if isJapanese {
                return String(format: NSLocalizedString(key, comment: ""), katakana(n))
            }
            if isZhHans {
                return String(format: NSLocalizedString(key, comment: ""), n)
            }
            // "love all" for 0-0, otherwise "8 all"
            let word = n == 0 ? "love" : "\(n)"
            return String(format: NSLocalizedString(key, comment: ""), word)
        }

        if let winner = match.matchWinner {
            speak(String(format: NSLocalizedString("speech.wins_match", comment: ""), name(for: winner)))
        } else if let winner = match.gameWinner {
            speak(String(format: NSLocalizedString("speech.wins_game", comment: ""), name(for: winner)))
        } else if match.isMatchPoint {
            speak(tied ? fmtTied("speech.tied", serverScore) : fmt("speech.match_point", serverScore, receiverScore))
        } else if match.isGamePoint {
            speak(tied ? fmtTied("speech.tied", serverScore) : fmt("speech.game_point", serverScore, receiverScore))
        } else if tied {
            speak(fmtTied("speech.tied", serverScore))
        } else {
            speak(fmt("speech.score", serverScore, receiverScore))
        }
    }

    private func onCrownChanged(_ newValue: Double) {
        guard enableCrownScoring, match.gameWinner == nil, match.matchWinner == nil else { return }
        let delta = newValue - lastCrownScore
        if delta >= crownThreshold {
            lastCrownScore = newValue
            tap(.me)
        } else if delta <= -crownThreshold {
            lastCrownScore = newValue
            tap(.opponent)
        }
    }

    private func startNextGame() {
        undoStack.removeAll()
        suddenDeath = false
        match.startNextGame()
        WKInterfaceDevice.current().play(.start)
    }

    private func newMatch() {
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

    private func saveMatch() {
        // In time mode the timer may expire mid-game; use timeModeWinner as fallback
        let winner = match.matchWinner ?? timeModeWinner
        guard !savedCurrentMatch, let winner else { return }
        savedCurrentMatch = true
        saveToRoster(effectiveOpponentName)
        saveToRoster(effectiveMyName)
        let currentRoster = PersistenceStore.decodeRoster(rosterData)
        var games = match.completedGames
        // Append in-progress game when time expired mid-game
        if timeModeEnabled && match.matchWinner == nil && (match.myScore > 0 || match.opponentScore > 0) {
            games.append(GameScore(my: match.myScore, opponent: match.opponentScore))
        }
        var history = decodeHistory()
        history.append(MatchRecord(
            games: games,
            myGamesWon: match.myGamesWon,
            opponentGamesWon: match.opponentGamesWon,
            winner: name(for: winner),
            myName: effectiveMyName,
            opponentName: effectiveOpponentName,
            date: Date(),
            duration: Date().timeIntervalSince(matchStartDate),
            myPlayerId: currentRoster.first(where: { $0.name == effectiveMyName })?.id,
            opponentPlayerId: currentRoster.first(where: { $0.name == effectiveOpponentName })?.id
        ))
        if let encoded = PersistenceStore.encodeHistory(history) { matchHistoryData = encoded }
        Task { await workoutManager.endWorkout() }
    }

    private func decodeHistory() -> [MatchRecord] {
        PersistenceStore.decodeHistory(matchHistoryData)
    }

    private var timerLabel: String {
        let m = Int(timeRemaining) / 60
        let s = Int(timeRemaining) % 60
        return String(format: "%d:%02d", m, s)
    }

    // The scene is split into the computed subviews below. Type-checking the
    // whole ZStack as one expression exceeds the Swift compiler's time budget
    // ("unable to type-check this expression in reasonable time").

    @ViewBuilder
    private var timerBadge: some View {
        if timeModeEnabled {
            HStack {
                Image(systemName: "timer")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(timerLabel)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(timeRemaining <= 30 && timeRemaining > 0 ? .red : .white)
                    .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.timer_remaining", comment: ""), timerLabel)))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
        }
    }

    private var scoreboard: some View {
        VStack(spacing: 6) {
            timerBadge
            GamesWonHeader(
                myName: effectiveMyName, opponentName: effectiveOpponentName,
                myGames: match.myGamesWon, opponentGames: match.opponentGamesWon,
                canUndo: !undoStack.isEmpty && match.gameWinner == nil && match.matchWinner == nil && timeModeWinner == nil,
                onUndo: undo
            )

            let serveKnown = match.myScore > 0 || match.opponentScore > 0

            ScoreView(
                name: effectiveOpponentName,
                score: match.opponentScore,
                isServing: serveKnown && match.servingSide == .opponent,
                serveRight: match.serveFromRightCourt,
                isWinner: match.gameWinner == .opponent,
                avatarColor: avatarColor(for: effectiveOpponentName),
                avatarIcon: avatarIcon(for: effectiveOpponentName),
                onTap: { tap(.opponent) }
            )

            ScoreView(
                name: effectiveMyName,
                score: match.myScore,
                isServing: serveKnown && match.servingSide == .me,
                serveRight: match.serveFromRightCourt,
                isWinner: match.gameWinner == .me,
                avatarColor: avatarColor(for: effectiveMyName),
                avatarIcon: avatarIcon(for: effectiveMyName),
                onTap: { tap(.me) }
            )
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var pointBanners: some View {
        if match.matchWinner == nil && timeModeWinner == nil && match.isGamePoint {
            bannerOverlay(match.isMatchPoint ? NSLocalizedString("game.match_point", comment: "") : NSLocalizedString("game.game_point", comment: ""))
                .allowsHitTesting(false)
        }

        if suddenDeath && timeModeWinner == nil {
            bannerOverlay("Sudden Death!")
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var resultOverlay: some View {
        if match.isTied {
            MatchOverOverlay(
                title: "It's a Tie!",
                games: String(format: NSLocalizedString("game.games_score", comment: ""), "\(match.myGamesWon) - \(match.opponentGamesWon)"),
                actionTitle: NSLocalizedString("game.rematch", comment: ""),
                action: newMatch,
                isMatchOver: true,
                completedGames: match.completedGames
            )
        } else if let winner = match.matchWinner ?? timeModeWinner {
            MatchOverOverlay(
                title: String(format: NSLocalizedString("game.wins_match", comment: ""), name(for: winner)),
                games: String(format: NSLocalizedString("game.games_score", comment: ""), "\(match.myGamesWon) - \(match.opponentGamesWon)"),
                actionTitle: NSLocalizedString("game.rematch", comment: ""),
                action: newMatch,
                isMatchOver: true,
                completedGames: match.completedGames
            )
        } else if let gameWinner = match.gameWinner {
            MatchOverOverlay(
                title: String(format: NSLocalizedString("game.wins_game", comment: ""), name(for: gameWinner)),
                games: String(format: NSLocalizedString("game.games_score", comment: ""), "\(match.myGamesWon) - \(match.opponentGamesWon)"),
                actionTitle: NSLocalizedString("game.next_game", comment: ""),
                action: startNextGame
            )
        }
    }

    var body: some View {
        ZStack {
            courtTheme.color
                .ignoresSafeArea()

            scoreboard
            pointBanners
            resultOverlay
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("game.menu") {
                    let matchInProgress = match.matchWinner == nil && timeModeWinner == nil &&
                        (match.myScore > 0 || match.opponentScore > 0 || !match.completedGames.isEmpty)
                    if matchInProgress {
                        showDiscardAlert = true
                    } else {
                        currentView = .menu
                    }
                }
            }
        }
        .alert(NSLocalizedString("game.discard_title", comment: ""), isPresented: $showDiscardAlert) {
            Button(NSLocalizedString("game.discard_confirm", comment: ""), role: .destructive) {
                Task { await workoutManager.endWorkout() }
                currentView = .menu
            }
            Button(NSLocalizedString("game.discard_cancel", comment: ""), role: .cancel) {}
        } message: {
            Text("game.discard_message")
        }
        .focusable()
        .digitalCrownRotation($crownValue, from: -1000, through: 1000, sensitivity: .low, isContinuous: true)
        .onChange(of: crownValue, perform: onCrownChanged)
        .onReceive(ticker) { _ in
            guard timeModeEnabled, timeModeWinner == nil, !suddenDeath,
                  match.matchWinner == nil else { return }
            if timeRemaining > 0 {
                timeRemaining -= 1
            } else {
                handleTimeUp()
            }
        }
        .onAppear {
            if match.completedGames.isEmpty && match.myScore == 0 && match.opponentScore == 0 {
                match = BadmintonMatch(
                    pointsToWin: pointsToWin,
                    pointCap: pointsToWin + 9,
                    gamesToWin: (gamesInMatch / 2) + 1
                )
                if timeModeEnabled { timeRemaining = TimeInterval(timeLimitMinutes * 60) }
                Task { await workoutManager.startWorkout(startDate: matchStartDate) }
            }
            crownValue = 0
            lastCrownScore = 0
        }
    }

    private func bannerOverlay(_ text: String) -> some View {
        VStack {
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.85))
                .cornerRadius(8)
                .transition(.scale.combined(with: .opacity))
            Spacer()
        }
        .padding(.top, 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: text)
    }
}

struct GamesWonHeader: View {
    let myName: String
    let opponentName: String
    let myGames: Int
    let opponentGames: Int
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("game.games")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .accessibilityHidden(true)
            Spacer()
            Text("\(opponentGames) – \(myGames)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.games_won", comment: ""), opponentGames, myGames)))
            if canUndo {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("a11y.undo")
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .padding(.horizontal, 6)
    }
}

struct ScoreView: View {
    let name: String
    let score: Int
    let isServing: Bool
    let serveRight: Bool
    let isWinner: Bool
    let avatarColor: Color
    var avatarIcon: String? = nil
    let onTap: () -> Void

    @State private var scorePulse = false
    @State private var winnerGlow = false

    /// A single spoken description of the tile: player, score, and — while
    /// serving — which service court, so VoiceOver users get the same context
    /// the sighted layout conveys.
    private var accessibilityDescription: String {
        let base = String(format: NSLocalizedString("a11y.score_tile", comment: ""), name, score)
        guard isServing else { return base }
        let court = NSLocalizedString(serveRight ? "game.right_court" : "game.left_court", comment: "")
        return String(format: NSLocalizedString("a11y.score_tile_serving_suffix", comment: ""), base, court)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    AvatarView(name: name, color: isWinner ? .yellow : avatarColor, size: 20, iconName: avatarIcon)
                    if isServing {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundColor(.yellow)
                    }
                    Text(name)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                if isServing {
                    Text(serveRight ? "game.right_court" : "game.left_court")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow.opacity(0.9))
                }
            }
            Spacer()
            Text("\(score)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .scaleEffect(scorePulse ? 1.35 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.4), value: scorePulse)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isWinner
                      ? Color.yellow.opacity(winnerGlow ? 0.35 : 0.15)
                      : Color.black.opacity(0.25))
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: winnerGlow)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isWinner ? Color.yellow : (isServing ? Color.yellow.opacity(0.8) : Color.white.opacity(0.5)),
                        lineWidth: isWinner ? 2.5 : (isServing ? 2 : 1.5))
        )
        .scaleEffect(isWinner ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isWinner)
        .contentShape(Rectangle())
        .onTapGesture {
            scorePulse = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scorePulse = false }
            onTap()
        }
        .onChange(of: isWinner) { won in
            winnerGlow = won
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("a11y.score_hint")
        .accessibilityAddTraits(.isButton)
    }
}

struct MatchOverOverlay: View {
    let title: String
    let games: String
    let actionTitle: String
    let action: () -> Void
    var isMatchOver: Bool = false
    var completedGames: [GameScore] = []

    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 8) {
            if isMatchOver {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.yellow)
                    .scaleEffect(shimmer ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: shimmer)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Games \(games)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
            if isMatchOver && !completedGames.isEmpty {
                Text(completedGames.map { "\($0.my)-\($0.opponent)" }.joined(separator: "  "))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.black.opacity(0.85))
        .cornerRadius(14)
        .padding(.horizontal, 8)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.7).combined(with: .opacity),
            removal: .opacity
        ))
        .onAppear { shimmer = true }
    }
}
