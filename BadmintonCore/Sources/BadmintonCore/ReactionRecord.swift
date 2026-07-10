//
//  ReactionRecord.swift
//  BadmintonCore
//
//  Roadmap Phase 5 backlog (#164): an emoji reaction or one-line comment on a
//  club match result, left by a member of the club's CKShare. Like
//  ChallengeRecord, the author is a real CKShare participant, not a roster
//  Player — authorParticipantId is a
//  CKShare.Participant.userIdentity.userRecordID.recordName, and the display
//  name is snapshotted at author time so the reaction still renders even if
//  the reader's device never re-fetches the CKShare's participant list.
//
//  Reactions link to their match by plain `matchId` (the repo's uniform flat
//  id-link pattern — no CKRecord parent references), and live in the club's
//  CloudKit zone only; there is no KV-store fallback (see
//  AppStore.saveReactions). When a match or club is deleted, its reactions are
//  deliberately NOT purged: they become invisible (every read joins on
//  clubId + matchId) and the club's zone deletion cleans up the server copy —
//  the same orphan semantics ChallengeRecord uses.
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
