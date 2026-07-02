//
//  badminton_score_tracker_Watch_AppTests.swift
//  badminton score tracker Watch AppTests
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//

import Foundation
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

struct PersistenceStoreTests {

    private func record(_ winner: String, at date: Date, id: UUID = UUID()) -> MatchRecord {
        MatchRecord(id: id, games: [], myGamesWon: 0, opponentGamesWon: 0, winner: winner, date: date)
    }

    @Test func mergeHistoryUnionsAndSortsByDate() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let a = record("A", at: t0)
        let b = record("B", at: t0.addingTimeInterval(60))
        let c = record("C", at: t0.addingTimeInterval(120))
        // Overlapping middle record; lists in different orders.
        let merged = PersistenceStore.mergeHistory([b, a], [c, b])
        #expect(merged.map(\.id) == [a.id, b.id, c.id])   // union, chronological
    }

    @Test func mergeHistoryDedupesSameId() {
        let r = record("A", at: Date())
        let merged = PersistenceStore.mergeHistory([r], [r])
        #expect(merged.count == 1)
    }

    @Test func mergeHistoryHandlesEmptyInputs() {
        let r = record("A", at: Date())
        #expect(PersistenceStore.mergeHistory([], []).isEmpty)
        #expect(PersistenceStore.mergeHistory([r], []).map(\.id) == [r.id])
        #expect(PersistenceStore.mergeHistory([], [r]).map(\.id) == [r.id])
    }
}

struct PlayerIdentityTests {

    @Test func guestLabelsAreRecognizedAsGuests() {
        #expect(Player.isGuestName(Player.guestNearLabel))
        #expect(Player.isGuestName(Player.guestFarLabel))
    }

    @Test func currentUserNameIsNotStoredAsSavedPlayer() {
        #expect(!Player.shouldBeStoredAsSavedPlayer(Player.defaultMyName, currentUserName: Player.defaultMyName))
        #expect(!Player.shouldBeStoredAsSavedPlayer("Alex", currentUserName: "Alex"))
        #expect(Player.shouldBeStoredAsSavedPlayer("Alex", currentUserName: Player.defaultMyName))
        #expect(!Player.shouldBeStoredAsSavedPlayer(Player.guestNearLabel, currentUserName: Player.defaultMyName))
        #expect(!Player.shouldBeStoredAsSavedPlayer("", currentUserName: Player.defaultMyName))
    }

    @Test func realNamesAreNotGuests() {
        #expect(!Player.isGuestName("Alex"))
        #expect(!Player.isGuestName(""))
        #expect(!Player.isGuestName(Player.defaultMyName))
    }

    @Test func guestLabelsAreDistinctFromEachOther() {
        // Near/far guests must not collide, or excluding "the other side's
        // guest" from a picker would also exclude the current side's guest.
        #expect(Player.guestNearLabel != Player.guestFarLabel)
    }
}

struct HistoryShrinkTests {

    private func record(_ id: UUID = UUID()) -> MatchRecord {
        MatchRecord(id: id, games: [], myGamesWon: 0, opponentGamesWon: 0, winner: "A", date: Date())
    }

    @Test func removingARecordIsAShrink() {
        let a = record()
        let b = record()
        #expect(PersistenceStore.isHistoryShrink(from: [a, b], to: [a]))
    }

    @Test func clearingAllRecordsIsAShrink() {
        let a = record()
        #expect(PersistenceStore.isHistoryShrink(from: [a], to: []))
    }

    @Test func addingARecordIsNotAShrink() {
        let a = record()
        let b = record()
        #expect(!PersistenceStore.isHistoryShrink(from: [a], to: [a, b]))
    }

    @Test func renamingInPlaceIsNotAShrink() {
        // Same set of ids, different field values (e.g. a name-propagation
        // rename) — must still be treated as safe to merge, not a deletion,
        // so any record concurrently added on another device isn't dropped.
        let id = UUID()
        let before = MatchRecord(id: id, games: [], myGamesWon: 0, opponentGamesWon: 0, winner: "Old", date: Date())
        let after = MatchRecord(id: id, games: [], myGamesWon: 0, opponentGamesWon: 0, winner: "New", date: Date())
        #expect(!PersistenceStore.isHistoryShrink(from: [before], to: [after]))
    }

    @Test func noOpEmptyToEmptyIsNotAShrink() {
        #expect(!PersistenceStore.isHistoryShrink(from: [], to: []))
    }
}
