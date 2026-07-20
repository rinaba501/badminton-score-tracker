//
//  FriendProfile.swift
//  BadmintonCore
//
//  Friends v1 (graph-only, data-model slice): a discoverable profile record
//  so two people who don't already share a club can find each other via an
//  out-of-band invite link/code. `participantId` is a durable, per-account
//  key (an `auth.uid()` string) — the same identity space ChallengeRecord/
//  ReactionRecord's participant-id fields use once a device is Supabase-
//  active. One profile per account, upserted by `participantId` rather than
//  freely created. `displayName` is user-supplied free text (no identity
//  verification), same convention as ChallengeRecord's snapshotted names.
//
//  This model is deliberately transport-agnostic (Foundation only) —
//  SupabaseSyncManager on each app target owns the actual `profiles` table
//  read/write; this struct is just the payload shape.
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
