//
//  MatchModel.swift
//  BadmintonCore
//
//  Pure, testable scoring logic for a best-of-three badminton match.
//

import Foundation

public enum Side: String, Codable, Equatable {
    case me
    case opponent
}

/// Final score of a single completed game within a match.
public struct GameScore: Codable, Equatable, Identifiable {
    public var id = UUID()
    public let my: Int
    public let opponent: Int

    public init(id: UUID = UUID(), my: Int, opponent: Int) {
        self.id = id
        self.my = my
        self.opponent = opponent
    }
}

/// Drives a single badminton match. No timers, no UI — every transition is a
/// pure function of the current state, which makes the rules unit-testable.
public struct BadmintonMatch: Codable, Equatable {
    public let pointsToWin: Int   // 21
    public let pointCap: Int      // 30 — at 29-29 the 30th point wins
    public let gamesToWin: Int    // 2  — best of three

    public private(set) var myScore: Int = 0
    public private(set) var opponentScore: Int = 0
    public private(set) var myGamesWon: Int = 0
    public private(set) var opponentGamesWon: Int = 0
    public private(set) var completedGames: [GameScore] = []
    /// Whoever won the previous rally serves next. Court side is derived from this.
    public private(set) var serverIsMe: Bool

    public init(serverIsMe: Bool = true,
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
    public var gameWinner: Side? {
        if myScore >= pointCap { return .me }
        if opponentScore >= pointCap { return .opponent }
        if myScore >= pointsToWin && myScore - opponentScore >= 2 { return .me }
        if opponentScore >= pointsToWin && opponentScore - myScore >= 2 { return .opponent }
        return nil
    }

    public var matchWinner: Side? {
        if myGamesWon >= gamesToWin { return .me }
        if opponentGamesWon >= gamesToWin { return .opponent }
        return nil
    }

    public var isMatchOver: Bool { matchWinner != nil }

    /// True while a game is decided but the next game hasn't started yet.
    public var isGameOver: Bool { gameWinner != nil }

    /// Either side is one rally away from winning the current game.
    public var isGamePoint: Bool {
        pointWouldEndGame(.me) || pointWouldEndGame(.opponent)
    }

    /// Either side is one rally away from winning the whole match.
    public var isMatchPoint: Bool {
        pointWouldEndMatch(.me) || pointWouldEndMatch(.opponent)
    }

    // MARK: - Serve

    public var servingSide: Side { serverIsMe ? .me : .opponent }

    /// In both singles and doubles the serving side serves from the right
    /// service court when its score is even, the left court when odd.
    public var serveFromRightCourt: Bool {
        (serverIsMe ? myScore : opponentScore) % 2 == 0
    }

    // MARK: - Mutations

    /// Award a rally to `side`. No-op once the current game or match is over —
    /// the caller advances with `startNextGame()`.
    public mutating func score(_ side: Side) {
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

    /// Clear the board for the next game. Pass `serverIsMe` to override the automatic serve assignment.
    public mutating func startNextGame(serverIsMe: Bool? = nil) {
        guard gameWinner != nil, matchWinner == nil else { return }
        self.serverIsMe = serverIsMe ?? (myScore > opponentScore)
        myScore = 0
        opponentScore = 0
    }

    /// Force-ends the current game in favour of `winner` (used for sudden death in time mode).
    /// Records the current score as the game result and resets the board.
    public mutating func recordSuddenDeathGame(winner: Side) {
        guard gameWinner == nil, matchWinner == nil else { return }
        completedGames.append(GameScore(my: myScore, opponent: opponentScore))
        if winner == .me { myGamesWon += 1 } else { opponentGamesWon += 1 }
        serverIsMe = (winner == .me)
        myScore = 0
        opponentScore = 0
    }

    /// True when all games have been played and the result is a draw (only possible with an even gamesInMatch setting).
    public var isTied: Bool {
        let totalPlayed = completedGames.count
        return matchWinner == nil && totalPlayed >= (gamesToWin * 2 - 1) && myGamesWon == opponentGamesWon
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
public struct MatchRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let games: [GameScore]
    public let myGamesWon: Int
    public let opponentGamesWon: Int
    public var winner: String
    public var myName: String
    public var opponentName: String
    public let date: Date
    public let duration: TimeInterval
    public var myPlayerId: UUID?
    public var opponentPlayerId: UUID?

    public init(id: UUID = UUID(),
                games: [GameScore],
                myGamesWon: Int,
                opponentGamesWon: Int,
                winner: String,
                myName: String = "",
                opponentName: String = "",
                date: Date,
                duration: TimeInterval = 0,
                myPlayerId: UUID? = nil,
                opponentPlayerId: UUID? = nil) {
        self.id = id
        self.games = games
        self.myGamesWon = myGamesWon
        self.opponentGamesWon = opponentGamesWon
        self.winner = winner
        self.myName = myName
        self.opponentName = opponentName
        self.date = date
        self.duration = duration
        self.myPlayerId = myPlayerId
        self.opponentPlayerId = opponentPlayerId
    }
}
