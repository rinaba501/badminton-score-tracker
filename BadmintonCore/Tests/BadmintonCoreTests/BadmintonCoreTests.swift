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

    @Test func courtChangeThresholdNeverFiresInEarlierGames() {
        var match = BadmintonMatch()
        score(&match, .me, 11)                  // game 1 of a best-of-3, not the deciding game
        #expect(!match.isCourtChangeThreshold(after: .me))
        match = BadmintonMatch()
        score(&match, .me, 21); match.startNextGame()   // 1-0
        score(&match, .opponent, 11)             // game 2, still not deciding (best-of-3 needs a 1-1 split first)
        #expect(!match.isCourtChangeThreshold(after: .opponent))
    }

    @Test func courtChangeThresholdFiresOnceInDecidingGame() {
        var match = BadmintonMatch()
        score(&match, .me, 21); match.startNextGame()        // 1-0
        score(&match, .opponent, 21); match.startNextGame()  // 1-1 — game 3 is deciding
        score(&match, .me, 10)
        #expect(!match.isCourtChangeThreshold(after: .me))  // 10 of 21 — not yet
        match.score(.me)
        #expect(match.isCourtChangeThreshold(after: .me))   // 11 of 21 — threshold reached
        match.score(.me)
        #expect(!match.isCourtChangeThreshold(after: .me))  // 12 of 21 — already past it
    }

    @Test func courtChangeThresholdFiresForWhicheverSideReachesItFirst() {
        var match = BadmintonMatch()
        score(&match, .me, 21); match.startNextGame()
        score(&match, .opponent, 21); match.startNextGame()  // deciding game
        score(&match, .opponent, 11)             // opponent is the one leading this time
        #expect(match.isCourtChangeThreshold(after: .opponent))   // my score (0) is still under threshold — first crossing
    }

    @Test func courtChangeThresholdDoesNotFireAgainWhenTrailingSideLaterReachesIt() {
        var match = BadmintonMatch()
        score(&match, .me, 21); match.startNextGame()
        score(&match, .opponent, 21); match.startNextGame()  // deciding game
        score(&match, .me, 15)
        score(&match, .opponent, 11)
        #expect(!match.isCourtChangeThreshold(after: .opponent))  // I already crossed 11 earlier — don't re-fire
    }

    @Test func courtChangeThresholdNeverFiresInASingleGameMatch() {
        var match = BadmintonMatch(gamesToWin: 1)
        score(&match, .me, 11)
        #expect(!match.isCourtChangeThreshold(after: .me))  // no game before it, so no "deciding game" distinction
    }

    @Test func courtChangeThresholdScalesWithPointsToWin() {
        var match = BadmintonMatch(pointsToWin: 11, pointCap: 20)
        score(&match, .me, 11); match.startNextGame()
        score(&match, .opponent, 11); match.startNextGame()  // deciding game
        score(&match, .me, 5)
        #expect(!match.isCourtChangeThreshold(after: .me))
        match.score(.me)
        #expect(match.isCourtChangeThreshold(after: .me))   // 6 of 11 is the scaled threshold
    }

    @Test func courtChangeThresholdDoesNotReFireWhileOtherSideCatchesUp() {
        var match = BadmintonMatch()
        score(&match, .me, 21); match.startNextGame()
        score(&match, .opponent, 21); match.startNextGame()  // deciding game
        score(&match, .me, 11)
        #expect(match.isCourtChangeThreshold(after: .me))   // my score just reached 11 — fires
        for _ in 0..<12 {
            match.score(.opponent)
            #expect(!match.isCourtChangeThreshold(after: .opponent))  // opponent catching all the way up to, then past, 11 — never re-fires
        }
        #expect(match.opponentScore == 12)  // sanity: the loop really did carry opponent through 11 (tying) and beyond
    }
}

struct DoublesServeRotationTests {

    /// Helper: award `count` points to `side`.
    private func score(_ match: inout BadmintonMatch, _ side: Side, _ count: Int) {
        for _ in 0..<count { match.score(side) }
    }

    @Test func sameServerAlternatesCourtsWhileTeamKeepsWinning() {
        // Real rule: the same individual keeps serving as long as their team
        // keeps winning, alternating which court (right=0 parity/left=1
        // parity) they personally stand in — captured by currentPartnerIndex
        // staying pinned to the original server's index the whole run.
        var match = BadmintonMatch()
        #expect(match.currentPartnerIndex(for: .me) == 0)   // 0-0, partner 0 starts right
        match.score(.me)                                    // 1-0, still serving
        #expect(match.currentPartnerIndex(for: .me) == 0)   // same server, now in left court
        match.score(.me)                                    // 2-0, still serving
        #expect(match.currentPartnerIndex(for: .me) == 0)   // same server, back in right court
    }

