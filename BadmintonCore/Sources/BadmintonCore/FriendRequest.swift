//
//  FriendRequest.swift
//  BadmintonCore
//
//  Friends v1 (graph-only, data-model slice): a friend request/graph edge
//  between two people, independent of any Club. Structurally mirrors
//  ChallengeRecord (same fromParticipantId/toParticipantId/status/
//  createdDate shape, same snapshotted-display-name rationale — a request
//  still renders correctly even if the other side's profile is never
//  re-fetched) but has no `clubId`: friend requests live in CloudKit's
//  public database, not a club's private/shared zone, and are found via an
//  out-of-band invite link/code rather than a CKShare's participant list.
//
//  There is no separate `Friendship` record. An accepted FriendRequest *is*
//  the friendship edge — the same "status flips in place, no new record"
//  convention ChallengeRecord already uses. Accepting a request does NOT
//  create any CKShare/CloudKit zone and does NOT wire up shared match
//  history — that is an explicit non-goal of this phase, left to a future
//  slice, so a future reader shouldn't assume missing wiring here.
//

import Foundation

public struct FriendRequest: Identifiable, Codable, Equatable {
    public let id: UUID
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
        fromParticipantId: String,
        fromDisplayName: String,
        toParticipantId: String,
        toDisplayName: String,
        status: Status = .pending,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.fromParticipantId = fromParticipantId
        self.fromDisplayName = fromDisplayName
        self.toParticipantId = toParticipantId
        self.toDisplayName = toDisplayName
        self.status = status
        self.createdDate = createdDate
    }
}
