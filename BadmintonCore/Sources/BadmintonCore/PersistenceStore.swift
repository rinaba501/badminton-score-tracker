//
//  PersistenceStore.swift
//  BadmintonCore
//
//  Centralized JSON encode/decode for the values persisted in @AppStorage.
//  The roster ([Player]) and match history ([MatchRecord]) are stored as
//  JSON-encoded Data. Keeping the (de)serialization in one place means a
//  schema or encoding change only has to be made here, instead of at every
//  view that reads or writes those blobs.
//

import Foundation

private let currentSchemaVersion = 1

/// Decodes to `nil` instead of throwing, so a single malformed element
/// embedded in an array doesn't abort decoding of its siblings.
private struct FailableDecodable<Base: Decodable>: Decodable {
    let base: Base?
    init(from decoder: Decoder) throws { base = try? Base(from: decoder) }
}

/// `{"schemaVersion": N, "records": [...]}` — the versioned wrapper around
/// what used to be a bare JSON array. `records` decodes tolerantly: a
/// corrupt element is dropped rather than failing the whole array.
private struct Envelope<T: Codable>: Codable {
    let schemaVersion: Int
    let records: [T]
    enum CodingKeys: String, CodingKey { case schemaVersion, records }

    init(schemaVersion: Int, records: [T]) {
        self.schemaVersion = schemaVersion
        self.records = records
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        records = try container.decode([FailableDecodable<T>].self, forKey: .records).compactMap(\.base)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(records, forKey: .records)
    }
}

/// Tries the current envelope format first, then falls back to the legacy
/// (implicit schema version 0) bare array. Tolerant per record either way.
private func decodeTolerant<T: Codable>(_ type: T.Type, from data: Data) -> [T] {
    if let envelope = try? JSONDecoder().decode(Envelope<T>.self, from: data) {
        return envelope.records
    }
    if let legacy = try? JSONDecoder().decode([FailableDecodable<T>].self, from: data) {
        return legacy.compactMap(\.base)
    }
    return []
}

// `.sortedKeys` makes the output byte-deterministic for identical content —
// JSONEncoder's default key order is otherwise unspecified across separate
// encode() calls, which would make `migratedData`'s byte-equality no-op
// check (and any other Data-diffing) unreliable.
private func encodeEnvelope<T: Codable>(_ records: [T]) -> Data? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    return try? encoder.encode(Envelope(schemaVersion: currentSchemaVersion, records: records))
}

public enum PersistenceStore {

    // MARK: - Roster ([Player])

    /// Decode the player roster, returning an empty array if the data is
    /// missing or corrupt. Understands both the current versioned envelope
    /// and the legacy bare-array format; a single corrupt record does not
    /// drop the rest of the roster.
    public static func decodeRoster(_ data: Data) -> [Player] {
        decodeTolerant(Player.self, from: data)
    }

    /// Encode the player roster for storage (as the current versioned
    /// envelope), or `nil` if encoding fails.
    public static func encodeRoster(_ players: [Player]) -> Data? {
        encodeEnvelope(players)
    }

    // MARK: - History ([MatchRecord])

    /// Decode the match history, returning an empty array if the data is
    /// missing or corrupt. Understands both the current versioned envelope
    /// and the legacy bare-array format; a single corrupt record does not
    /// drop the rest of the history.
    public static func decodeHistory(_ data: Data) -> [MatchRecord] {
        decodeTolerant(MatchRecord.self, from: data)
    }

    /// Encode the match history for storage (as the current versioned
    /// envelope), or `nil` if encoding fails.
    public static func encodeHistory(_ records: [MatchRecord]) -> Data? {
        encodeEnvelope(records)
    }

    // MARK: - Migration

    /// Returns upgraded roster `Data` if `data` isn't already the current
    /// envelope format, or `nil` if no migration is needed. Called at launch
    /// (see `AppStore.runMigrations()`) so storage converges on the current
    /// format without waiting for the next save.
    public static func migratedRosterData(from data: Data) -> Data? {
        migratedData(Player.self, from: data)
    }

    /// Returns upgraded history `Data` if `data` isn't already the current
    /// envelope format, or `nil` if no migration is needed.
    public static func migratedHistoryData(from data: Data) -> Data? {
        migratedData(MatchRecord.self, from: data)
    }

    private static func migratedData<T: Codable>(_ type: T.Type, from data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let records = decodeTolerant(T.self, from: data)
        guard let migrated = encodeEnvelope(records), migrated != data else { return nil }
        return migrated
    }

    /// Merge two match-history lists by record `id` (union), sorted
    /// chronologically. `a`'s copy wins when both sides have the same id
    /// (so local edits like a name-propagation rename stick), and ids present
    /// in only one side are carried over — this is a safe union for adding
    /// matches recorded on either device. It can only grow, never shrink, so
    /// it must NOT be used to sync an intentional deletion (see
    /// `isHistoryShrink`) — merging a shrunk list back against an
    /// unshrunk one would silently resurrect what was just deleted.
    public static func mergeHistory(_ a: [MatchRecord], _ b: [MatchRecord]) -> [MatchRecord] {
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
    public static func isHistoryShrink(from oldRecords: [MatchRecord], to newRecords: [MatchRecord]) -> Bool {
        let oldIds = Set(oldRecords.map(\.id))
        let newIds = Set(newRecords.map(\.id))
        return newIds != oldIds && newIds.isSubset(of: oldIds)
    }

    // MARK: - iCloud KV-store quota

    /// `NSUbiquitousKeyValueStore` caps at ~1 MB total / 1 MB per value. Warn
    /// well before that ceiling rather than discovering it via a silently
    /// dropped write.
    public static let iCloudQuotaWarningThresholdBytes = 900_000

    /// True once `data` (the encoded payload about to be pushed to the KV
    /// store) has crossed the warning threshold.
    public static func exceedsICloudQuotaWarningThreshold(_ data: Data) -> Bool {
        data.count > iCloudQuotaWarningThresholdBytes
    }
}
