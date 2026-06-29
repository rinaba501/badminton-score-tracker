//
//  ContentView.swift
//  badminton score tracker watch Watch App
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//

import SwiftUI
import WatchKit
import AVFoundation

// MARK: - Player Model

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorIndex: Int
    var iconName: String?

    init(id: UUID = UUID(), name: String, colorIndex: Int = 0, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.iconName = iconName
    }

    static let avatarColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .red,
        .cyan, .mint, .teal, .indigo, .yellow, .brown
    ]

    static let avatarImageNames: [String] = [
        "avatar_shuttlecock_happy", "avatar_shuttlecock_cute",
        "avatar_shuttlecock_angry",
        "avatar_blonde_girl", "avatar_purple_girl",
        "avatar_messy_bun", "avatar_blue_cap",
        "avatar_cap_shuttlecock", "avatar_headdress",
        "avatar_racket_happy", "avatar_racket_cool",
        "avatar_racket_mustache", "avatar_net",
        "avatar_red_cap", "avatar_viking"
    ]

    static let sportIcons: [String] = [
        "star.fill", "bolt.fill", "flame.fill", "crown.fill",
        "heart.fill", "moon.fill", "sun.max.fill", "snowflake",
        "pawprint.fill", "leaf.fill", "figure.run", "sportscourt.fill"
    ]

    var avatarColor: Color { Self.avatarColors[colorIndex % Self.avatarColors.count] }

    var initials: String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first(where: { $0.isLetter }).map(String.init) }.joined().uppercased()
    }
}

struct AvatarView: View {
    let name: String
    let color: Color
    var size: CGFloat = 28
    var iconName: String? = nil

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let result = words.compactMap { $0.first(where: { $0.isLetter }).map(String.init) }.joined().uppercased()
        return result.isEmpty ? "?" : result
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
            if let icon = iconName {
                if Player.avatarImageNames.contains(icon) {
                    Image(icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.48, weight: .medium))
                        .foregroundColor(.white)
                }
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
    }
}

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

final class ScoreAnnouncer: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.volume = 1.0
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        utterance.voice = AVSpeechSynthesisVoice(language: lang) ?? AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }
}

final class SoundPlayer: ObservableObject {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let sampleRate: Double = 44100
    private lazy var format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

    init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        try? engine.start()
    }

    private func tone(frequency: Float, duration: Float, amplitude: Float = 0.45) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(Float(sampleRate) * duration)
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buf.frameLength = frames
        let data = buf.floatChannelData![0]
        let sr = Float(sampleRate)
        let decaySamples = sr * duration * 0.4
        for i in 0..<Int(frames) {
            let env = exp(-Float(i) / decaySamples)
            data[i] = amplitude * env * sin(2 * .pi * frequency * Float(i) / sr)
        }
        return buf
    }

    private func schedule(_ buf: AVAudioPCMBuffer, after delay: Double = 0) {
        let block = {
            if !self.engine.isRunning { try? self.engine.start() }
            self.node.scheduleBuffer(buf)
            if !self.node.isPlaying { self.node.play() }
        }
        if delay == 0 { block() } else { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: block) }
    }

    func playScore()     { schedule(tone(frequency: 880, duration: 0.18)) }
    func playGamePoint() { schedule(tone(frequency: 740, duration: 0.18)) }

    func playGameWin() {
        schedule(tone(frequency: 523, duration: 0.2))
        schedule(tone(frequency: 659, duration: 0.25), after: 0.18)
    }

    func playMatchWin() {
        schedule(tone(frequency: 523, duration: 0.15))
        schedule(tone(frequency: 659, duration: 0.15), after: 0.15)
        schedule(tone(frequency: 784, duration: 0.35, amplitude: 0.6), after: 0.3)
    }
}

struct ContentView: View {
    @State private var currentView: AppView = .menu

    enum AppView {
        case menu, preMatch, game, settings, history, stats
    }

    var body: some View {
        NavigationView {
            switch currentView {
            case .menu:
                MenuView(currentView: $currentView)
            case .preMatch:
                PreMatchView(currentView: $currentView)
            case .game:
                GameView(currentView: $currentView)
            case .settings:
                SettingsView(currentView: $currentView)
            case .history:
                HistoryView(currentView: $currentView)
            case .stats:
                StatsView(currentView: $currentView)
            }
        }
    }
}

struct MenuView: View {
    @Binding var currentView: ContentView.AppView

