//
//  StatsCalculatorTests.swift
//  BadmintonCoreTests
//
//  Pins the behavior of the stats derivations extracted from StatsView,
//  HistoryView, and PreMatchView — especially the intentional differences
//  between the two participants functions and the two head-to-head functions.
//

import Foundation
import Testing
@testable import BadmintonCore

struct StatsCalculatorTests {

    /// Helper: a finished match record.
    private func record(my: String, opp: String, winner: String,
                        games: [(Int, Int)] = [(21, 15)],
                        date: Date = Date(timeIntervalSince1970: 1_000),
                        duration: TimeInterval = 0,
                        myId: UUID? = nil, oppId: UUID? = nil) -> MatchRecord {
        MatchRecord(
            games: games.map { GameScore(my: $0.0, opponent: $0.1) },
            myGamesWon: winner == my ? 1 : 0,
            opponentGamesWon: winner == opp ? 1 : 0,
            winner: winner,
            myName: my,
            opponentName: opp,
            date: date,
            duration: duration,
            myPlayerId: myId,
            opponentPlayerId: oppId
        )
    }

    // MARK: - Participants variants

    @Test func allPlayersHoistsMainPlayerAndKeepsEmptyNames() {
        let history = [
            record(my: "Alice", opp: "Bob", winner: "Alice"),
            record(my: "", opp: "Me", winner: "Me")
        ]
        let players = StatsCalculator.allPlayers(history: history, hoisting: "Me")
        #expect(players == ["Me", "Alice", "Bob", ""])
    }

    @Test func participantsDropsEmptyNamesAndDoesNotHoist() {
        let history = [
            record(my: "Alice", opp: "Bob", winner: "Alice"),
            record(my: "", opp: "Me", winner: "Me")
        ]
        let players = StatsCalculator.participants(history: history)
        #expect(players == ["Alice", "Bob", "Me"])
    }

    // MARK: - Player history & aggregates

    @Test func playerHistoryMatchesEitherSide() {
        let history = [
            record(my: "Alice", opp: "Bob", winner: "Alice"),
            record(my: "Cara", opp: "Alice", winner: "Cara"),
            record(my: "Cara", opp: "Bob", winner: "Bob")
        ]
        let alices = StatsCalculator.playerHistory(history, player: "Alice")
        #expect(alices.count == 2)
    }

    @Test func winRateIsZeroForEmptyHistoryAndFiftyForSplit() {
        #expect(StatsCalculator.winRate(player: "Alice", playerHistory: []) == 0)
        let history = [
            record(my: "Alice", opp: "Bob", winner: "Alice"),
            record(my: "Alice", opp: "Bob", winner: "Bob")
        ]
        #expect(StatsCalculator.wins(player: "Alice", playerHistory: history) == 1)
        #expect(StatsCalculator.winRate(player: "Alice", playerHistory: history) == 50.0)
    }

    @Test func longestStreakCountsConsecutiveWins() {
        let history = [
            record(my: "Alice", opp: "Bob", winner: "Alice"),
            record(my: "Alice", opp: "Bob", winner: "Alice"),
            record(my: "Alice", opp: "Bob", winner: "Bob"),
            record(my: "Alice", opp: "Bob", winner: "Alice")
        ]
        #expect(StatsCalculator.longestStreak(player: "Alice", playerHistory: history) == 2)
    }

    @Test func avgPointsScoredUsesThePlayersSideOfEachRecord() {
        let history = [
            record(my: "Alice", opp: "Bob", winner: "Alice", games: [(21, 10)]),
            record(my: "Bob", opp: "Alice", winner: "Bob", games: [(21, 15)])
        ]
        // Alice scored 21 (as near side) and 15 (as far side) over 2 games.
        #expect(StatsCalculator.avgPointsScored(player: "Alice", playerHistory: history) == 18.0)
    }

