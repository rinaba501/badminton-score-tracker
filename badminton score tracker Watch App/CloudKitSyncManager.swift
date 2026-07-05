//
//  CloudKitSyncManager.swift
//  badminton score tracker Watch App
//
//  Phase 4 (#109): syncs match history + roster through the CloudKit private
//  database via CKSyncEngine — one CKRecord per MatchRecord / Player, keyed by
//  the model's UUID, with a single opaque JSON `payload` field (see
//  PersistenceStore.encodeRecord). Real per-record deletion replaces the
//  KV-store single-blob merge + isHistoryShrink heuristic, so a cleared match
//  can't be resurrected by a union.
//
//  SHIPS INERT: nothing here runs unless `cloudKitSyncEnabled` is true (default
//  false). While disabled, CloudKitSyncManager.shared is never instantiated,
//  no CKContainer is touched, and CloudSyncManager keeps syncing everything via
//  the KV store exactly as before — so the app needs no CloudKit entitlement
//  until the flag is deliberately flipped on (after the two-device test).
//
//  Correctness here cannot be proven by CI or the simulator; the two-device
//  iCloud test in the PR is the real gate. Per CLAUDE.md this file, like
//  CloudSyncManager/AppStore, is a high-risk area — change it in plan mode.
//

import Foundation
import CloudKit
import os
import BadmintonCore

@MainActor
final class CloudKitSyncManager {
    static let shared = CloudKitSyncManager()

