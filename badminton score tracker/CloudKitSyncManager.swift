//
//  CloudKitSyncManager.swift
//  badminton score tracker (iOS)
//
//  Phase 5c: syncs match history + roster + clubs through the CloudKit private
//  and shared databases via CKSyncEngine. Manages two sync engine instances
//  to synchronize personal data (private DB) and shared club data (shared DB).
//  Supports creating zone-wide CKShare for clubs and accepting share invitations.
//

import Foundation
import CloudKit
import os
import BadmintonCore

@MainActor
final class CloudKitSyncManager {
    static let shared = CloudKitSyncManager()

    /// Whether CloudKit owns history/roster/clubs sync.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: AppStorageKeys.cloudKitSyncEnabled) as? Bool ?? false
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "badminton-score-tracker", category: "CloudKitSync")

    private static let containerID = "iCloud.ritsuma.badminton-score-tracker"
    private static let zoneName = "BadmintonZone"
    private static let matchType = "MatchRecord"
    private static let playerType = "Player"
    private static let clubType = "Club"
    private static let challengeType = "Challenge"
    private static let payloadField = "payload"

    private lazy var container = CKContainer(identifier: Self.containerID)
    private lazy var privateDatabase = container.privateCloudDatabase
    private lazy var sharedDatabase = container.sharedCloudDatabase

    private let privateZone = CKRecordZone(zoneName: zoneName)

    private var privateSyncEngine: CKSyncEngine?
    private var sharedSyncEngine: CKSyncEngine?

    /// recordName -> encoded CKRecord system fields (change tag). Persisted so a
    /// save of an existing record carries the server's change tag and reads as
    /// an update, not a conflict.
    private var recordMetadata: [String: Data] = [:]

    /// Set while a first-launch migration upload is pending.
    private var migrationPending = false

    private init() {}

    // MARK: - Lifecycle

    func start() {
        loadMetadata()

        // 1. Initialize Private Database Sync Engine
        let privateStateSerialization = loadPrivateState()
        let privateConfig = CKSyncEngine.Configuration(
            database: privateDatabase,
            stateSerialization: privateStateSerialization,
            delegate: self
        )
        privateSyncEngine = CKSyncEngine(privateConfig)

        // 2. Initialize Shared Database Sync Engine
        let sharedStateSerialization = loadSharedState()
        let sharedConfig = CKSyncEngine.Configuration(
            database: sharedDatabase,
            stateSerialization: sharedStateSerialization,
            delegate: self
        )
        sharedSyncEngine = CKSyncEngine(sharedConfig)

        if !UserDefaults.standard.bool(forKey: AppStorageKeys.didMigrateToCloudKit) {
            if let engine = privateSyncEngine {
                migrateLocalDataToCloud(using: engine)
            }
        }
    }

    private func migrateLocalDataToCloud(using engine: CKSyncEngine) {
        engine.state.add(pendingDatabaseChanges: [.saveZone(privateZone)])
        migrationPending = true

        let personalHistory = AppStore.shared.history.filter { $0.clubId == nil }.map(\.id)
        let personalRoster = AppStore.shared.roster.filter { $0.clubId == nil }.map(\.id)

        enqueueHistoryChanges(upsertedIds: personalHistory, deletedIds: [:])
        enqueueRosterChanges(upsertedIds: personalRoster, deletedIds: [:])

        // Enqueue any local clubs as well (we own these since they are locally created)
        enqueueClubChanges(upsertedIds: AppStore.shared.clubs.map(\.id), deletedIds: [:])
    }

    // MARK: - Write paths (called by AppStore)

    func enqueueClubChanges(upsertedIds: [UUID], deletedIds: [UUID: String?]) {
        guard let privateSyncEngine, let sharedSyncEngine else { return }

        for id in upsertedIds {
            let zoneID = zoneID(for: id)
            let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)

            if zoneID.ownerName == CKCurrentUserDefaultName {
                let zone = CKRecordZone(zoneID: zoneID)
                privateSyncEngine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
                privateSyncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            } else {
                sharedSyncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        }

        for (id, owner) in deletedIds {
            let ownerName = owner ?? CKCurrentUserDefaultName
            let zoneID = CKRecordZone.ID(zoneName: "Club-\(id.uuidString)", ownerName: ownerName)
            let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)

            if zoneID.ownerName == CKCurrentUserDefaultName {
                privateSyncEngine.state.add(pendingDatabaseChanges: [.deleteZone(zoneID)])
            } else {
                sharedSyncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            }
        }
    }

    func enqueueHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID?]) {
        enqueue(upsertedIds: upsertedIds, deletedIds: deletedIds)
    }

    func enqueueRosterChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID?]) {
        enqueue(upsertedIds: upsertedIds, deletedIds: deletedIds)
    }

    /// A challenge always belongs to a club's zone (never the personal zone),
    /// so it follows the same generic per-record `enqueue` path as history/
    /// roster rather than Club's own-zone path.
    func enqueueChallengeChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID]) {
        enqueue(upsertedIds: upsertedIds, deletedIds: deletedIds.mapValues { $0 as UUID? })
    }

    private func enqueue(upsertedIds: [UUID], deletedIds: [UUID: UUID?]) {
        guard let privateSyncEngine, let sharedSyncEngine else { return }

        for id in upsertedIds {
            let clubId = clubId(for: id)
            let zoneID = zoneID(for: clubId)
            let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)

            if zoneID.ownerName == CKCurrentUserDefaultName {
                privateSyncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            } else {
                sharedSyncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        }

        for (id, clubId) in deletedIds {
            let zoneID = zoneID(for: clubId)
            let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)

            if zoneID.ownerName == CKCurrentUserDefaultName {
                privateSyncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            } else {
                sharedSyncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
            }
        }
    }

    // MARK: - Zone / Club Resolution Helpers

    private func zoneID(for clubId: UUID?) -> CKRecordZone.ID {
        guard let clubId else {
            return CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
        }
        if let club = AppStore.shared.clubs.first(where: { $0.id == clubId }),
           let owner = club.ownerRecordName {
            return CKRecordZone.ID(zoneName: "Club-\(clubId.uuidString)", ownerName: owner)
        }
        return CKRecordZone.ID(zoneName: "Club-\(clubId.uuidString)", ownerName: CKCurrentUserDefaultName)
    }

    private func clubId(for recordId: UUID) -> UUID? {
        if let match = AppStore.shared.history.first(where: { $0.id == recordId }) {
            return match.clubId
        }
        if let player = AppStore.shared.roster.first(where: { $0.id == recordId }) {
            return player.clubId
        }
        if let challenge = AppStore.shared.challenges.first(where: { $0.id == recordId }) {
            return challenge.clubId
        }
        return nil
    }

    private func clubId(from zoneID: CKRecordZone.ID) -> UUID? {
        let prefix = "Club-"
        guard zoneID.zoneName.hasPrefix(prefix) else { return nil }
        let uuidString = String(zoneID.zoneName.dropFirst(prefix.count))
        return UUID(uuidString: uuidString)
    }

    // Build the CKRecord to upload for a pending save.
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
        if let club = AppStore.shared.clubs.first(where: { $0.id == uuid }) {
            guard let payload = PersistenceStore.encodeClub(club) else { return nil }
            return record(for: recordID, type: Self.clubType, payload: payload)
        }
        if let challenge = AppStore.shared.challenges.first(where: { $0.id == uuid }) {
            guard let payload = PersistenceStore.encodeChallenge(challenge) else { return nil }
            return record(for: recordID, type: Self.challengeType, payload: payload)
        }
        return nil
    }

    private func record(for recordID: CKRecord.ID, type: String, payload: Data) -> CKRecord {
        let record = storedRecord(for: recordID.recordName) ?? CKRecord(recordType: type, recordID: recordID)
        record[Self.payloadField] = payload as CKRecordValue
        return record
    }

    // MARK: - Metadata Persistence

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

    // MARK: - SyncEngine State Persistence

    private func loadPrivateState() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: AppStorageKeys.ckSyncEngineState) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func persistPrivateState(_ serialization: CKSyncEngine.State.Serialization) {
        if let data = try? JSONEncoder().encode(serialization) {
            UserDefaults.standard.set(data, forKey: AppStorageKeys.ckSyncEngineState)
        }
        if migrationPending {
            migrationPending = false
            UserDefaults.standard.set(true, forKey: AppStorageKeys.didMigrateToCloudKit)
        }
    }

    private func loadSharedState() -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: AppStorageKeys.ckSharedSyncEngineState) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func persistSharedState(_ serialization: CKSyncEngine.State.Serialization) {
        if let data = try? JSONEncoder().encode(serialization) {
            UserDefaults.standard.set(data, forKey: AppStorageKeys.ckSharedSyncEngineState)
        }
    }

    // MARK: - Share Management

    /// Exposed for `CloudSharingView` (Phase 5e), which needs the container alongside a CKShare.
    var ckContainer: CKContainer { container }

    /// Fetches or creates the CKShare for a Club zone. Must be run on the owner's device.
    func fetchOrCreateShare(for club: Club) async throws -> CKShare {
        let zoneID = zoneID(for: club.id)
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)

        do {
            let record = try await privateDatabase.record(for: shareID)
            if let share = record as? CKShare {
                return share
            }
        } catch {
            // If share not found, create a new one. Any other error (offline,
            // not signed into iCloud, permission failure, etc.) is rethrown
            // as-is — Phase 5e's invite UI surfaces this message to the user,
            // so swallowing it here would show a misleading generic error.
            let ckError = error as? CKError
            guard ckError?.code == .unknownItem else { throw error }

            let share = CKShare(recordZoneID: zoneID)
            share.publicPermission = .readWrite
            let saved = try await privateDatabase.save(share)
            if let savedShare = saved as? CKShare {
                return savedShare
            }
        }
        throw CKError(.invalidArguments)
    }

    /// Accept a CKShare invitation metadata.
    func acceptShare(metadata: CKShare.Metadata) {
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        operation.acceptSharesResultBlock = { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.logger.info("Successfully accepted CKShare.")
                Task {
                    do {
                        try await self.sharedSyncEngine?.fetchChanges()
                    } catch {
                        self.logger.error("Error fetching changes after accepting share: \(error.localizedDescription)")
                    }
                }
            case .failure(let error):
                self.logger.error("Failed to accept CKShare: \(error.localizedDescription)")
            }
        }
        operation.qualityOfService = .userInteractive
        container.add(operation)
    }
}