    @Test func avgMatchDurationIgnoresRecordsWithoutADuration() {
        let history = [
            record(my: "Alice", opp: "Bob", winner: "Alice", duration: 0),
            record(my: "Alice", opp: "Bob", winner: "Alice", duration: 120),
            record(my: "Alice", opp: "Bob", winner: "Bob", duration: 240)
        ]
        #expect(StatsCalculator.avgMatchDuration(playerHistory: history) == 180)
        #expect(StatsCalculator.avgMatchDuration(playerHistory: []) == 0)
    }

    // MARK: - Head-to-head variants

    @Test func headToHeadFallsBackToRosterIdsWhenNamesChanged() {
        let aliceId = UUID()
        let bobId = UUID()
        let roster = [
            Player(id: aliceId, name: "Alice"),
            Player(id: bobId, name: "Bob")
        ]
        // Record saved under old display names but carrying both player ids;
        // it still involves "Alice" by name on one side (playerHistory slices
        // by name), while the opponent name has since changed.
        let history = [
            record(my: "Alice", opp: "Bobby", winner: "Alice", myId: aliceId, oppId: bobId),
            record(my: "Alice", opp: "Bob", winner: "Bob", myId: aliceId, oppId: bobId)
        ]
        let h2h = StatsCalculator.headToHead(player: "Alice", opponent: "Bob",
                                             history: history, roster: roster)
        #expect(h2h.wins == 1)
        #expect(h2h.losses == 1)
    }

    @Test func headToHeadIfAnyReturnsNilWithoutMatchesAndCountsMeSideWins() {
        let roster = [Player(name: "Me"), Player(name: "Rival")]
        #expect(StatsCalculator.headToHeadIfAny(me: "Me", opponent: "Rival",
                                                history: [], roster: roster) == nil)
        let history = [
            record(my: "Me", opp: "Rival", winner: "Me"),
            record(my: "Rival", opp: "Me", winner: "Rival")
        ]
        let h2h = StatsCalculator.headToHeadIfAny(me: "Me", opponent: "Rival",
                                                  history: history, roster: roster)
        #expect(h2h?.wins == 1)
        #expect(h2h?.losses == 1)
    }

    // MARK: - History filtering & formatting

    @Test func filteredHistoryReversesAndAppliesPlayerAndDateFilters() {
        let old = record(my: "Alice", opp: "Bob", winner: "Alice",
                         date: Date(timeIntervalSince1970: 1_000))
        let recent = record(my: "Alice", opp: "Cara", winner: "Cara",
                            date: Date(timeIntervalSince1970: 5_000))
        let history = [old, recent]

        let all = StatsCalculator.filteredHistory(history, selectedPlayer: "", cutoff: nil)
        #expect(all.map(\.id) == [recent.id, old.id])

        let bobOnly = StatsCalculator.filteredHistory(history, selectedPlayer: "Bob", cutoff: nil)
        #expect(bobOnly.map(\.id) == [old.id])

        let recentOnly = StatsCalculator.filteredHistory(
            history, selectedPlayer: "", cutoff: Date(timeIntervalSince1970: 2_000))
        #expect(recentOnly.map(\.id) == [recent.id])

        let oldestFirst = StatsCalculator.filteredHistory(
            history, selectedPlayer: "", cutoff: nil, newestFirst: false)
        #expect(oldestFirst.map(\.id) == [old.id, recent.id])
    }

    @Test func durationStringFormatsMinutesAndSeconds() {
        #expect(StatsCalculator.durationString(0) == "0s")
        #expect(StatsCalculator.durationString(59) == "59s")
        #expect(StatsCalculator.durationString(222) == "3m 42s")
    }
}

/// Doubles records mixed with singles-shaped ones (partner fields nil) —
/// every function must keep its singles behavior unchanged while correctly
/// attributing a partner's participation/wins on their team.
struct StatsCalculatorDoublesTests {

