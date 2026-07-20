//
//  Club.swift
//  BadmintonCore
//
//  A named grouping for players/history. This struct is intentionally
//  minimal (no membership list of its own) — the actual membership lives in
//  the `club_members` table (owner determined by this row's `owner_id`,
//  read via `SupabaseSyncManager.fetchClubMembers`). Here it's just a tag
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
    /// Roadmap Phase 5 backlog (#163): an optional time-boxed window that
    /// restricts Standings (only) to matches played within it — the
    /// Activity Feed stays a full chronological log regardless. `nil`
    /// `seasonStartDate` means "no season set" (today's all-time behavior,
    /// unchanged); `seasonEndDate` is independently optional, so a season
    /// can be open-ended. Both `Optional` for the same synthesized-Codable
    /// reason as `requireMatchConfirmation` above.
    public var seasonStartDate: Date?
    public var seasonEndDate: Date?
    /// Turn Standings tracking off for this club entirely (and, since Season
    /// only exists to feed Standings, hides the Season section too) — for
    /// clubs used purely for score-tracking/history with no competitive
    /// pressure. INVERTED nil-semantics vs. every other Optional Bool above:
    /// here `nil` means ON (true) — existing clubs must keep showing
    /// Standings unchanged, so absent/default resolves to "tracking", not
    /// "off". `false` is the only way to actually turn it off.
    public var trackStandings: Bool?

    public init(
        id: UUID = UUID(),
        name: String,
        createdDate: Date = Date(),
        ownerRecordName: String? = nil,
        requireMatchConfirmation: Bool? = nil,
        seasonStartDate: Date? = nil,
        seasonEndDate: Date? = nil,
        trackStandings: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.createdDate = createdDate
        self.ownerRecordName = ownerRecordName
        self.requireMatchConfirmation = requireMatchConfirmation
        self.seasonStartDate = seasonStartDate
        self.seasonEndDate = seasonEndDate
        self.trackStandings = trackStandings
    }
}

extension Club {
    /// True when `date` falls within this club's season window. Always true
    /// when no season is set. Both bounds are inclusive; a nil end date
    /// means open-ended. Filters Standings only — the Activity Feed
    /// intentionally ignores this (#163).
    public func isDateInSeason(_ date: Date) -> Bool {
        guard let seasonStartDate else { return true }
        if date < seasonStartDate { return false }
        if let seasonEndDate, date > seasonEndDate { return false }
        return true
    }
}
