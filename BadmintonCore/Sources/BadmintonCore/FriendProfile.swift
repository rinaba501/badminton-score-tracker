//
//  FriendProfile.swift
//  BadmintonCore
//
//  Friends v1 (graph-only, data-model slice): a discoverable public-CloudKit-
//  database record so two people who don't already share a club's CKShare
//  zone can find each other via an out-of-band invite link/code. `participantId`
//  is a CKContainer.fetchUserRecordID() result — the durable, per-Apple-ID key
//  — NOT a CKShare.Participant id like ChallengeRecord/ReactionRecord use,
//  since there is no club/share in common yet. One profile per Apple ID,
//  upserted by `participantId` rather than freely created. `displayName` is
//  user-supplied free text (no Apple identity verification), same convention
//  as ChallengeRecord's snapshotted names.
//
//  This model is deliberately CloudKit-transport-agnostic (Foundation only,
//  no CloudKit import) — CloudKitSyncManager on each app target owns the
//  actual public-database read/write; this struct is just the payload shape.
//

import Foundation

public struct FriendProfile: Identifiable, Codable, Equatable {
    public let id: UUID
    public let participantId: String
    public var displayName: String
    public let createdDate: Date

    public init(
        id: UUID = UUID(),
        participantId: String,
        displayName: String,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.participantId = participantId
        self.displayName = displayName
        self.createdDate = createdDate
    }
}
