//
//  Club.swift
//  BadmintonCore
//
//  Roadmap Phase 5b: a named local grouping for players/history — the
//  precursor to real cross-person sharing. A Club is intentionally minimal
//  here (no membership list): it only becomes an actual shared group once
//  Phase 5c wires it to a CloudKit CKShare zone. Until then it's just a tag
//  `Player.clubId`/`MatchRecord.clubId` can point at; `nil` on either means
//  "personal" (today's behavior, unchanged) — see the local-first invariant
//  in ROADMAP.md's Phase 5 section.
//

import Foundation

public struct Club: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public let createdDate: Date
    public var ownerRecordName: String?
    /// Roadmap Phase 5 backlog (#160): gate matches recorded into this club
    /// behind a confirm/decline step before they count toward standings.
    /// `Optional` (rather than a defaulted non-optional `Bool`, as elsewhere
    /// in this codebase) because `Club` has no custom Codable init — a plain
    /// synthesized `Decodable` requires the key to be present, so an
    /// `Optional` is what lets pre-existing persisted Club JSON keep
    /// decoding unchanged. `nil` means off, same as `false`.
    public var requireMatchConfirmation: Bool?

    public init(
        id: UUID = UUID(),
        name: String,
        createdDate: Date = Date(),
        ownerRecordName: String? = nil,
        requireMatchConfirmation: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.createdDate = createdDate
        self.ownerRecordName = ownerRecordName
        self.requireMatchConfirmation = requireMatchConfirmation
    }
}
