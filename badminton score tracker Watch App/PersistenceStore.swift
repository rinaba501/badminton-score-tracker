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
}
