//
//  MatchModel.swift
//  badminton score tracker Watch App
//
//  Pure, testable scoring logic for a best-of-three badminton match.
//

import Foundation

enum Side: String, Codable, Equatable {
    case me
    case opponent
}

/// Final score of a single completed game within a match.
struct GameScore: Codable, Equatable, Identifiable {
    var id = UUID()
    let my: Int
    let opponent: Int

    init(id: UUID = UUID(), my: Int, opponent: Int) {
        self.id = id
        self.my = my
        self.opponent = opponent
    }
}

/// Drives a single badminton match. No timers, no UI — every transition is a
/// pure function of the current state, which makes the rules unit-testable.
struct BadmintonMatch: Codable, Equatable {
    let pointsToWin: Int   // 21
    let pointCap: Int      // 30 — at 29-29 the 30th point wins
    let gamesToWin: Int    // 2  — best of three

    private(set) var myScore: Int = 0
    private(set) var opponentScore: Int = 0
    private(set) var myGamesWon: Int = 0
    private(set) var opponentGamesWon: Int = 0
    private(set) var completedGames: [GameScore] = []
    /// Whoever won the previous rally serves next. Court side is derived from this.
    private(set) var serverIsMe: Bool

    init(serverIsMe: Bool = true,
         pointsToWin: Int = 21,
         pointCap: Int = 30,
         gamesToWin: Int = 2) {
        self.serverIsMe = serverIsMe
        self.pointsToWin = pointsToWin
        self.pointCap = pointCap
        self.gamesToWin = gamesToWin
    }

    // MARK: - Derived game / match state

    /// Winner of the *current* game, if it has just been decided. Stays non-nil
    /// (scores are left on screen) until `startNextGame()` clears the board.
    var gameWinner: Side? {
        if myScore >= pointCap { return .me }
        if opponentScore >= pointCap { return .opponent }
        if myScore >= pointsToWin && myScore - opponentScore >= 2 { return .me }
        if opponentScore >= pointsToWin && opponentScore - myScore >= 2 { return .opponent }
        return nil
    }

    var matchWinner: Side? {
        if myGamesWon >= gamesToWin { return .me }
        if opponentGamesWon >= gamesToWin { return .opponent }
        return nil
    }

    var isMatchOver: Bool { matchWinner != nil }

    /// True while a game is decided but the next game hasn't started yet.
    var isGameOver: Bool { gameWinner != nil }

    /// Either side is one rally away from winning the current game.
    var isGamePoint: Bool {
        pointWouldEndGame(.me) || pointWouldEndGame(.opponent)
    }

    /// Either side is one rally away from winning the whole match.
    var isMatchPoint: Bool {
        pointWouldEndMatch(.me) || pointWouldEndMatch(.opponent)
    }

    // MARK: - Serve

    var servingSide: Side { serverIsMe ? .me : .opponent }

    /// In both singles and doubles the serving side serves from the right
    /// service court when its score is even, the left court when odd.
    var serveFromRightCourt: Bool {
        (serverIsMe ? myScore : opponentScore) % 2 == 0
    }

    // MARK: - Mutations

    /// Award a rally to `side`. No-op once the current game or match is over —
    /// the caller advances with `startNextGame()`.
    mutating func score(_ side: Side) {
        guard matchWinner == nil, gameWinner == nil else { return }

        switch side {
        case .me:
            myScore += 1
            serverIsMe = true
        case .opponent:
            opponentScore += 1
            serverIsMe = false
        }

        if let winner = gameWinner {
            completedGames.append(GameScore(my: myScore, opponent: opponentScore))
            if winner == .me { myGamesWon += 1 } else { opponentGamesWon += 1 }
        }
    }

    /// Clear the board for the next game. The previous game's winner serves first.
    mutating func startNextGame() {
        guard gameWinner != nil, matchWinner == nil else { return }
        serverIsMe = (myScore > opponentScore)
        myScore = 0
        opponentScore = 0
    }

    // MARK: - Helpers

    private func pointWouldEndGame(_ side: Side) -> Bool {
        guard gameWinner == nil else { return false }
        var copy = self
        copy.score(side)
        return copy.gameWinner == side
    }

    private func pointWouldEndMatch(_ side: Side) -> Bool {
        guard gameWinner == nil else { return false }
        var copy = self
        copy.score(side)
        return copy.matchWinner == side
    }
}

/// A finished match, persisted to history.
struct MatchRecord: Identifiable, Codable, Equatable {
    let id: UUID
    let games: [GameScore]
    let myGamesWon: Int
    let opponentGamesWon: Int
    let winner: String
    let date: Date

    init(id: UUID = UUID(),
         games: [GameScore],
         myGamesWon: Int,
         opponentGamesWon: Int,
         winner: String,
         date: Date) {
        self.id = id
        self.games = games
        self.myGamesWon = myGamesWon
        self.opponentGamesWon = opponentGamesWon
        self.winner = winner
        self.date = date
    }
}
