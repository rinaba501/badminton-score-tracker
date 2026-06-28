//
//  badminton_score_tracker_Watch_AppTests.swift
//  badminton score tracker Watch AppTests
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//

import Testing
@testable import badminton_score_tracker_Watch_App

struct BadmintonMatchTests {

    /// Helper: award `count` points to `side`.
    private func score(_ match: inout BadmintonMatch, _ side: Side, _ count: Int) {
        for _ in 0..<count { match.score(side) }
    }

    @Test func scoringIncrementsAndSetsServer() {
        var match = BadmintonMatch()
        match.score(.me)
        #expect(match.myScore == 1)
        #expect(match.servingSide == .me)
        match.score(.opponent)
        #expect(match.opponentScore == 1)
        #expect(match.servingSide == .opponent)
    }

    @Test func winAtTwentyOneWithTwoPointMargin() {
        var match = BadmintonMatch()
        score(&match, .opponent, 10)
        score(&match, .me, 21)
        #expect(match.gameWinner == .me)
        #expect(match.myGamesWon == 1)
    }

    @Test func mustWinByTwoPoints() {
        var match = BadmintonMatch()
        score(&match, .me, 20)
        score(&match, .opponent, 20)
        #expect(match.gameWinner == nil)        // 20-20 deuce
        match.score(.me)
        #expect(match.gameWinner == nil)        // 21-20, game point not over
        #expect(match.isGamePoint)
        match.score(.me)
        #expect(match.gameWinner == .me)        // 22-20 wins
    }

    @Test func scoreCappedAtThirty() {
        var match = BadmintonMatch()
        // Alternate to 29-29 (can't run one side ahead or it wins at 21).
        for _ in 0..<29 {
            match.score(.me)
            match.score(.opponent)
        }
        #expect(match.myScore == 29 && match.opponentScore == 29)
        #expect(match.gameWinner == nil)        // 29-29
        match.score(.opponent)
        #expect(match.gameWinner == .opponent)  // 30-29 wins even without 2-point margin
    }

    @Test func bestOfThreeMatchWinner() {
        var match = BadmintonMatch()
        // Game 1 to me
        score(&match, .me, 21)
        match.startNextGame()
        #expect(match.myGamesWon == 1)
        #expect(match.matchWinner == nil)
        // Game 2 to me
        score(&match, .me, 21)
        #expect(match.myGamesWon == 2)
        #expect(match.matchWinner == .me)
        #expect(match.completedGames.count == 2)
    }

    @Test func threeGameMatch() {
        var match = BadmintonMatch()
        score(&match, .me, 21);        match.startNextGame()  // 1-0
        score(&match, .opponent, 21);  match.startNextGame()  // 1-1
        #expect(match.matchWinner == nil)
        score(&match, .opponent, 21)                          // 1-2
        #expect(match.matchWinner == .opponent)
    }

    @Test func cannotScoreAfterGameOverUntilNextGame() {
        var match = BadmintonMatch()
        score(&match, .me, 21)
        #expect(match.gameWinner == .me)
        match.score(.me)                        // ignored
        #expect(match.myScore == 21)
        match.startNextGame()
        #expect(match.myScore == 0)
        #expect(match.opponentScore == 0)
    }

    @Test func cannotScoreAfterMatchOver() {
        var match = BadmintonMatch()
        score(&match, .me, 21); match.startNextGame()
        score(&match, .me, 21)
        #expect(match.matchWinner == .me)
        match.score(.opponent)
        #expect(match.opponentScore == 0)       // frozen after match
    }

    @Test func winnerOfPreviousGameServesFirst() {
        var match = BadmintonMatch(serverIsMe: true)
        score(&match, .opponent, 21)            // opponent wins game 1
        match.startNextGame()
        #expect(match.servingSide == .opponent) // game winner serves next
    }

    @Test func serveCourtFollowsServerScoreParity() {
        var match = BadmintonMatch()
        match.score(.me)                        // my score 1 (odd), I serve
        #expect(match.servingSide == .me)
        #expect(match.serveFromRightCourt == false)
        match.score(.me)                        // my score 2 (even)
        #expect(match.serveFromRightCourt == true)
    }

    @Test func matchPointDetection() {
        var match = BadmintonMatch()
        score(&match, .me, 21); match.startNextGame()  // me leads 1-0
        score(&match, .me, 20)
        #expect(match.isGamePoint)
        #expect(match.isMatchPoint)             // winning this game wins the match
    }

    @Test func gamePointButNotMatchPointEarly() {
        var match = BadmintonMatch()
        score(&match, .me, 20)                  // first game, 20-0
        #expect(match.isGamePoint)
        #expect(!match.isMatchPoint)            // only 1 game won would still need another
    }
}
