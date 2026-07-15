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

    // MARK: - Clubs ([Club]) — Roadmap Phase 5b, local only (no CloudKit yet)

    /// Decode the club list, returning an empty array if the data is missing
    /// or corrupt. Same envelope/tolerance contract as `decodeRoster`.
    public static func decodeClubs(_ data: Data) -> [Club] {
        decodeTolerant(Club.self, from: data)
    }

    /// Encode the club list for storage (as the current versioned envelope),
    /// or `nil` if encoding fails.
    public static func encodeClubs(_ clubs: [Club]) -> Data? {
        encodeEnvelope(clubs)
    }

    // MARK: - Challenges ([ChallengeRecord]) — Roadmap Phase 5 backlog (#162)

    /// Decode the challenge list, returning an empty array if the data is
    /// missing or corrupt. Same envelope/tolerance contract as `decodeRoster`.
    public static func decodeChallenges(_ data: Data) -> [ChallengeRecord] {
        decodeTolerant(ChallengeRecord.self, from: data)
    }

    /// Encode the challenge list for storage (as the current versioned
    /// envelope), or `nil` if encoding fails.
    public static func encodeChallenges(_ challenges: [ChallengeRecord]) -> Data? {
        encodeEnvelope(challenges)
    }

    // MARK: - Reactions ([ReactionRecord]) — Roadmap Phase 5 backlog (#164)

    /// Decode the reaction list, returning an empty array if the data is
    /// missing or corrupt. Same envelope/tolerance contract as `decodeRoster`.
    public static func decodeReactions(_ data: Data) -> [ReactionRecord] {
        decodeTolerant(ReactionRecord.self, from: data)
    }

    /// Encode the reaction list for storage (as the current versioned
    /// envelope), or `nil` if encoding fails.
    public static func encodeReactions(_ reactions: [ReactionRecord]) -> Data? {
        encodeEnvelope(reactions)
    }

    // MARK: - Friend requests ([FriendRequest]) — Friends v1 (graph-only)

    /// Decode the friend-request list, returning an empty array if the data
    /// is missing or corrupt. Same envelope/tolerance contract as
    /// `decodeRoster`.
    public static func decodeFriendRequests(_ data: Data) -> [FriendRequest] {
        decodeTolerant(FriendRequest.self, from: data)
    }

    /// Encode the friend-request list for storage (as the current versioned
    /// envelope), or `nil` if encoding fails.
    public static func encodeFriendRequests(_ requests: [FriendRequest]) -> Data? {
        encodeEnvelope(requests)
    }

    // MARK: - Friend activity ([FriendHistorySnapshot]) — friends' shared
    // roster/history, local cache only. Never sent to CloudKit as its own
    // payload type: it's an aggregate of Player/MatchRecord CKRecords fetched
    // from a friend's "FriendsHistory" zone (see CloudKitSyncManager), kept
    // local so the Friend Activity view has something to render offline.

    /// Decode the friend-activity cache, returning an empty array if the
    /// data is missing or corrupt. Same envelope/tolerance contract as
    /// `decodeRoster`.
    public static func decodeFriendActivity(_ data: Data) -> [FriendHistorySnapshot] {
        decodeTolerant(FriendHistorySnapshot.self, from: data)
    }

    /// Encode the friend-activity cache for storage (as the current
    /// versioned envelope), or `nil` if encoding fails.
    public static func encodeFriendActivity(_ snapshots: [FriendHistorySnapshot]) -> Data? {
        encodeEnvelope(snapshots)
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

    // MARK: - Single-record codecs (CloudKit)

    // Each CloudKit CKRecord stores one model as a JSON `payload` field. These
    // wrap a single record in the same versioned, byte-deterministic envelope
    // the array codecs use, so schema versioning and per-record tolerant
    // decoding carry over unchanged — CloudKit stays agnostic about the model
    // shape. `decode*` returns nil (never throws/crashes) on empty or corrupt
    // payload, so one bad CKRecord can't take down a whole zone fetch.

    /// Encode a single match record as a CloudKit payload, or `nil` on failure.
    public static func encodeRecord(_ record: MatchRecord) -> Data? {
        encodeEnvelope([record])
    }

    /// Decode a single match record from a CloudKit payload, or `nil` if the
    /// payload is empty or unreadable.
    public static func decodeRecord(_ data: Data) -> MatchRecord? {
        decodeTolerant(MatchRecord.self, from: data).first
    }

    /// Encode a single roster player as a CloudKit payload, or `nil` on failure.
    public static func encodePlayer(_ player: Player) -> Data? {
        encodeEnvelope([player])
    }

    /// Decode a single roster player from a CloudKit payload, or `nil` if the
    /// payload is empty or unreadable.
    public static func decodePlayer(_ data: Data) -> Player? {
        decodeTolerant(Player.self, from: data).first
    }

    /// Encode a single club as a CloudKit payload, or `nil` on failure.
    public static func encodeClub(_ club: Club) -> Data? {
        encodeEnvelope([club])
    }

    /// Decode a single club from a CloudKit payload, or `nil` if the
    /// payload is empty or unreadable.
    public static func decodeClub(_ data: Data) -> Club? {
        decodeTolerant(Club.self, from: data).first
    }

    /// Encode a single challenge as a CloudKit payload, or `nil` on failure.
    public static func encodeChallenge(_ challenge: ChallengeRecord) -> Data? {
        encodeEnvelope([challenge])
    }

    /// Decode a single challenge from a CloudKit payload, or `nil` if the
    /// payload is empty or unreadable.
    public static func decodeChallenge(_ data: Data) -> ChallengeRecord? {
        decodeTolerant(ChallengeRecord.self, from: data).first
    }

    /// Encode a single reaction as a CloudKit payload, or `nil` on failure.
    public static func encodeReaction(_ reaction: ReactionRecord) -> Data? {
        encodeEnvelope([reaction])
    }

    /// Decode a single reaction from a CloudKit payload, or `nil` if the
    /// payload is empty or unreadable.
    public static func decodeReaction(_ data: Data) -> ReactionRecord? {
        decodeTolerant(ReactionRecord.self, from: data).first
    }

    /// Encode a single friend request as a CloudKit payload, or `nil` on
    /// failure.
    public static func encodeFriendRequest(_ request: FriendRequest) -> Data? {
        encodeEnvelope([request])
    }

    /// Decode a single friend request from a CloudKit payload, or `nil` if
    /// the payload is empty or unreadable.
    public static func decodeFriendRequest(_ data: Data) -> FriendRequest? {
        decodeTolerant(FriendRequest.self, from: data).first
    }

    /// Encode a single friend profile as a CloudKit payload, or `nil` on
    /// failure. There is no array-list codec for profiles — unlike
    /// challenges/reactions/friend requests, profiles aren't cached locally
    /// as a synced collection; they're fetched on demand per participant
    /// (see CloudKitSyncManager.fetchProfile).
    public static func encodeFriendProfile(_ profile: FriendProfile) -> Data? {
        encodeEnvelope([profile])
    }

    /// Decode a single friend profile from a CloudKit payload, or `nil` if
    /// the payload is empty or unreadable.
    public static func decodeFriendProfile(_ data: Data) -> FriendProfile? {
        decodeTolerant(FriendProfile.self, from: data).first
    }

    /// Encode a settings snapshot as a CloudKit payload, or `nil` on failure.
    public static func encodeSettingsSnapshot(_ snapshot: SettingsSnapshot) -> Data? {
        encodeEnvelope([snapshot])
    }

    /// Decode a settings snapshot from a CloudKit payload, or `nil` if the
    /// payload is empty or unreadable.
    public static func decodeSettingsSnapshot(_ data: Data) -> SettingsSnapshot? {
        decodeTolerant(SettingsSnapshot.self, from: data).first
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

    // MARK: - Record diffing (CloudKit)

    /// The per-record changes between two snapshots of a collection, keyed by
    /// `id`. Drives CloudKit's `.saveRecord` / `.deleteRecord` pending changes:
    /// exact upserts and real deletions replace the whole-blob merge, so a
    /// deletion is an explicit server tombstone that can't be resurrected by a
    /// union (the bug class that hit `mergeHistory` + clear-history).
    public struct RecordDiff: Equatable {
        public let upsertedIds: [UUID]
        public let deletedIds: [UUID]
        public init(upsertedIds: [UUID], deletedIds: [UUID]) {
            self.upsertedIds = upsertedIds
            self.deletedIds = deletedIds
        }
    }

    /// Diff two `Identifiable & Equatable` snapshots into upserts and deletes.
    /// `upsertedIds` = ids new to `new`, plus ids whose element changed in
    /// place (an in-place rename mutates fields but keeps the id — `Equatable`
    /// catches it). `deletedIds` = ids present in `old` but absent from `new`.
    /// Order of `upsertedIds` follows `new`; `deletedIds` follows `old`.
    private static func diff<T: Identifiable & Equatable>(from old: [T], to new: [T]) -> RecordDiff where T.ID == UUID {
        let oldById = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newIds = Set(new.map(\.id))
        let upserted = new.filter { oldById[$0.id] != $0 }.map(\.id)
        // Dedupe defensively: a well-formed collection never repeats an id,
        // but corrupt data shouldn't be able to enqueue the same delete twice.
        var seenDeleted = Set<UUID>()
        let deleted = old.compactMap { record -> UUID? in
            guard !newIds.contains(record.id), seenDeleted.insert(record.id).inserted else { return nil }
            return record.id
        }
        return RecordDiff(upsertedIds: upserted, deletedIds: deleted)
    }

    /// Upserts/deletes to sync when match history changes from `old` to `new`.
    public static func diffHistory(from old: [MatchRecord], to new: [MatchRecord]) -> RecordDiff {
        diff(from: old, to: new)
    }

    /// Upserts/deletes to sync when the roster changes from `old` to `new`.
    public static func diffRoster(from old: [Player], to new: [Player]) -> RecordDiff {
        diff(from: old, to: new)
    }

    /// Upserts/deletes to sync when the clubs list changes from `old` to `new`.
    public static func diffClubs(from old: [Club], to new: [Club]) -> RecordDiff {
        diff(from: old, to: new)
    }

    /// Upserts/deletes to sync when the challenges list changes from `old` to `new`.
    public static func diffChallenges(from old: [ChallengeRecord], to new: [ChallengeRecord]) -> RecordDiff {
        diff(from: old, to: new)
    }

    /// Upserts/deletes to sync when the reactions list changes from `old` to `new`.
    public static func diffReactions(from old: [ReactionRecord], to new: [ReactionRecord]) -> RecordDiff {
        diff(from: old, to: new)
    }

    /// Upserts/deletes to sync when the friend-requests list changes from `old` to `new`.
    public static func diffFriendRequests(from old: [FriendRequest], to new: [FriendRequest]) -> RecordDiff {
        diff(from: old, to: new)
    }

    // MARK: - Conflict resolution (CloudKit)

    /// How to resolve a CloudKit `.serverRecordChanged` conflict on one record.
    public enum Resolution: Equatable {
        /// Accept the server's record into the local cache (last-writer-wins).
        case takeServer
        /// Re-apply our pending deletion against the fresh server record.
        case keepDeletion
    }

    /// Per-record last-writer-wins, with one deliberate asymmetry: a local
    /// *deletion* always wins over a concurrent server edit, so a user who
    /// cleared history is never overruled by someone else's in-place change.
    /// Everything else takes the server copy (the last write to reach the
    /// server). Note this must NOT tie-break on `MatchRecord.date` — that is
    /// match-completion time and does not change on an in-place rename.
    public static func resolveConflict(localIntendedDelete: Bool) -> Resolution {
        localIntendedDelete ? .keepDeletion : .takeServer
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