    @Test func sideOutDoesNotMoveEitherTeamsPartners() {
        var match = BadmintonMatch()
        match.score(.me)       // 1-0, me still serving
        match.score(.opponent) // side-out: opponent gains serve at their score 1 (odd)
        #expect(match.servingSide == .opponent)
        // Opponent never served yet this game, so their box assignment is
        // still the game-start default (partner 0 in the right court) —
        // at their score of 1 (odd), the player in the LEFT court serves,
        // which is partner 1 (the complement of the frozen right-box index 0).
        #expect(match.currentPartnerIndex(for: .opponent) == 1)
        // My team's assignment is untouched by losing the rally.
        #expect(match.currentPartnerIndex(for: .me) == 0)
    }

    @Test func receivingTeamsBoxAssignmentFreezesAcrossServiceTurns() {
        var match = BadmintonMatch()
        match.score(.opponent) // side-out immediately: opponent serves at 1 (odd)
        match.score(.opponent) // opponent continues serving at 2 (even) — same server both times
        #expect(match.currentPartnerIndex(for: .opponent) == 1)
        match.score(.me) // side-out back to me; opponent's box assignment freezes here
        #expect(match.currentPartnerIndex(for: .opponent) == 1) // frozen while not serving
        match.score(.me) // me continues serving; opponent still untouched
        #expect(match.currentPartnerIndex(for: .opponent) == 1)
    }

    @Test func startNextGameResetsBoxAssignmentsToDefaultsUnlessOverridden() {
        var match = BadmintonMatch()
        match.score(.me)
        match.score(.me) // my box index has toggled away from 0
        score(&match, .me, 19)
        match.startNextGame()
        #expect(match.currentPartnerIndex(for: .me) == 0)
        #expect(match.currentPartnerIndex(for: .opponent) == 0)
    }

    @Test func startNextGameAcceptsExplicitBoxAssignments() {
        var match = BadmintonMatch()
        score(&match, .me, 21)
        match.startNextGame(myRightBoxPartnerIndex: 1, opponentRightBoxPartnerIndex: 1)
        #expect(match.currentPartnerIndex(for: .me) == 1)
        #expect(match.currentPartnerIndex(for: .opponent) == 1)
    }

    @Test func recordSuddenDeathGameResetsBoxAssignments() {
        var match = BadmintonMatch()
        match.score(.me)
        match.score(.me)
        match.recordSuddenDeathGame(winner: .me)
        #expect(match.currentPartnerIndex(for: .me) == 0)
        #expect(match.currentPartnerIndex(for: .opponent) == 0)
    }
}

struct MatchRecordDoublesFieldsTests {

    @Test func doublesFieldsRoundTripThroughEncoding() throws {
        let record = MatchRecord(
            games: [GameScore(my: 21, opponent: 15)],
            myGamesWon: 1, opponentGamesWon: 0, winner: .near,
            myName: "Alice", opponentName: "Carol", date: Date(),
            myPartnerName: "Bob", opponentPartnerName: "Dana",
            myPartnerPlayerId: UUID(), opponentPartnerPlayerId: UUID()
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: data)
        #expect(decoded.myPartnerName == "Bob")
        #expect(decoded.opponentPartnerName == "Dana")
        #expect(decoded.myPartnerPlayerId == record.myPartnerPlayerId)
        #expect(decoded.opponentPartnerPlayerId == record.opponentPartnerPlayerId)
    }

    @Test func legacySinglesJSONDecodesWithNilPartnerFields() throws {
        // Shaped exactly like a pre-doubles record — no partner keys present.
        let json = """
        {"id":"\(UUID().uuidString)","games":[],"myGamesWon":1,"opponentGamesWon":0,
        "winner":"Alice","myName":"Alice","opponentName":"Carol",
        "date":\(Date().timeIntervalSinceReferenceDate),"duration":0}
        """
        let decoded = try JSONDecoder().decode(MatchRecord.self, from: Data(json.utf8))
        #expect(decoded.myPartnerName == nil)
        #expect(decoded.opponentPartnerName == nil)
        #expect(decoded.myPartnerPlayerId == nil)
        #expect(decoded.opponentPartnerPlayerId == nil)
        #expect(decoded.myName == "Alice")
    }
}

struct PersistenceStoreTests {