    /// Whether CloudKit owns history/roster sync. Default false: the code ships
    /// inert and the KV store keeps handling everything until this is flipped.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: AppStorageKeys.cloudKitSyncEnabled) as? Bool ?? false
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "badminton-score-tracker", category: "CloudKitSync")

    private static let containerID = "iCloud.ritsuma.badminton-score-tracker"
    private static let zoneName = "BadmintonZone"
    private static let matchType = "MatchRecord"
    private static let playerType = "Player"
    private static let payloadField = "payload"

    private lazy var container = CKContainer(identifier: Self.containerID)
    private lazy var database = container.privateCloudDatabase
    private let zone = CKRecordZone(zoneName: zoneName)

    private var syncEngine: CKSyncEngine?

    /// recordName -> encoded CKRecord system fields (change tag). Persisted so a
    /// save of an existing record carries the server's change tag and reads as
    /// an update, not a conflict. Loaded on start, written on every change.
    private var recordMetadata: [String: Data] = [:]

    /// Set while a first-launch migration upload is pending, so the durable
    /// `didMigrateToCloudKit` flag is only set once the engine state (with the
    /// migration's pending changes) has actually been persisted.
    private var migrationPending = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        loadMetadata()
        let stateSerialization = loadState()
        let configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateSerialization,
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        syncEngine = engine

        if !UserDefaults.standard.bool(forKey: AppStorageKeys.didMigrateToCloudKit) {
            migrateLocalDataToCloud(using: engine)
        }
    }

    // Enqueue every existing local record for upload on first launch. Idempotent
    // (record name == UUID), so a re-run just re-saves the same records.
    private func migrateLocalDataToCloud(using engine: CKSyncEngine) {
        engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        migrationPending = true
        enqueueHistoryChanges(upsertedIds: AppStore.shared.history.map(\.id), deletedIds: [])
        enqueueRosterChanges(upsertedIds: AppStore.shared.roster.map(\.id), deletedIds: [])
    }

    // MARK: - Write path (called by AppStore)

    func enqueueHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID]) {
        enqueue(upsertedIds: upsertedIds, deletedIds: deletedIds)
    }

    func enqueueRosterChanges(upsertedIds: [UUID], deletedIds: [UUID]) {
        enqueue(upsertedIds: upsertedIds, deletedIds: deletedIds)
    }

    private func enqueue(upsertedIds: [UUID], deletedIds: [UUID]) {
        guard let syncEngine else { return }
        let changes = upsertedIds.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(recordID(for: $0)) }
            + deletedIds.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(recordID(for: $0)) }
        guard !changes.isEmpty else { return }
        syncEngine.state.add(pendingRecordZoneChanges: changes)
    }

    // MARK: - Record identity / materialization

    private func recordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.uuidString, zoneID: zone.zoneID)
    }

    // Build the CKRecord to upload for a pending save. Starts from stored system
    // fields (so an update carries the right change tag); returns nil if the
    // model was deleted between enqueue and send (the engine then drops it).
    private func materializeRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let uuid = UUID(uuidString: recordID.recordName) else { return nil }

        if let match = AppStore.shared.history.first(where: { $0.id == uuid }) {
            guard let payload = PersistenceStore.encodeRecord(match) else { return nil }
            return record(for: recordID, type: Self.matchType, payload: payload)
        }
        if let player = AppStore.shared.roster.first(where: { $0.id == uuid }) {
            guard let payload = PersistenceStore.encodePlayer(player) else { return nil }
            return record(for: recordID, type: Self.playerType, payload: payload)
        }
        return nil
    }

    private func record(for recordID: CKRecord.ID, type: String, payload: Data) -> CKRecord {
        let record = storedRecord(for: recordID.recordName) ?? CKRecord(recordType: type, recordID: recordID)
        record[Self.payloadField] = payload as CKRecordValue
        return record
    }

    // MARK: - System-fields metadata store

    private func loadMetadata() {
        if let data = UserDefaults.standard.data(forKey: AppStorageKeys.ckRecordMetadata),
           let map = try? JSONDecoder().decode([String: Data].self, from: data) {
            recordMetadata = map
        }
    }

    private func persistMetadata() {
        if let data = try? JSONEncoder().encode(recordMetadata) {
            UserDefaults.standard.set(data, forKey: AppStorageKeys.ckRecordMetadata)
        }
    }

    private func remember(_ record: CKRecord) {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        recordMetadata[record.recordID.recordName] = coder.encodedData
        persistMetadata()
    }

    private func forget(_ recordName: String) {
        recordMetadata[recordName] = nil
        persistMetadata()
    }

    private func storedRecord(for recordName: String) -> CKRecord? {
        guard let data = recordMetadata[recordName],
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = true
        let record = CKRecord(coder: unarchiver)
        unarchiver.finishDecoding()
        return record
    }

    // MARK: - Engine state persistence

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: AppStorageKeys.ckSyncEngineState) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func persistState(_ serialization: CKSyncEngine.State.Serialization) {
        if let data = try? JSONEncoder().encode(serialization) {
            UserDefaults.standard.set(data, forKey: AppStorageKeys.ckSyncEngineState)
        }
        // The migration's pending changes are now durable — safe to record that
        // the one-time upload has been scheduled so it won't run again.
        if migrationPending {
            migrationPending = false
            UserDefaults.standard.set(true, forKey: AppStorageKeys.didMigrateToCloudKit)
        }
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudKitSyncManager: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            persistState(update.stateSerialization)

        case .accountChange(let change):
            handleAccountChange(change)

        case .fetchedRecordZoneChanges(let changes):
            applyFetched(changes)

        case .sentRecordZoneChanges(let sent):
            handleSent(sent)

        case .sentDatabaseChanges, .fetchedDatabaseChanges,
             .willFetchChanges, .didFetchChanges, .willSendChanges, .didSendChanges:
            break

        @unknown default:
            logger.log("Unhandled CKSyncEngine event: \(String(describing: event))")
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { [weak self] recordID in
            await self?.materializeRecord(for: recordID)
        }
    }

    // MARK: Event handling

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange) {
        switch change.changeType {
        case .signIn:
            // New account: re-seed its private zone with our local data.
            guard let engine = syncEngine else { return }
            migrateLocalDataToCloud(using: engine)
        case .signOut, .switchAccounts:
            // Drop CloudKit-derived bookkeeping; local UserDefaults cache stays
            // as the offline source of truth for reads.
            recordMetadata = [:]
            persistMetadata()
            UserDefaults.standard.removeObject(forKey: AppStorageKeys.ckSyncEngineState)
            UserDefaults.standard.set(false, forKey: AppStorageKeys.didMigrateToCloudKit)
        @unknown default:
            break
        }
    }

    private func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        var upsertedMatches: [MatchRecord] = []
        var upsertedPlayers: [Player] = []
        for modification in changes.modifications {
            let record = modification.record
            remember(record)
            guard let payload = record[Self.payloadField] as? Data else { continue }
            switch record.recordType {
            case Self.matchType:
                if let match = PersistenceStore.decodeRecord(payload) { upsertedMatches.append(match) }
            case Self.playerType:
                if let player = PersistenceStore.decodePlayer(payload) { upsertedPlayers.append(player) }
            default:
                break
            }
        }

        var deletedMatchIds: [UUID] = []
        var deletedPlayerIds: [UUID] = []
        for deletion in changes.deletions {
            forget(deletion.recordID.recordName)
            guard let uuid = UUID(uuidString: deletion.recordID.recordName) else { continue }
            switch deletion.recordType {
            case Self.matchType: deletedMatchIds.append(uuid)
            case Self.playerType: deletedPlayerIds.append(uuid)
            default: break
            }
        }

        if !upsertedMatches.isEmpty || !upsertedPlayers.isEmpty {
            AppStore.shared.applyRemoteUpsert(records: upsertedMatches, players: upsertedPlayers)
        }
        if !deletedMatchIds.isEmpty || !deletedPlayerIds.isEmpty {
            AppStore.shared.applyRemoteDeletions(recordIds: deletedMatchIds, playerIds: deletedPlayerIds)
        }
    }

    private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges) {
        for saved in sent.savedRecords {
            remember(saved)
        }
        for failure in sent.failedRecordSaves {
            handleFailedSave(failure)
        }
    }

    private func handleFailedSave(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave) {
        let error = failure.error
        let recordID = failure.record.recordID
        switch error.code {
        case .serverRecordChanged:
            guard let serverRecord = error.serverRecord else { return }
            remember(serverRecord)
            // Our resolveConflict is per-record LWW with delete-wins; on a plain
            // edit conflict we yield to the server copy (it reached the server
            // last). Deletions aren't routed here — they go through deleteRecord.
            if PersistenceStore.resolveConflict(localIntendedDelete: false) == .takeServer,
               let payload = serverRecord[Self.payloadField] as? Data {
                applyServerRecord(serverRecord, payload: payload)
            }
        case .zoneNotFound, .userDeletedZone:
            // Zone vanished (e.g. user wiped iCloud data): recreate it and
            // re-upload everything from the local cache.
            guard let engine = syncEngine else { return }
            engine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
            enqueueHistoryChanges(upsertedIds: AppStore.shared.history.map(\.id), deletedIds: [])
            enqueueRosterChanges(upsertedIds: AppStore.shared.roster.map(\.id), deletedIds: [])
        case .unknownItem:
            forget(recordID.recordName)
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            break // CKSyncEngine retries these automatically.
        default:
            logger.error("Unhandled record-save failure \(error.code.rawValue) for \(recordID.recordName)")
        }
    }

    private func applyServerRecord(_ record: CKRecord, payload: Data) {
        switch record.recordType {
        case Self.matchType:
            if let match = PersistenceStore.decodeRecord(payload) {
                AppStore.shared.applyRemoteUpsert(records: [match], players: [])
            }
        case Self.playerType:
            if let player = PersistenceStore.decodePlayer(payload) {
                AppStore.shared.applyRemoteUpsert(records: [], players: [player])
            }
        default:
            break
        }
    }
}
