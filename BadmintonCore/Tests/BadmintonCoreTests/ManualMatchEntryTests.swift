//
//  ManualMatchEntryTests.swift
//  BadmintonCoreTests
//
//  MatchRecord.resultFromManualGames — issue #278, manual match entry.
//

import Foundation
import Testing
@testable import BadmintonCore

struct ManualMatchEntryTests {

    @Test func straightGamesWinForMe() {
        let result = MatchRecord.resultFromManualGames([
            GameScore(my: 21, opponent: 15),
            GameScore(my: 21, opponent: 18)
        ])
        #expect(result?.myGamesWon == 2)
        #expect(result?.opponentGamesWon == 0)
        #expect(result?.winner == .near)
    }

    @Test func decidingGameWinForOpponent() {
        let result = MatchRecord.resultFromManualGames([
            GameScore(my: 21, opponent: 15),
            GameScore(my: 18, opponent: 21),
            GameScore(my: 12, opponent: 21)
        ])
        #expect(result?.myGamesWon == 1)
        #expect(result?.opponentGamesWon == 2)
        #expect(result?.winner == .far)
    }

    @Test func singleGameMatch() {
        let result = MatchRecord.resultFromManualGames([GameScore(my: 11, opponent: 9)])
        #expect(result?.myGamesWon == 1)
        #expect(result?.opponentGamesWon == 0)
        #expect(result?.winner == .near)
    }

    @Test func emptyGamesListIsInvalid() {
        #expect(MatchRecord.resultFromManualGames([]) == nil)
    }

    @Test func aTiedGameIsInvalid() {
        #expect(MatchRecord.resultFromManualGames([GameScore(my: 20, opponent: 20)]) == nil)
    }

    @Test func aTiedOverallGameCountIsInvalid() {
        let result = MatchRecord.resultFromManualGames([
            GameScore(my: 21, opponent: 10),
            GameScore(my: 10, opponent: 21)
        ])
        #expect(result == nil)
    }
}