    var body: some View {
        List {
            Button(action: { currentView = .preMatch }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("menu.new_match")
                }
            }

            Button(action: { currentView = .history }) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("menu.history")
                }
            }

            Button(action: { currentView = .stats }) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                    Text("menu.stats")
                }
            }

            Button(action: { currentView = .settings }) {
                HStack {
                    Image(systemName: "gear")
                    Text("menu.settings")
                }
            }
        }
        .navigationTitle("menu.title")
    }
}

// MARK: - Pre-Match

struct PreMatchView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("iServeFirst") private var iServeFirst = true
    @AppStorage("matchMyName") private var matchMyName = ""
    @AppStorage("matchOpponentName") private var matchOpponentName = ""
    @AppStorage("playerRoster") private var rosterData: Data = Data()

    @State private var step: Step = .pickMyPlayer
    @State private var showAddPlayer = false
    @State private var newPlayerName = ""
    @State private var addingForSide: Side = .me

    enum Step { case pickMyPlayer, pickOpponent, serveFirst }
    enum Side { case me, opponent }

    private var roster: [Player] {
        (try? JSONDecoder().decode([Player].self, from: rosterData)) ?? []
    }

    private static let guestNames: Set<String> = ["Guest (Near)", "Guest (Far)"]

    private func saveToRoster(name: String) {
        guard !name.isEmpty, !Self.guestNames.contains(name) else { return }
        var r = roster
        if !r.contains(where: { $0.name == name }) {
            let colorIndex = r.count % Player.avatarColors.count
            r.insert(Player(name: name, colorIndex: colorIndex), at: 0)
            if let encoded = try? JSONEncoder().encode(r) { rosterData = encoded }
        }
    }

    private func avatarColor(for name: String) -> Color {
        roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        roster.first(where: { $0.name == name })?.iconName
    }

    private func playerPicker(title: String, defaultLabel: String, defaultColor: Color, guestLabel: String, excluding: String? = nil, onSelect: @escaping (String) -> Void) -> some View {
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
                Section(header: Text("Saved")) {
                    ForEach(filteredRoster) { player in
                        Button(action: { onSelect(player.name) }) {
                            HStack {
                                AvatarView(name: player.name, color: player.avatarColor, size: 24, iconName: player.iconName)
                                Text(player.name)
                            }
                        }
                    }
                }
            }
            Section {
                Button(action: { showAddPlayer = true }) {
                    Label("Add New", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPlayer) {
            VStack(spacing: 12) {
                Text("New Player")
                    .font(.headline)
                TextField("Name", text: $newPlayerName)
                Button("Add") {
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
            playerPicker(title: "Near Side", defaultLabel: myName, defaultColor: avatarColor(for: myName), guestLabel: "Guest (Near)") { name in
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
            playerPicker(title: "Far Side", defaultLabel: "", defaultColor: .gray, guestLabel: "Guest (Far)", excluding: matchMyName.isEmpty ? myName : matchMyName) { name in
                matchOpponentName = name
                step = .serveFirst
            }
            .navigationTitle("prematch.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { step = .pickMyPlayer }
                }
            }

        case .serveFirst:
            VStack(spacing: 12) {
                Text("prematch.who_serves")
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Button(action: {
                    iServeFirst = true
                    currentView = .game
                }) {
                    Text(matchMyName.isEmpty ? myName : matchMyName)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)

                Button(action: {
                    iServeFirst = false
                    currentView = .game
                }) {
                    Text(matchOpponentName.isEmpty ? "Opponent" : matchOpponentName)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.gray.opacity(0.4))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .navigationTitle("prematch.title")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("prematch.back") { step = .pickOpponent }
                }
            }
        }
    }
}

// MARK: - Court Theme

enum CourtTheme: String, Codable, CaseIterable {
    case green  = "Green"
    case blue   = "Blue"
    case red    = "Red"
    case purple = "Purple"
    case black  = "Black"

    var color: Color {
        switch self {
        case .green:  return Color(red: 0.2, green: 0.6, blue: 0.2)
        case .blue:   return Color(red: 0.1, green: 0.4, blue: 0.8)
        case .red:    return Color(red: 0.75, green: 0.15, blue: 0.15)
        case .purple: return Color(red: 0.45, green: 0.2, blue: 0.7)
        case .black:  return Color(red: 0.1, green: 0.1, blue: 0.1)
        }
    }
}

// MARK: - Game

struct GameView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("matchMyName") private var matchMyName = ""
    @AppStorage("matchOpponentName") private var matchOpponentName = ""
    @AppStorage("playerRoster") private var rosterData: Data = Data()
    @AppStorage("iServeFirst") private var iServeFirst = true
    @AppStorage("matchHistory") private var matchHistoryData: Data = Data()
    @AppStorage("pointsToWin") private var pointsToWin: Int = 21
    @AppStorage("gamesInMatch") private var gamesInMatch: Int = 3
    @AppStorage("courtTheme") private var courtTheme: CourtTheme = .green

    @AppStorage("announceScore") private var announceScore = true
    @AppStorage("enableSounds") private var enableSounds = true
    @StateObject private var soundPlayer = SoundPlayer()

    @State private var match = BadmintonMatch()
    @State private var undoStack: [BadmintonMatch] = []
    @State private var savedCurrentMatch = false
    @State private var matchStartDate = Date()
    @State private var crownValue: Double = 0
    @State private var lastCrownScore: Double = 0
    @StateObject private var announcer = ScoreAnnouncer()
    private let crownThreshold: Double = 1.0

    private var effectiveMyName: String { matchMyName.isEmpty ? myName : matchMyName }
    private var effectiveOpponentName: String { matchOpponentName.isEmpty ? "Guest" : matchOpponentName }

    private func name(for side: Side) -> String {
        side == .me ? effectiveMyName : effectiveOpponentName
    }

    private static let guestNames: Set<String> = ["Guest (Near)", "Guest (Far)"]

    private func saveToRoster(_ name: String) {
        guard !name.isEmpty, !Self.guestNames.contains(name) else { return }
        var roster = (try? JSONDecoder().decode([Player].self, from: rosterData)) ?? []
        if !roster.contains(where: { $0.name == name }) {
            let colorIndex = roster.count % Player.avatarColors.count
            roster.insert(Player(name: name, colorIndex: colorIndex), at: 0)
            if let encoded = try? JSONEncoder().encode(roster) { rosterData = encoded }
        }
    }

    private func avatarColor(for name: String) -> Color {
        let roster = (try? JSONDecoder().decode([Player].self, from: rosterData)) ?? []
        return roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        let roster = (try? JSONDecoder().decode([Player].self, from: rosterData)) ?? []
        return roster.first(where: { $0.name == name })?.iconName
    }

    private func tap(_ side: Side) {
        guard match.gameWinner == nil, match.matchWinner == nil else { return }
        undoStack.append(match)
        let wasGamePoint = match.isGamePoint
        match.score(side)

        if match.matchWinner != nil {
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                WKInterfaceDevice.current().play(.success)
            }
            if enableSounds { soundPlayer.playMatchWin() }
            saveMatch()
        } else if match.gameWinner != nil {
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WKInterfaceDevice.current().play(.retry)
            }
            if enableSounds { soundPlayer.playGameWin() }
        } else if !wasGamePoint && match.isGamePoint {
            WKInterfaceDevice.current().play(.notification)
            if enableSounds { soundPlayer.playGamePoint() }
        } else {
            WKInterfaceDevice.current().play(.click)
            if enableSounds { soundPlayer.playScore() }
        }
        announceCurrentScore()
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
        guard match.gameWinner == nil, match.matchWinner == nil else { return }
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
        match.startNextGame()
        WKInterfaceDevice.current().play(.start)
    }

    private func newMatch() {
        match = BadmintonMatch(
            serverIsMe: iServeFirst,
            pointsToWin: pointsToWin,
            pointCap: pointsToWin + 9,
            gamesToWin: (gamesInMatch / 2) + 1
        )
        undoStack.removeAll()
        savedCurrentMatch = false
    }

    private func saveMatch() {
        guard !savedCurrentMatch, let winner = match.matchWinner else { return }
        savedCurrentMatch = true
        saveToRoster(effectiveOpponentName)
        saveToRoster(effectiveMyName)
        let currentRoster = (try? JSONDecoder().decode([Player].self, from: rosterData)) ?? []
        var history = decodeHistory()
        history.append(MatchRecord(
            games: match.completedGames,
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
        if let encoded = try? JSONEncoder().encode(history) {
            matchHistoryData = encoded
        }
    }

    private func decodeHistory() -> [MatchRecord] {
        (try? JSONDecoder().decode([MatchRecord].self, from: matchHistoryData)) ?? []
    }

    var body: some View {
        ZStack {
            courtTheme.color
                .ignoresSafeArea()

            VStack(spacing: 6) {
                GamesWonHeader(
                    myName: effectiveMyName, opponentName: effectiveOpponentName,
                    myGames: match.myGamesWon, opponentGames: match.opponentGamesWon,
                    canUndo: !undoStack.isEmpty && match.gameWinner == nil && match.matchWinner == nil,
                    onUndo: undo
                )

                ScoreView(
                    name: effectiveOpponentName,
                    score: match.opponentScore,
                    isServing: match.servingSide == .opponent,
                    serveRight: match.serveFromRightCourt,
                    isWinner: match.gameWinner == .opponent,
                    avatarColor: avatarColor(for: effectiveOpponentName),
                    avatarIcon: avatarIcon(for: effectiveOpponentName),
                    onTap: { tap(.opponent) }
                )

                ScoreView(
                    name: effectiveMyName,
                    score: match.myScore,
                    isServing: match.servingSide == .me,
                    serveRight: match.serveFromRightCourt,
                    isWinner: match.gameWinner == .me,
                    avatarColor: avatarColor(for: effectiveMyName),
                    avatarIcon: avatarIcon(for: effectiveMyName),
                    onTap: { tap(.me) }
                )

            }
            .padding(.horizontal, 10)

            if match.matchWinner == nil && match.isGamePoint {
                bannerOverlay(match.isMatchPoint ? NSLocalizedString("game.match_point", comment: "") : NSLocalizedString("game.game_point", comment: ""))
                    .allowsHitTesting(false)
            }

            if let winner = match.matchWinner {
                MatchOverOverlay(
                    title: String(format: NSLocalizedString("game.wins_match", comment: ""), name(for: winner)),
                    games: String(format: NSLocalizedString("game.games_score", comment: ""), "\(match.myGamesWon) - \(match.opponentGamesWon)"),
                    actionTitle: NSLocalizedString("game.new_match", comment: ""),
                    action: newMatch,
                    isMatchOver: true
                )
            } else if match.gameWinner != nil {
                MatchOverOverlay(
                    title: String(format: NSLocalizedString("game.wins_game", comment: ""), ""),
                    games: String(format: NSLocalizedString("game.games_score", comment: ""), "\(match.myGamesWon) - \(match.opponentGamesWon)"),
                    actionTitle: NSLocalizedString("game.next_game", comment: ""),
                    action: startNextGame
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("game.menu") { currentView = .menu }
            }
        }
        .focusable()
        .digitalCrownRotation($crownValue, from: -1000, through: 1000, sensitivity: .low, isContinuous: true)
        .onChange(of: crownValue, perform: onCrownChanged)
        .onAppear {
            if match.completedGames.isEmpty && match.myScore == 0 && match.opponentScore == 0 {
                match = BadmintonMatch(
                    serverIsMe: iServeFirst,
                    pointsToWin: pointsToWin,
                    pointCap: pointsToWin + 9,
                    gamesToWin: (gamesInMatch / 2) + 1
                )
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
            Spacer()
            Text("\(opponentGames) – \(myGames)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            if canUndo {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
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
    }
}

struct MatchOverOverlay: View {
    let title: String
    let games: String
    let actionTitle: String
    let action: () -> Void
    var isMatchOver: Bool = false

    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 8) {
            if isMatchOver {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.yellow)
                    .scaleEffect(shimmer ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: shimmer)
            }
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Games \(games)")
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
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

// MARK: - Settings

struct SettingsView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("gameMode") private var gameMode: GameMode = .singles
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("pointsToWin") private var pointsToWin: Int = 21
    @AppStorage("gamesInMatch") private var gamesInMatch: Int = 3
    @AppStorage("courtTheme") private var courtTheme: CourtTheme = .green
    @AppStorage("announceScore") private var announceScore = true
    @AppStorage("enableSounds") private var enableSounds = true
    @AppStorage("playerRoster") private var rosterData: Data = Data()

    @State private var editingPlayer: Player? = nil
    @State private var showDuplicatePlayerNameAlert = false
    @AppStorage("matchHistory") private var matchHistoryData: Data = Data()

    enum GameMode: String, Codable, CaseIterable {
        case singles = "Singles"
        case doubles = "Doubles"
    }

    private var roster: [Player] {
        (try? JSONDecoder().decode([Player].self, from: rosterData)) ?? []
    }

    private var opponents: [Player] { roster.filter { $0.name != myName } }

    private func deletePlayers(at offsets: IndexSet) {
        let toDelete = Set(offsets.map { opponents[$0].id })
        var r = roster.filter { !toDelete.contains($0.id) }
        if let encoded = try? JSONEncoder().encode(r) { rosterData = encoded }
    }

    private func savePlayerEdit(_ updated: Player) {
        let old = roster.first(where: { $0.id == updated.id })

        // Reject duplicate names (excluding the player being edited)
        if let old, old.name != updated.name,
           roster.contains(where: { $0.id != updated.id && $0.name == updated.name }) {
            showDuplicatePlayerNameAlert = true
            return
        }

        var r = roster
        if let idx = r.firstIndex(where: { $0.id == updated.id }) {
            r[idx] = updated
        } else {
            r.insert(updated, at: 0)
        }
        if let encoded = try? JSONEncoder().encode(r) { rosterData = encoded }

        // Propagate name change to match history via player ID
        if let old, old.name != updated.name {
            var history = (try? JSONDecoder().decode([MatchRecord].self, from: matchHistoryData)) ?? []
            for i in history.indices {
                if history[i].myPlayerId == updated.id {
                    if history[i].winner == history[i].myName { history[i].winner = updated.name }
                    history[i].myName = updated.name
                }
                if history[i].opponentPlayerId == updated.id {
                    if history[i].winner == history[i].opponentName { history[i].winner = updated.name }
                    history[i].opponentName = updated.name
                }
            }
            if let encoded = try? JSONEncoder().encode(history) { matchHistoryData = encoded }

            // Also update myName AppStorage if this is the "me" player
            if old.name == myName { myName = updated.name }
        }

        editingPlayer = nil
    }

    private func meAsPlayer() -> Player {
        roster.first(where: { $0.name == myName }) ?? Player(name: myName, colorIndex: 0)
    }

    var body: some View {
        List {
            Section(header: Text("settings.game_mode")) {
                Picker("settings.mode", selection: $gameMode) {
                    Text("settings.singles").tag(GameMode.singles)
                    Text("settings.doubles").tag(GameMode.doubles)
                }
            }

            Section(header: Text("Me")) {
                Button(action: { editingPlayer = meAsPlayer() }) {
                    HStack(spacing: 8) {
                        let me = meAsPlayer()
                        AvatarView(name: me.name, color: me.avatarColor, size: 28, iconName: me.iconName)
                        Text(myName)
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section(header: Text("Players")) {
                if roster.isEmpty {
                    Text("No saved players yet")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(opponents) { player in
                        Button(action: { editingPlayer = player }) {
                            HStack(spacing: 8) {
                                AvatarView(name: player.name, color: player.avatarColor, size: 24, iconName: player.iconName)
                                Text(player.name)
                                    .font(.caption)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete(perform: deletePlayers)
                }
            }

            Section(header: Text("settings.crown")) {
                Toggle("settings.sound_effects", isOn: $enableSounds)
                Toggle("settings.announce_score", isOn: $announceScore)
            }

            Section(header: Text("settings.court_theme")) {
                Picker("settings.theme", selection: $courtTheme) {
                    ForEach(CourtTheme.allCases, id: \.self) { theme in
                        HStack {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 12, height: 12)
                            Text(LocalizedStringKey("theme.\(theme.rawValue.lowercased())"))
                        }
                        .tag(theme)
                    }
                }
            }

            Section(header: Text("settings.match_format")) {
                Picker("settings.points_to_win", selection: $pointsToWin) {
                    Text("settings.pts_11").tag(11)
                    Text("settings.pts_15").tag(15)
                    Text("settings.pts_21").tag(21)
                }
                Picker("settings.games_in_match", selection: $gamesInMatch) {
                    Text("settings.games_1").tag(1)
                    Text("settings.games_3").tag(3)
                    Text("settings.games_5").tag(5)
                }
            }
        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("settings.back") { currentView = .menu }
            }
        }
        .sheet(item: $editingPlayer) { player in
            PlayerEditView(initialPlayer: player, onSave: savePlayerEdit)
        }
        .alert("Name already taken", isPresented: $showDuplicatePlayerNameAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A player with that name already exists.")
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("matchHistory") private var matchHistoryData: Data = Data()
    @State private var showingClearConfirmation = false

    private var history: [MatchRecord] {
        (try? JSONDecoder().decode([MatchRecord].self, from: matchHistoryData)) ?? []
    }

    private func save(_ records: [MatchRecord]) {
        if let encoded = try? JSONEncoder().encode(records) {
            matchHistoryData = encoded
        }
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
                    ForEach(history.reversed()) { record in
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
        .alert(Text("history.clear_title"), isPresented: $showingClearConfirmation) {
            Button("history.cancel", role: .cancel) { }
            Button("history.clear", role: .destructive) { matchHistoryData = Data() }
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

    private func durationString(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Head-to-head score line
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.myName.isEmpty ? "Me" : record.myName)
                        .font(.system(size: 12, weight: iWon ? .bold : .regular))
                        .lineLimit(1)
                    Text(record.opponentName.isEmpty ? "Opponent" : record.opponentName)
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
                    Text(durationString(record.duration))
                }
            }
            .font(.caption2)
            .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Stats

struct StatsView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("matchHistory") private var matchHistoryData: Data = Data()

    private var history: [MatchRecord] {
        (try? JSONDecoder().decode([MatchRecord].self, from: matchHistoryData)) ?? []
    }

    private var totalMatches: Int { history.count }
    private var wins: Int { history.filter { $0.winner == myName }.count }
    private var losses: Int { totalMatches - wins }

    private var winRate: Double {
        totalMatches == 0 ? 0 : Double(wins) / Double(totalMatches) * 100
    }

    private var avgPointsScored: Double {
        guard !history.isEmpty else { return 0 }
        let total = history.flatMap { $0.games }.map { $0.my }.reduce(0, +)
        let games = history.flatMap { $0.games }.count
        return games == 0 ? 0 : Double(total) / Double(games)
    }

    private var avgMatchDuration: TimeInterval {
        let timed = history.filter { $0.duration > 0 }
        guard !timed.isEmpty else { return 0 }
        return timed.map { $0.duration }.reduce(0, +) / Double(timed.count)
    }

    private func durationString(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    private var longestStreak: Int {
        var best = 0
        var current = 0
        for record in history {
            if record.winner == myName {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    var body: some View {
        List {
            if history.isEmpty {
                Section {
                    Text("No matches yet")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            } else {
                Section(header: Text(myName)) {
                    StatRow(label: "Matches", value: "\(totalMatches)")
                    StatRow(label: "Wins", value: "\(wins)")
                    StatRow(label: "Losses", value: "\(losses)")
                    StatRow(label: "Win rate", value: String(format: "%.0f%%", winRate))
                    StatRow(label: "Avg pts/game", value: String(format: "%.1f", avgPointsScored))
                    StatRow(label: "Best streak", value: "\(longestStreak)")
                    if avgMatchDuration > 0 {
                        StatRow(label: "Avg duration", value: durationString(avgMatchDuration))
                    }
                }
            }
        }
        .navigationTitle("Stats")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { currentView = .menu }
            }
        }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Player Edit

struct PlayerEditView: View {
    let initialPlayer: Player
    let onSave: (Player) -> Void

    @State private var localPlayer: Player

    init(initialPlayer: Player, onSave: @escaping (Player) -> Void) {
        self.initialPlayer = initialPlayer
        self.onSave = onSave
        _localPlayer = State(initialValue: initialPlayer)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    AvatarView(
                        name: localPlayer.name,
                        color: localPlayer.avatarColor,
                        size: 48,
                        iconName: localPlayer.iconName
                    )
                    Spacer()
                }
                .padding(.top, 4)

                Text("Name")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("Name", text: $localPlayer.name)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(8)

                Text("Color")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(Player.avatarColors.enumerated()), id: \.offset) { i, color in
                        Circle()
                            .fill(color)
                            .frame(height: 28)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: localPlayer.colorIndex == i ? 2.5 : 0)
                            )
                            .onTapGesture { localPlayer.colorIndex = i }
                    }
                }

                Text("Avatar")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(localPlayer.iconName == nil
                                  ? Color.blue.opacity(0.5)
                                  : Color.secondary.opacity(0.25))
                        Text("A")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(height: 36)
                    .onTapGesture { localPlayer.iconName = nil }

                    ForEach(Player.avatarImageNames, id: \.self) { imageName in
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(localPlayer.iconName == imageName
                                      ? Color.blue.opacity(0.5)
                                      : Color.secondary.opacity(0.25))
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .padding(3)
                        }
                        .frame(height: 36)
                        .onTapGesture { localPlayer.iconName = imageName }
                    }
                }

                Text("Icons")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Player.sportIcons, id: \.self) { icon in
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(localPlayer.iconName == icon
                                      ? Color.blue.opacity(0.5)
                                      : Color.secondary.opacity(0.25))
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        .frame(height: 36)
                        .onTapGesture { localPlayer.iconName = icon }
                    }
                }

                Button("Save") {
                    onSave(localPlayer)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle(localPlayer.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    ContentView()
}