    private func record(_ winner: String, at date: Date, id: UUID = UUID()) -> MatchRecord {
        MatchRecord(id: id, games: [], myGamesWon: 0, opponentGamesWon: 0, winner: .near, date: date)
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

    @Test func guestTokensAreRecognizedAsGuestsIndependentOfLocale() {
        // Unlike the legacy localized labels, these are fixed literals never
        // routed through NSLocalizedString — so the check can't depend on
        // which locale happens to be active.
        #expect(Player.isGuestName(Player.guestNearToken))
        #expect(Player.isGuestName(Player.guestFarToken))
        #expect(Player.guestNearToken != Player.guestFarToken)
        #expect(!Player.shouldBeStoredAsSavedPlayer(Player.guestNearToken, currentUserName: Player.defaultMyName))
        #expect(!Player.shouldBeStoredAsSavedPlayer(Player.guestFarToken, currentUserName: Player.defaultMyName))
    }

    @Test func displayNameMapsGuestTokensToLabels() {
        #expect(Player.displayName(for: Player.guestNearToken) == Player.guestNearLabel)
        #expect(Player.displayName(for: Player.guestFarToken) == Player.guestFarLabel)
        #expect(Player.displayName(for: "Alice") == "Alice")
        // Legacy pre-token guest labels pass through unchanged too — they
        // already *are* display text.
        #expect(Player.displayName(for: Player.guestNearLabel) == Player.guestNearLabel)
    }

    @Test func guestPoolTokensAreAllRecognizedAndMutuallyDistinct() {
        #expect(Set(Player.guestTokens).count == Player.guestTokens.count)
        for token in Player.guestTokens {
            #expect(Player.isGuestName(token))
        }
    }

    @Test func guestPoolTokensAreDistinctFromLegacyTokens() {
        #expect(Set(Player.guestTokens).isDisjoint(with: [Player.guestNearToken, Player.guestFarToken]))
    }

    @Test func displayNameMapsEachPoolTokenToItsOwnLabel() {
        let labels = Player.guestTokens.map { Player.displayName(for: $0) }
        #expect(Set(labels).count == Player.guestTokens.count)
        for label in labels {
            #expect(!label.isEmpty)
        }
    }

    @Test func poolTokensAreNotStoredAsSavedPlayer() {
        for token in Player.guestTokens {
            #expect(!Player.shouldBeStoredAsSavedPlayer(token, currentUserName: Player.defaultMyName))
        }
    }

    @Test func randomGuestTokenExcludesUsedTokens() {
        let allButLast = Set(Player.guestTokens.dropLast())
        #expect(Player.randomGuestToken(excluding: allButLast) == Player.guestTokens.last)
    }

    @Test func randomGuestTokenFallsBackWhenPoolFullyExcluded() {
        let drawn = Player.randomGuestToken(excluding: Set(Player.guestTokens))
        #expect(Player.guestTokens.contains(drawn))
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
            MatchRecord(id: UUID(), games: [], myGamesWon: 0, opponentGamesWon: 0, winner: .near, myName: "Alex", opponentName: "Zoe", date: Date(), myPlayerId: alex.id, opponentPlayerId: zoe.id),
            MatchRecord(id: UUID(), games: [], myGamesWon: 0, opponentGamesWon: 0, winner: .far, myName: "Alex", opponentName: "Zoe", date: Date().addingTimeInterval(-60), myPlayerId: alex.id, opponentPlayerId: zoe.id),
            MatchRecord(id: UUID(), games: [], myGamesWon: 0, opponentGamesWon: 0, winner: .near, myName: "Mina", opponentName: "Alex", date: Date().addingTimeInterval(-120), myPlayerId: mina.id, opponentPlayerId: alex.id)
        ]

        let mostPlayed = Player.sortedPlayers(players, order: .mostPlayed, history: history)
        #expect(mostPlayed.map(\.name) == ["Alex", "Zoe", "Mina"])

        let recentlyUsed = Player.sortedPlayers(players, order: .recentlyUsed, history: history)
        #expect(recentlyUsed.map(\.name) == ["Alex", "Zoe", "Mina"])
    }
}

struct HistoryShrinkTests {

    private func record(_ id: UUID = UUID()) -> MatchRecord {
        MatchRecord(id: id, games: [], myGamesWon: 0, opponentGamesWon: 0, winner: .near, date: Date())
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
        let before = MatchRecord(id: id, games: [], myGamesWon: 0, opponentGamesWon: 0, winner: .near, date: Date())
        let after = MatchRecord(id: id, games: [], myGamesWon: 0, opponentGamesWon: 0, winner: .near, myName: "New", date: Date())
        #expect(!PersistenceStore.isHistoryShrink(from: [before], to: [after]))
    }

    @Test func noOpEmptyToEmptyIsNotAShrink() {
        #expect(!PersistenceStore.isHistoryShrink(from: [], to: []))
    }
}

struct ICloudQuotaTests {

    @Test func smallDataDoesNotExceedThreshold() {
        let data = Data(repeating: 0, count: 1_000)
        #expect(!PersistenceStore.exceedsICloudQuotaWarningThreshold(data))
    }

    @Test func dataPastThresholdExceedsIt() {
        let data = Data(repeating: 0, count: PersistenceStore.iCloudQuotaWarningThresholdBytes + 1)
        #expect(PersistenceStore.exceedsICloudQuotaWarningThreshold(data))
    }

    @Test func dataExactlyAtThresholdDoesNotExceedIt() {
        let data = Data(repeating: 0, count: PersistenceStore.iCloudQuotaWarningThresholdBytes)
        #expect(!PersistenceStore.exceedsICloudQuotaWarningThreshold(data))
    }
}
