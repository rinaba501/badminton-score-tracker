//
//  ContentView.swift
//  badminton score tracker watch Watch App
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//

import SwiftUI
import WatchKit
import AVFoundation

struct ContentView: View {
    @State private var currentView: AppView = .menu

    enum AppView {
        case menu, preMatch, game, settings, history
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
                    Text("New Match")
                }
            }

            Button(action: { currentView = .history }) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Match History")
                }
            }

            Button(action: { currentView = .settings }) {
                HStack {
                    Image(systemName: "gear")
                    Text("Settings")
                }
            }
        }
        .navigationTitle("Badminton Score")
    }
}

// MARK: - Pre-Match

struct PreMatchView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("opponentName") private var opponentName = "Opponent"
    @AppStorage("iServeFirst") private var iServeFirst = true

    var body: some View {
        VStack(spacing: 12) {
            Text("Who serves first?")
                .font(.headline)
                .multilineTextAlignment(.center)

            Button(action: {
                iServeFirst = true
                currentView = .game
            }) {
                Text(myName)
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
                Text(opponentName)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.gray.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .navigationTitle("New Match")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { currentView = .menu }
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
    @AppStorage("opponentName") private var opponentName = "Opponent"
    @AppStorage("iServeFirst") private var iServeFirst = true
    @AppStorage("matchHistory") private var matchHistoryData: Data = Data()
    @AppStorage("pointsToWin") private var pointsToWin: Int = 21
    @AppStorage("gamesInMatch") private var gamesInMatch: Int = 3
    @AppStorage("courtTheme") private var courtTheme: CourtTheme = .green

    @AppStorage("announceScore") private var announceScore = true

    @State private var match = BadmintonMatch()
    @State private var undoStack: [BadmintonMatch] = []
    @State private var savedCurrentMatch = false
    @State private var crownValue: Double = 0
    @State private var lastCrownScore: Double = 0
    private let synthesizer = AVSpeechSynthesizer()
    private let crownThreshold: Double = 1.0

    private func name(for side: Side) -> String {
        side == .me ? myName : opponentName
    }

    private func tap(_ side: Side) {
        guard match.gameWinner == nil, match.matchWinner == nil else { return }
        undoStack.append(match)
        let wasGamePoint = match.isGamePoint
        match.score(side)

        if match.matchWinner != nil {
            // Match won — two strong pulses
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                WKInterfaceDevice.current().play(.success)
            }
            saveMatch()
        } else if match.gameWinner != nil {
            // Game won — strong pulse followed by a softer one
            WKInterfaceDevice.current().play(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                WKInterfaceDevice.current().play(.retry)
            }
        } else if !wasGamePoint && match.isGamePoint {
            // Just reached game/match point — alert pulse
            WKInterfaceDevice.current().play(.notification)
        } else {
            // Regular point
            WKInterfaceDevice.current().play(.click)
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
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }

    private func announceCurrentScore() {
        if let winner = match.matchWinner {
            speak("\(name(for: winner)) wins the match!")
        } else if let winner = match.gameWinner {
            speak("\(name(for: winner)) wins the game!")
        } else if match.isMatchPoint {
            speak("Match point. \(match.myScore) - \(match.opponentScore)")
        } else if match.isGamePoint {
            speak("Game point. \(match.myScore) - \(match.opponentScore)")
        } else {
            speak("\(match.myScore) - \(match.opponentScore)")
        }
    }

    private func onCrownChanged(_ newValue: Double) {
        guard match.gameWinner == nil, match.matchWinner == nil else { return }
        let delta = newValue - lastCrownScore
        if delta >= crownThreshold {
            lastCrownScore = newValue
            tap(.me)
            announceCurrentScore()
        } else if delta <= -crownThreshold {
            lastCrownScore = newValue
            tap(.opponent)
            announceCurrentScore()
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
        var history = decodeHistory()
        history.append(MatchRecord(
            games: match.completedGames,
            myGamesWon: match.myGamesWon,
            opponentGamesWon: match.opponentGamesWon,
            winner: name(for: winner),
            date: Date()
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
                    myName: myName, opponentName: opponentName,
                    myGames: match.myGamesWon, opponentGames: match.opponentGamesWon
                )

                ScoreView(
                    name: opponentName,
                    score: match.opponentScore,
                    isServing: match.servingSide == .opponent,
                    serveRight: match.serveFromRightCourt,
                    isWinner: match.gameWinner == .opponent,
                    onTap: { tap(.opponent) }
                )

                ScoreView(
                    name: myName,
                    score: match.myScore,
                    isServing: match.servingSide == .me,
                    serveRight: match.serveFromRightCourt,
                    isWinner: match.gameWinner == .me,
                    onTap: { tap(.me) }
                )
            }
            .padding(.horizontal, 10)

            if match.matchWinner == nil && match.isGamePoint {
                bannerOverlay(match.isMatchPoint ? "Match Point!" : "Game Point!")
                    .allowsHitTesting(false)
            }

            if let winner = match.matchWinner {
                MatchOverOverlay(
                    title: "\(name(for: winner)) wins the match!",
                    games: "\(match.myGamesWon) - \(match.opponentGamesWon)",
                    actionTitle: "New Match",
                    action: newMatch
                )
            } else if match.gameWinner != nil {
                MatchOverOverlay(
                    title: "Game!",
                    games: "\(match.myGamesWon) - \(match.opponentGamesWon)",
                    actionTitle: "Next Game",
                    action: startNextGame
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Menu") { currentView = .menu }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: undo) {
                    Image(systemName: "arrow.uturn.backward")
                }
                .disabled(undoStack.isEmpty)
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

    var body: some View {
        HStack(spacing: 4) {
            Text("Games")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Text("\(opponentGames) – \(myGames)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
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
    let onTap: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
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
                    Text(serveRight ? "Right court" : "Left court")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow.opacity(0.9))
                }
            }
            Spacer()
            Text("\(score)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isServing ? Color.yellow.opacity(0.8) : Color.white.opacity(0.5),
                        lineWidth: isServing ? 2 : 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .scaleEffect(isWinner ? 1.06 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isWinner)
    }
}

struct MatchOverOverlay: View {
    let title: String
    let games: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
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
        .background(Color.black.opacity(0.8))
        .cornerRadius(14)
        .padding(.horizontal, 8)
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("gameMode") private var gameMode: GameMode = .singles
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("opponentName") private var opponentName = "Opponent"
    @AppStorage("pointsToWin") private var pointsToWin: Int = 21
    @AppStorage("gamesInMatch") private var gamesInMatch: Int = 3
    @AppStorage("courtTheme") private var courtTheme: CourtTheme = .green
    @AppStorage("announceScore") private var announceScore = true

    enum GameMode: String, Codable, CaseIterable {
        case singles = "Singles"
        case doubles = "Doubles"
    }

    var body: some View {
        List {
            Section(header: Text("Game Mode")) {
                Picker("Mode", selection: $gameMode) {
                    ForEach(GameMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
            }

            Section(header: Text("Player Names")) {
                TextField("Your Name", text: $myName)
                TextField("Opponent Name", text: $opponentName)
            }

            Section(header: Text("Digital Crown")) {
                Toggle("Announce score", isOn: $announceScore)
            }

            Section(header: Text("Court Theme")) {
                Picker("Theme", selection: $courtTheme) {
                    ForEach(CourtTheme.allCases, id: \.self) { theme in
                        HStack {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 12, height: 12)
                            Text(theme.rawValue)
                        }
                        .tag(theme)
                    }
                }
            }

            Section(header: Text("Match Format")) {
                Picker("Points to win", selection: $pointsToWin) {
                    Text("11 pts").tag(11)
                    Text("15 pts").tag(15)
                    Text("21 pts").tag(21)
                }
                Picker("Games in match", selection: $gamesInMatch) {
                    Text("1 game").tag(1)
                    Text("Best of 3").tag(3)
                    Text("Best of 5").tag(5)
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { currentView = .menu }
            }
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
                    Text("No matches played yet")
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
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle("Match History")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { currentView = .menu }
            }
            if !history.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingClearConfirmation = true }) {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                }
            }
        }
        .alert("Clear History", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) { matchHistoryData = Data() }
        } message: {
            Text("Are you sure you want to clear all match history? This cannot be undone.")
        }
    }
}

struct MatchHistoryRow: View {
    let record: MatchRecord

    private var gameLine: String {
        record.games.map { "\($0.my)-\($0.opponent)" }.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(record.winner) won")
                .font(.headline)
            Text("Games \(record.myGamesWon) - \(record.opponentGamesWon)")
                .font(.subheadline)
            if !gameLine.isEmpty {
                Text(gameLine)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(record.date, format: .dateTime.month().day().hour().minute())
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