    private func doublesRecord(my: String, myPartner: String, opp: String, oppPartner: String,
                               winner: String, games: [(Int, Int)] = [(21, 15)],
                               date: Date = Date(timeIntervalSince1970: 1_000)) -> MatchRecord {
        MatchRecord(
            games: games.map { GameScore(my: $0.0, opponent: $0.1) },
            myGamesWon: winner == my ? 1 : 0,
            opponentGamesWon: winner == opp ? 1 : 0,
            winner: winner,
            myName: my,
            opponentName: opp,
            date: date,
            myPartnerName: myPartner,
            opponentPartnerName: oppPartner
        )
    }

    @Test func participantsIncludesBothPartnersOnEachTeam() {
        let history = [doublesRecord(my: "Alice", myPartner: "Bob", opp: "Cara", oppPartner: "Dan", winner: "Alice")]
        let players = StatsCalculator.participants(history: history)
        #expect(Set(players) == ["Alice", "Bob", "Cara", "Dan"])
    }

    @Test func playerHistoryMatchesAPartnerNotJustTheRepresentativeName() {
        let history = [doublesRecord(my: "Alice", myPartner: "Bob", opp: "Cara", oppPartner: "Dan", winner: "Alice")]
        // "Bob" never appears as `myName` — only as the partner — yet the
        // record must still count as part of his history.
        #expect(StatsCalculator.playerHistory(history, player: "Bob").count == 1)
    }

    @Test func opponentsExcludesTeammateAndListsBothOfTheOtherTeam() {
        let history = [doublesRecord(my: "Alice", myPartner: "Bob", opp: "Cara", oppPartner: "Dan", winner: "Alice")]
        let bobHistory = StatsCalculator.playerHistory(history, player: "Bob")
        let opponents = StatsCalculator.opponents(of: "Bob", playerHistory: bobHistory)
        #expect(Set(opponents) == ["Cara", "Dan"])
        #expect(!opponents.contains("Alice")) // teammate, never an opponent
    }

    @Test func winsAndLongestStreakAttributeToPartnerViaTeamMembership() {
        // Bob (partner, not the representative `myName`) is on the winning
        // team both times — his personal name never appears in `winner`.
        let history = [
            doublesRecord(my: "Alice", myPartner: "Bob", opp: "Cara", oppPartner: "Dan", winner: "Alice"),
            doublesRecord(my: "Alice", myPartner: "Bob", opp: "Cara", oppPartner: "Dan", winner: "Alice")
        ]
        let bobHistory = StatsCalculator.playerHistory(history, player: "Bob")
        #expect(StatsCalculator.wins(player: "Bob", playerHistory: bobHistory) == 2)
        #expect(StatsCalculator.longestStreak(player: "Bob", playerHistory: bobHistory) == 2)
    }

    @Test func headToHeadRecognizesAPlayerOnEitherTeam() {
        // Bob (near partner) vs Dan (far partner) — neither is the
        // representative name stored in myName/opponentName.
        let history = [doublesRecord(my: "Alice", myPartner: "Bob", opp: "Cara", oppPartner: "Dan", winner: "Alice")]
        let h2h = StatsCalculator.headToHead(player: "Bob", opponent: "Dan", history: history, roster: [])
        #expect(h2h.wins == 1)
        #expect(h2h.losses == 0)
    }

    @Test func singlesRecordsAreUnaffectedByTeamMembershipRework() {
        // Partner fields absent entirely (nil) — must behave exactly as a
        // plain singles record, pinning no-regression for the rework.
        let history = [
            MatchRecord(games: [GameScore(my: 21, opponent: 15)], myGamesWon: 1, opponentGamesWon: 0,
                       winner: "Alice", myName: "Alice", opponentName: "Bob", date: Date())
        ]
        #expect(StatsCalculator.participants(history: history) == ["Alice", "Bob"])
        #expect(StatsCalculator.playerHistory(history, player: "Alice").count == 1)
        #expect(StatsCalculator.opponents(of: "Alice", playerHistory: history) == ["Bob"])
        #expect(StatsCalculator.wins(player: "Alice", playerHistory: history) == 1)
    }
}
