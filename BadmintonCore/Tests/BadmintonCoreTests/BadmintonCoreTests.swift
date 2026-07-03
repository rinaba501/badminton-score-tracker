//
//  BadmintonCoreTests.swift
//  BadmintonCoreTests
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//  Moved from the Watch App test bundle when the core logic was extracted
//  into the BadmintonCore package.
//

import Foundation
import Testing
@testable import BadmintonCore

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

struct PlayerSortingTests {

    @Test func rosterSortOrderSupportsNameAndCreatedOrdering() {
        let players = [
            Player(name: "Zoe", colorIndex: 0),
            Player(name: "Alex", colorIndex: 0),
            Player(name: "Mina", colorIndex: 0)
        ]

        let byName = Player.sortedPlayers(players, order: .name)
        #expect(byName.map(\.name) == ["Alex", "Mina", "Zoe"])

        let byNameDescending = Player.sortedPlayers(players, order: .nameDescending)
        #expect(byNameDescending.map(\.name) == ["Zoe", "Mina", "Alex"])

        let createdOrder = Player.sortedPlayers(players, order: .created)
        #expect(createdOrder.map(\.name) == ["Zoe", "Alex", "Mina"])
    }

    @Test func rosterSortOrderSupportsMostPlayedAndRecentlyUsedOrdering() {
        let alex = Player(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!, name: "Alex", colorIndex: 0)
        let zoe = Player(id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!, name: "Zoe", colorIndex: 0)
        let mina = Player(id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, name: "Mina", colorIndex: 0)
        let players = [alex, zoe, mina]
        let history = [
            MatchRecord(id: UUID(), games: [], myGamesWon: 0, opponentGamesWon: 0, winner: "Alex", myName: "Alex", opponentName: "Zoe", date: Date(), myPlayerId: alex.id, opponentPlayerId: zoe.id),
            MatchRecord(id: UUID(), games: [], myGamesWon: 0, opponentGamesWon: 0, winner: "Zoe", myName: "Alex", opponentName: "Zoe", date: Date().addingTimeInterval(-60), myPlayerId: alex.id, opponentPlayerId: zoe.id),
            MatchRecord(id: UUID(), games: [], myGamesWon: 0, opponentGamesWon: 0, winner: "Mina", myName: "Mina", opponentName: "Alex", date: Date().addingTimeInterval(-120), myPlayerId: mina.id, opponentPlayerId: alex.id)
        ]

        let mostPlayed = Player.sortedPlayers(players, order: .mostPlayed, history: history)
        #expect(mostPlayed.map(\.name) == ["Alex", "Zoe", "Mina"])

        let recentlyUsed = Player.sortedPlayers(players, order: .recentlyUsed, history: history)
        #expect(recentlyUsed.map(\.name) == ["Alex", "Zoe", "Mina"])
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
