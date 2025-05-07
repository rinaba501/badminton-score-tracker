//
//  ContentView.swift
//  badminton score tracker watch Watch App
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//

import SwiftUI
import WatchKit

struct Game: Identifiable, Codable {
    let id = UUID()
    let myScore: Int
    let opponentScore: Int
    let winner: String
    let date: Date
}

struct ContentView: View {
    @State private var currentView: AppView = .menu

    enum AppView {
        case menu, game, settings, history
    }

    var body: some View {
        NavigationView {
            switch currentView {
            case .menu:
                MenuView(currentView: $currentView)
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
            Button(action: { currentView = .game }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("New Game")
                }
            }

            Button(action: { currentView = .history }) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("Game History")
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

struct GameView: View {
    @Binding var currentView: ContentView.AppView
    @State private var myScore = 0
    @State private var opponentScore = 0
    @State private var isAnimating = false
    @State private var winner: String? = nil
    @AppStorage("gameMode") private var gameMode: GameMode = .singles
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("opponentName") private var opponentName = "Opponent"
    @AppStorage("gameHistory") private var gameHistoryData: Data = Data()

    enum GameMode: String, Codable {
        case singles = "Singles"
        case doubles = "Doubles"
    }

    var isMatchPoint: Bool {
        if myScore >= 20 || opponentScore >= 20 {
            if (myScore == 20 && opponentScore <= 19) || (opponentScore == 20 && myScore <= 19) {
                return true
            }
            else if (myScore >= 21 && myScore - opponentScore == 1) || (opponentScore >= 21 && opponentScore - myScore == 1) {
                return true
            } else if myScore == 29 && opponentScore == 29 {
                return true
            } else {
                return false
            }
        } else {
            return false
        }
    }

    private var gameHistory: [Game] {
        (try? JSONDecoder().decode([Game].self, from: gameHistoryData)) ?? []
    }

    func checkWinner() {
        let hasWon = (myScore >= 21 && myScore - opponentScore >= 2) || (opponentScore >= 21 && opponentScore - myScore >= 2) || myScore == 30 || opponentScore == 30

        if hasWon {
            let winnerName = myScore > opponentScore ? myName : opponentName
            winner = winnerName
            isAnimating = true

            var history = gameHistory
            history.append(Game(myScore: myScore, opponentScore: opponentScore, winner: winnerName, date: Date()))

            if let encoded = try? JSONEncoder().encode(history) {
                gameHistoryData = encoded
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                myScore = 0
                opponentScore = 0
                isAnimating = false
                winner = nil
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Court Background
                Color(red: 0.2, green: 0.6, blue: 0.2)
                    .ignoresSafeArea()

                // Court Lines
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(height: 2)
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: 2)
                    Rectangle()
                        .fill(Color.white.opacity(0.4))
                        .frame(height: 2)
                }
                .padding(.horizontal, 12)

                // Main Content
                VStack(spacing: 8) {
                    // Opponent's Score
                    ScoreView(name: opponentName, score: opponentScore, isWinner: winner == opponentName, isAnimating: isAnimating, onTap: {
                        opponentScore += 1
                        checkWinner()
                    }, onLongPress: {
                        myScore = 0
                        opponentScore = 0
                        winner = nil
                    })

                    // My Score
                    ScoreView(name: myName, score: myScore, isWinner: winner == myName, isAnimating: isAnimating, onTap: {
                        myScore += 1
                        checkWinner()
                    }, onLongPress: {
                        myScore = 0
                        opponentScore = 0
                        winner = nil
                    })
                }
                .padding(.horizontal, 16)

                // Match Point Indicator
                if isMatchPoint {
                    Text("Match Point!")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(8)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isMatchPoint)
                }

                // Winner Overlay
                if isAnimating {
                    Text("\(winner == myName ? "I Win!" : "\(winner ?? "") Wins!")")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(12)
                        .transition(.scale.combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
                }
            }
            .navigationBarBackButtonHidden(false)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Menu") {
                        currentView = .menu
                    }
                }
            }
        }
    }
}

struct ScoreView: View {
    let name: String
    let score: Int
    let isWinner: Bool
    let isAnimating: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)

            Text("\(score)")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.25))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.6), lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in onLongPress() }
        )
        .scaleEffect(isWinner && isAnimating ? 1.2 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isAnimating)
    }
}

struct SettingsView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("gameMode") private var gameMode: GameView.GameMode = .singles
    @AppStorage("myName") private var myName = "Me"
    @AppStorage("opponentName") private var opponentName = "Opponent"

    var body: some View {
        List {
            Section(header: Text("Game Mode")) {
                Picker("Mode", selection: $gameMode) {
                    Text("Singles").tag(GameView.GameMode.singles)
                    Text("Doubles").tag(GameView.GameMode.doubles)
                }
            }

            Section(header: Text("Player Names")) {
                TextField("Your Name", text: $myName)
                TextField("Opponent Name", text: $opponentName)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    currentView = .menu
                }
            }
        }
    }
}

struct HistoryView: View {
    @Binding var currentView: ContentView.AppView
    @AppStorage("gameHistory") private var gameHistoryData: Data = Data()

    private var gameHistory: [Game] {
        (try? JSONDecoder().decode([Game].self, from: gameHistoryData)) ?? []
    }

    var body: some View {
        List(gameHistory.reversed()) { game in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(game.winner) won")
                    .font(.headline)
                Text("Score: \(game.myScore) - \(game.opponentScore)")
                    .font(.subheadline)
                Text(game.date, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Game History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") {
                    currentView = .menu
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
