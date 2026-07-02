//
//  PersistenceStore.swift
//  badminton score tracker Watch App
//
//  Centralized JSON encode/decode for the values persisted in @AppStorage.
//  The roster ([Player]) and match history ([MatchRecord]) are stored as
//  JSON-encoded Data. Keeping the (de)serialization in one place means a
//  schema or encoding change only has to be made here, instead of at every
//  view that reads or writes those blobs.
//

import Foundation

enum PersistenceStore {

    // MARK: - Roster ([Player])

    /// Decode the player roster, returning an empty array if the data is
    /// missing or corrupt.
    static func decodeRoster(_ data: Data) -> [Player] {
        (try? JSONDecoder().decode([Player].self, from: data)) ?? []
    }

    /// Encode the player roster for storage, or `nil` if encoding fails.
    static func encodeRoster(_ players: [Player]) -> Data? {
        try? JSONEncoder().encode(players)
    }

    // MARK: - History ([MatchRecord])

    /// Decode the match history, returning an empty array if the data is
    /// missing or corrupt.
    static func decodeHistory(_ data: Data) -> [MatchRecord] {
        (try? JSONDecoder().decode([MatchRecord].self, from: data)) ?? []
    }

    /// Encode the match history for storage, or `nil` if encoding fails.
    static func encodeHistory(_ records: [MatchRecord]) -> Data? {
        try? JSONEncoder().encode(records)
    }

    /// Merge two match-history lists by record `id` (union), sorted
    /// chronologically. `a`'s copy wins when both sides have the same id
    /// (so local edits like a name-propagation rename stick), and ids present
    /// in only one side are carried over — this is a safe union for adding
    /// matches recorded on either device. It can only grow, never shrink, so
    /// it must NOT be used to sync an intentional deletion (see
    /// `isHistoryShrink`) — merging a shrunk list back against an
    /// unshrunk one would silently resurrect what was just deleted.
    static func mergeHistory(_ a: [MatchRecord], _ b: [MatchRecord]) -> [MatchRecord] {
        var byId: [UUID: MatchRecord] = [:]
        for record in a { byId[record.id] = record }
        for record in b where byId[record.id] == nil { byId[record.id] = record }
        return byId.values.sorted { $0.date < $1.date }
    }

    /// True when `newRecords` removes at least one record present in
    /// `oldRecords` and adds none — i.e. this write is an intentional
    /// deletion (single record or "clear all"), not an append or an
    /// in-place edit (e.g. a rename that keeps the same set of ids).
    /// Callers use this to decide whether a history write is safe to
    /// reconcile with iCloud via `mergeHistory` (grows/edits) or must be
    /// pushed as an authoritative overwrite instead (shrinks) — merging a
    /// deletion would silently undo it, since a union can only grow.
    static func isHistoryShrink(from oldRecords: [MatchRecord], to newRecords: [MatchRecord]) -> Bool {
        let oldIds = Set(oldRecords.map(\.id))
        let newIds = Set(newRecords.map(\.id))
        return newIds != oldIds && newIds.isSubset(of: oldIds)
    }
}
