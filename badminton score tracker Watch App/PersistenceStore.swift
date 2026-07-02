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
    /// chronologically. Match records are immutable and append-only, so a
    /// same-id record in both lists is the same match — this is a safe union
    /// that never drops a match. Used by iCloud sync instead of overwriting
    /// one device's history with another's (last-write-wins).
    static func mergeHistory(_ a: [MatchRecord], _ b: [MatchRecord]) -> [MatchRecord] {
        var byId: [UUID: MatchRecord] = [:]
        for record in a { byId[record.id] = record }
        for record in b where byId[record.id] == nil { byId[record.id] = record }
        return byId.values.sorted { $0.date < $1.date }
    }
}
