//
//  ChallengeRecord.swift
//  BadmintonCore
//
//  Roadmap Phase 5 backlog (#162): a "want to play?" ping between two
//  members of a club. Unlike Club/Player/MatchRecord, the two parties are
//  real account holders, not roster Players (a Player has no account link)
//  — fromParticipantId/toParticipantId are each an `auth.uid()` string.
//  Display names are snapshotted at send time rather than re-resolved live,
//  so a challenge still renders correctly even if the recipient's device
//  never re-fetches the club's member list.
//

import Foundation

public struct ChallengeRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let clubId: UUID
    public let fromParticipantId: String
    public let fromDisplayName: String
    public let toParticipantId: String
    public let toDisplayName: String
    public var status: Status
    public let createdDate: Date

    public enum Status: String, Codable, Equatable {
        case pending, accepted, declined
    }

    public init(
        id: UUID = UUID(),
        clubId: UUID,
        fromParticipantId: String,
        fromDisplayName: String,
        toParticipantId: String,
        toDisplayName: String,
        status: Status = .pending,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.clubId = clubId
        self.fromParticipantId = fromParticipantId
        self.fromDisplayName = fromDisplayName
        self.toParticipantId = toParticipantId
        self.toDisplayName = toDisplayName
        self.status = status
        self.createdDate = createdDate
    }
}
