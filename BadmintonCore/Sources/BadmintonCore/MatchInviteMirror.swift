//
//  MatchInviteMirror.swift
//  BadmintonCore
//
//  Roadmap Phase 10a: builds the recipient's own `MatchRecord` from an
//  accepted `SharedMatchInvite`. Kept out of `MatchModel.swift` (which
//  stays a pure scoring-engine file) and out of `AppStore`/UI, so the
//  flip-and-recompute logic is unit-testable in isolation, the same split
//  `FriendHistorySnapshot`/`ChallengeRecord` already get their own files
//  rather than being folded into `MatchModel.swift`.
//
//  Deliberately does NOT attempt to detect or merge against a record the
//  recipient already logged for the same match themselves — that's
//  `StatsCalculator.conflictingRecord`'s job (it decides whether to call
//  `build` at all vs. surface a manual review), and two independently
//  logged, identically-scored records are accepted to coexist rather than
//  being auto-deduped (see that function's doc comment).
//

import Foundation

public enum MatchInviteMirror {
    /// Flips every `GameScore` (my/opponent swap), recomputes
    /// `myGamesWon`/`opponentGamesWon`/`winner` from the flipped games via
    /// `MatchRecord.resultFromManualGames`, and sets `myName`/`myPlayerId`
    /// to the RECIPIENT's own identity (never copied from the invite —
    /// `myName` is locally scoped, same as everywhere else in this
    /// codebase). `opponentPlayerId` is always `nil`: the sender isn't a
    /// roster `Player` on this device. Returns `nil` only if
    /// `resultFromManualGames` itself does (a malformed/empty `games`
    /// snapshot) — shouldn't happen for a `matchSnapshot` that came from a
    /// completed match, but this package's convention is to stay
    /// defensive/decode-tolerant rather than assume.
    public static func build(from invite: SharedMatchInvite, myName: String, myPlayerId: UUID?) -> MatchRecord? {
        let flippedGames = invite.matchSnapshot.games.map { GameScore(my: $0.opponent, opponent: $0.my) }
        guard let result = MatchRecord.resultFromManualGames(flippedGames) else { return nil }
        return MatchRecord(
            games: flippedGames,
            myGamesWon: result.myGamesWon,
            opponentGamesWon: result.opponentGamesWon,
            winner: result.winner,
            myName: myName,
            opponentName: invite.fromDisplayName,
            date: invite.matchSnapshot.date,
            duration: invite.matchSnapshot.duration,
            myPlayerId: myPlayerId,
            opponentPlayerId: nil,
            clubId: nil,
            isConfirmed: true,
            isOfficial: invite.matchSnapshot.isOfficial,
            opponentParticipantId: invite.fromParticipantId,
            sourceMatchId: invite.id
        )
    }
}
