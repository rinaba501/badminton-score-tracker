//
//  MatchInviteMirrorTests.swift
//  BadmintonCoreTests
//
//  Roadmap Phase 10a: pins MatchInviteMirror.build's flip/recompute logic.
//

import Foundation
import Testing
@testable import BadmintonCore

struct MatchInviteMirrorTests {

    private func invite(
        games: [(Int, Int)], fromName: String = "Alex", myGamesWon: Int, opponentGamesWon: Int,
        winner: RecordSide, date: Date = Date(timeIntervalSince1970: 5_000), isOfficial: Bool = true
    ) -> SharedMatchInvite {
        let snapshot = MatchRecord(
            games: games.map { GameScore(my: $0.0, opponent: $0.1) },
            myGamesWon: myGamesWon, opponentGamesWon: opponentGamesWon, winner: winner,
            myName: fromName, opponentName: "Recipient", date: date, duration: 900,
            isOfficial: isOfficial
        )
        return SharedMatchInvite(
            id: snapshot.id, fromParticipantId: "alex-id", fromDisplayName: fromName,
            toParticipantId: "recipient-id", matchSnapshot: snapshot
        )
    }

    /// GameScore.id is a fresh UUID per instance and carries no meaning about
    /// the result — compare score values only, not full GameScore equality.
    private func scoreValues(_ games: [GameScore]) -> [[Int]] {
        games.map { [$0.my, $0.opponent] }
    }

    @Test func buildFlipsGamesAndRecomputesWinnerWhenSenderWon() throws {
        let sent = invite(games: [(21, 18), (21, 15)], myGamesWon: 2, opponentGamesWon: 0, winner: .near)
        let mirror = try #require(MatchInviteMirror.build(from: sent, myName: "Me", myPlayerId: nil))
        #expect(scoreValues(mirror.games) == [[18, 21], [15, 21]])
        #expect(mirror.myGamesWon == 0)
        #expect(mirror.opponentGamesWon == 2)
        #expect(mirror.winner == .far)
    }

    @Test func buildFlipsGamesAndRecomputesWinnerWhenSenderLost() throws {
        let sent = invite(games: [(15, 21), (18, 21)], myGamesWon: 0, opponentGamesWon: 2, winner: .far)
        let mirror = try #require(MatchInviteMirror.build(from: sent, myName: "Me", myPlayerId: nil))
        #expect(scoreValues(mirror.games) == [[21, 15], [21, 18]])
        #expect(mirror.myGamesWon == 2)
        #expect(mirror.opponentGamesWon == 0)
        #expect(mirror.winner == .near)
    }

    @Test func buildSetsIdentityFromRecipientNeverFromInvite() throws {
        let sent = invite(games: [(21, 15)], myGamesWon: 1, opponentGamesWon: 0, winner: .near)
        let myId = UUID()
        let mirror = try #require(MatchInviteMirror.build(from: sent, myName: "RecipientLocalName", myPlayerId: myId))
        #expect(mirror.myName == "RecipientLocalName")
        #expect(mirror.myPlayerId == myId)
        #expect(mirror.opponentName == "Alex")
        #expect(mirror.opponentPlayerId == nil)
    }

    @Test func buildSetsSourceMatchIdAndOpponentParticipantIdAndClearsClubId() throws {
        let sent = invite(games: [(21, 15)], myGamesWon: 1, opponentGamesWon: 0, winner: .near)
        let mirror = try #require(MatchInviteMirror.build(from: sent, myName: "Me", myPlayerId: nil))
        #expect(mirror.sourceMatchId == sent.id)
        #expect(mirror.opponentParticipantId == "alex-id")
        #expect(mirror.clubId == nil)
        #expect(mirror.isConfirmed == true)
    }

    @Test func buildPreservesDateAndDuration() throws {
        let date = Date(timeIntervalSince1970: 12_345)
        let sent = invite(games: [(21, 15)], myGamesWon: 1, opponentGamesWon: 0, winner: .near, date: date)
        let mirror = try #require(MatchInviteMirror.build(from: sent, myName: "Me", myPlayerId: nil))
        #expect(mirror.date == date)
        #expect(mirror.duration == 900)
    }

    @Test func buildReturnsNilWhenSnapshotGamesAreEmpty() {
        let snapshot = MatchRecord(games: [], myGamesWon: 0, opponentGamesWon: 0, winner: .near,
                                    myName: "Alex", opponentName: "Recipient", date: Date())
        let sent = SharedMatchInvite(
            id: snapshot.id, fromParticipantId: "alex-id", fromDisplayName: "Alex",
            toParticipantId: "recipient-id", matchSnapshot: snapshot
        )
        #expect(MatchInviteMirror.build(from: sent, myName: "Me", myPlayerId: nil) == nil)
    }
}
