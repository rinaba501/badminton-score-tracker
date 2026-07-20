//
//  MatchInvite.swift
//  BadmintonCore
//
//  Roadmap Phase 10a: a "did this happen?" ping sent when a personal
//  (non-club, singles) MatchRecord's opponent was picked from Friends —
//  the recorder's own account is fromParticipantId, the opponent's account
//  is toParticipantId, same real-account-holder identity space
//  ChallengeRecord/FriendRequest use (an auth.uid() string), not a roster
//  Player. `id` deliberately reuses the SENDER's own MatchRecord.id rather
//  than minting a fresh one — see supabase/schema.sql's match_invites
//  table comment — so the recipient's mirrored MatchRecord.sourceMatchId
//  can just equal this same id with no separate lookup, and re-sending an
//  edited match is a plain upsert rather than a new row. Unlike
//  FriendRequest, most invites are never seen by a human at all: AppStore
//  auto-accepts (mirrors matchSnapshot into the recipient's own history)
//  whenever no conflicting record already exists, since being friends is
//  already the trust boundary — a manual accept/decline only surfaces when
//  StatsCalculator.conflictingRecord finds a pre-existing, differently-
//  scored record for the same two participants (see MatchInviteMirror.swift
//  and AppStore.matchConflicts).
//

import Foundation

public struct SharedMatchInvite: Identifiable, Codable, Equatable {
    public let id: UUID
    public let fromParticipantId: String
    public let fromDisplayName: String
    public let toParticipantId: String
    public var status: Status
    public let createdDate: Date
    public let matchSnapshot: MatchRecord

    public enum Status: String, Codable, Equatable {
        case pending, accepted, declined
    }

    public init(
        id: UUID,
        fromParticipantId: String,
        fromDisplayName: String,
        toParticipantId: String,
        status: Status = .pending,
        createdDate: Date = Date(),
        matchSnapshot: MatchRecord
    ) {
        self.id = id
        self.fromParticipantId = fromParticipantId
        self.fromDisplayName = fromDisplayName
        self.toParticipantId = toParticipantId
        self.status = status
        self.createdDate = createdDate
        self.matchSnapshot = matchSnapshot
    }
}