// MARK: - CKSyncEngineDelegate

extension CloudKitSyncManager: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            if syncEngine === privateSyncEngine {
                persistPrivateState(update.stateSerialization)
            } else if syncEngine === sharedSyncEngine {
                persistSharedState(update.stateSerialization)
            }

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
            if let engine = privateSyncEngine {
                migrateLocalDataToCloud(using: engine)
            }
        case .signOut, .switchAccounts:
            recordMetadata = [:]
            persistMetadata()
            UserDefaults.standard.removeObject(forKey: AppStorageKeys.ckSyncEngineState)
            UserDefaults.standard.removeObject(forKey: AppStorageKeys.ckSharedSyncEngineState)
            UserDefaults.standard.set(false, forKey: AppStorageKeys.didMigrateToCloudKit)
        @unknown default:
            break
        }
    }

    private func applyFetched(_ changes: CKSyncEngine.Event.FetchedRecordZoneChanges) {
        var upsertedMatches: [MatchRecord] = []
        var upsertedPlayers: [Player] = []
        var upsertedClubs: [Club] = []
        var upsertedChallenges: [ChallengeRecord] = []

        for modification in changes.modifications {
            let record = modification.record
            remember(record)
            guard let payload = record[Self.payloadField] as? Data else { continue }
            let recordClubId = clubId(from: record.recordID.zoneID)

            switch record.recordType {
            case Self.matchType:
                if var match = PersistenceStore.decodeRecord(payload) {
                    // Backfill clubId from zone if missing.
                    if match.clubId == nil {
                        match = MatchRecord(
                            id: match.id, games: match.games,
                            myGamesWon: match.myGamesWon, opponentGamesWon: match.opponentGamesWon,
                            winner: match.winner, myName: match.myName, opponentName: match.opponentName,
                            date: match.date, duration: match.duration,
                            myPlayerId: match.myPlayerId, opponentPlayerId: match.opponentPlayerId,
                            myPartnerName: match.myPartnerName, opponentPartnerName: match.opponentPartnerName,
                            myPartnerPlayerId: match.myPartnerPlayerId, opponentPartnerPlayerId: match.opponentPartnerPlayerId,
                            clubId: recordClubId, isConfirmed: match.isConfirmed
                        )
                    }
                    upsertedMatches.append(match)
                }
            case Self.playerType:
                if var player = PersistenceStore.decodePlayer(payload) {
                    // Backfill clubId from zone if missing.
                    if player.clubId == nil {
                        player = Player(
                            id: player.id, name: player.name, colorIndex: player.colorIndex,
                            iconName: player.iconName, clubId: recordClubId
                        )
                    }
                    upsertedPlayers.append(player)
                }
            case Self.clubType:
                if var club = PersistenceStore.decodeClub(payload) {
                    let owner = record.recordID.zoneID.ownerName
                    club.ownerRecordName = (owner == CKCurrentUserDefaultName) ? nil : owner
                    upsertedClubs.append(club)
                }
            case Self.challengeType:
                if let challenge = PersistenceStore.decodeChallenge(payload) {
                    upsertedChallenges.append(challenge)
                }
            default:
                break
            }
        }

        var deletedMatchIds: [UUID] = []
        var deletedPlayerIds: [UUID] = []
        var deletedClubIds: [UUID] = []
        var deletedChallengeIds: [UUID] = []

        for deletion in changes.deletions {
            forget(deletion.recordID.recordName)
            guard let uuid = UUID(uuidString: deletion.recordID.recordName) else { continue }
            switch deletion.recordType {
            case Self.matchType: deletedMatchIds.append(uuid)
            case Self.playerType: deletedPlayerIds.append(uuid)
            case Self.clubType: deletedClubIds.append(uuid)
            case Self.challengeType: deletedChallengeIds.append(uuid)
            default: break
            }
        }

        if !upsertedMatches.isEmpty || !upsertedPlayers.isEmpty || !upsertedClubs.isEmpty || !upsertedChallenges.isEmpty {
            AppStore.shared.applyRemoteUpsert(
                records: upsertedMatches, players: upsertedPlayers, clubs: upsertedClubs, challenges: upsertedChallenges
            )
        }
        if !deletedMatchIds.isEmpty || !deletedPlayerIds.isEmpty || !deletedClubIds.isEmpty || !deletedChallengeIds.isEmpty {
            AppStore.shared.applyRemoteDeletions(
                recordIds: deletedMatchIds, playerIds: deletedPlayerIds, clubIds: deletedClubIds, challengeIds: deletedChallengeIds
            )
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
            if PersistenceStore.resolveConflict(localIntendedDelete: false) == .takeServer,
               let payload = serverRecord[Self.payloadField] as? Data {
                applyServerRecord(serverRecord, payload: payload)
            }
        case .zoneNotFound, .userDeletedZone:
            guard let privateSyncEngine else { return }
            let zoneID = recordID.zoneID
            if zoneID.ownerName == CKCurrentUserDefaultName {
                privateSyncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
                if zoneID.zoneName == Self.zoneName {
                    enqueueHistoryChanges(upsertedIds: AppStore.shared.history.filter { $0.clubId == nil }.map(\.id), deletedIds: [:])
                    enqueueRosterChanges(upsertedIds: AppStore.shared.roster.filter { $0.clubId == nil }.map(\.id), deletedIds: [:])
                } else if let clubId = clubId(from: zoneID) {
                    enqueueClubChanges(upsertedIds: [clubId], deletedIds: [:])
                    enqueueHistoryChanges(upsertedIds: AppStore.shared.history.filter { $0.clubId == clubId }.map(\.id), deletedIds: [:])
                    enqueueRosterChanges(upsertedIds: AppStore.shared.roster.filter { $0.clubId == clubId }.map(\.id), deletedIds: [:])
                }
            }
        case .unknownItem:
            forget(recordID.recordName)
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            break // CKSyncEngine retries these automatically.
        default:
            logger.error("Unhandled record-save failure \(error.code.rawValue) for \(recordID.recordName)")
        }
    }

    private func applyServerRecord(_ record: CKRecord, payload: Data) {
        let recordClubId = clubId(from: record.recordID.zoneID)
        switch record.recordType {
        case Self.matchType:
            if var match = PersistenceStore.decodeRecord(payload) {
                if match.clubId == nil {
                    match = MatchRecord(
                        id: match.id, games: match.games,
                        myGamesWon: match.myGamesWon, opponentGamesWon: match.opponentGamesWon,
                        winner: match.winner, myName: match.myName, opponentName: match.opponentName,
                        date: match.date, duration: match.duration,
                        myPlayerId: match.myPlayerId, opponentPlayerId: match.opponentPlayerId,
                        myPartnerName: match.myPartnerName, opponentPartnerName: match.opponentPartnerName,
                        myPartnerPlayerId: match.myPartnerPlayerId, opponentPartnerPlayerId: match.opponentPartnerPlayerId,
                        clubId: recordClubId, isConfirmed: match.isConfirmed
                    )
                }
                AppStore.shared.applyRemoteUpsert(records: [match], players: [], clubs: [])
            }
        case Self.playerType:
            if var player = PersistenceStore.decodePlayer(payload) {
                if player.clubId == nil {
                    player = Player(
                        id: player.id, name: player.name, colorIndex: player.colorIndex,
                        iconName: player.iconName, clubId: recordClubId
                    )
                }
                AppStore.shared.applyRemoteUpsert(records: [], players: [player], clubs: [])
            }
        case Self.clubType:
            if var club = PersistenceStore.decodeClub(payload) {
                let owner = record.recordID.zoneID.ownerName
                club.ownerRecordName = (owner == CKCurrentUserDefaultName) ? nil : owner
                AppStore.shared.applyRemoteUpsert(records: [], players: [], clubs: [club])
            }
        case Self.challengeType:
            if let challenge = PersistenceStore.decodeChallenge(payload) {
                AppStore.shared.applyRemoteUpsert(records: [], players: [], clubs: [], challenges: [challenge])
            }
        default:
            break
        }
    }
}
