//
//  ReactionRecord.swift
//  BadmintonCore
//
//  Roadmap Phase 5 backlog (#164): an emoji reaction or one-line comment on
//  a club match result, left by a club member. Like ChallengeRecord, the
//  author is a real account holder, not a roster Player —
//  authorParticipantId is an `auth.uid()` string, and the display name is
//  snapshotted at author time so the reaction still renders even if the
//  reader's device never re-fetches the club's member list.
//
//  Reactions link to their match by plain `matchId` (the repo's uniform
//  flat id-link pattern), club-scoped only — there is no personal/KV-store
//  fallback (see AppStore.saveReactions). When a match or club is deleted,
//  its reactions are deliberately NOT purged: they become invisible (every
//  read joins on clubId + matchId) and the club's own delete cascades the
//  server copy (on delete cascade) — the same orphan semantics
//  ChallengeRecord uses.
//

import Foundation

public struct ReactionRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let clubId: UUID
    public let matchId: UUID
    public let authorParticipantId: String
    public let authorDisplayName: String
    public let kind: Kind
    public let content: String
    public let createdDate: Date

    /// One record type carries both flavors; `kind` says how to read
    /// `content` — an emoji character, or free-form comment text.
    public enum Kind: String, Codable, Equatable {
        case emoji, comment
    }

    public init(
        id: UUID = UUID(),
        clubId: UUID,
        matchId: UUID,
        authorParticipantId: String,
        authorDisplayName: String,
        kind: Kind,
        content: String,
        createdDate: Date = Date()
    ) {
        self.id = id
        self.clubId = clubId
        self.matchId = matchId
        self.authorParticipantId = authorParticipantId
        self.authorDisplayName = authorDisplayName
        self.kind = kind
        self.content = content
        self.createdDate = createdDate
    }
}
