//
//  CloudKitSyncManager.swift
//  badminton score tracker Watch App
//
//  Syncs match history + roster + clubs + scalar settings through the
//  CloudKit private and shared databases via CKSyncEngine —
//  the only sync path (no KV-store fallback, no feature flag). Manages two
//  sync engine instances to synchronize personal data (private DB) and
//  shared club data (shared DB). Supports creating zone-wide CKShare for
//  clubs and accepting share invitations.
//

import Foundation
import CloudKit
import os
import BadmintonCore

@MainActor
final class CloudKitSyncManager: SyncEngine {
    static let shared = CloudKitSyncManager()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "badminton-score-tracker", category: "CloudKitSync")

    private static let containerID = "iCloud.ritsuma.badminton-score-tracker"
    private static let zoneName = "BadmintonZone"
    /// Fixed, always-self-owned zone carrying a mirrored, read-only copy of
    /// this device's personal (clubId == nil) roster + history, shared via
    /// identity (not link) to every accepted friend once
    /// SettingsSnapshot.shareHistoryWithFriends is on. Unlike Club zones,
    /// there is exactly one of these per user and it's never named with a
    /// UUID — on the receiving side, `zoneID.ownerName` alone identifies
    /// which friend's zone a fetched record came from.
    private static let friendsHistoryZoneName = "FriendsHistory"
    private static let matchType = "MatchRecord"
    private static let playerType = "Player"
    private static let clubType = "Club"
    private static let challengeType = "Challenge"
    private static let reactionType = "Reaction"
    private static let friendProfileType = "FriendProfile"
    private static let friendRequestType = "FriendRequest"
    private static let settingsType = "Settings"
    private static let settingsRecordName = "Settings"
    /// Single fixed records in the FriendsHistory zone, mirroring per-field
    /// friend-visibility profile data — see FriendIdentitySnapshot.swift/
    /// FriendStatsSnapshot.swift. One of each per user, same "never deleted
    /// except when every gating toggle is off" contract as Settings.
    private static let friendIdentityType = "FriendIdentity"
    private static let friendIdentityRecordName = "FriendIdentity"
    private static let friendStatsType = "FriendStats"
    private static let friendStatsRecordName = "FriendStats"
    private static let payloadField = "payload"

    private lazy var container = CKContainer(identifier: Self.containerID)
    private lazy var privateDatabase = container.privateCloudDatabase
    private lazy var sharedDatabase = container.sharedCloudDatabase
    /// Friends v1 (graph-only): the public database, used only by the
    /// methods in the "Friends" section below. Unlike `privateDatabase`/
    /// `sharedDatabase`, it is NOT driven by a `CKSyncEngine` — there is no
    /// push-based sync for it here, just direct save/fetch/query calls.
    private lazy var publicDatabase = container.publicCloudDatabase

    private let privateZone = CKRecordZone(zoneName: zoneName)

    /// A single fixed record (never deleted, only ever upserted) carrying
    /// the scalar settings that used to sync via the iCloud KV store.
    private var settingsRecordID: CKRecord.ID {
        CKRecord.ID(recordName: Self.settingsRecordName, zoneID: privateZone.zoneID)
    }

    private var friendIdentityRecordID: CKRecord.ID {
        CKRecord.ID(recordName: Self.friendIdentityRecordName, zoneID: friendsHistoryZoneID())
    }

    private var friendStatsRecordID: CKRecord.ID {
        CKRecord.ID(recordName: Self.friendStatsRecordName, zoneID: friendsHistoryZoneID())
    }

    private var privateSyncEngine: CKSyncEngine?
    private var sharedSyncEngine: CKSyncEngine?

    /// Zone-qualified record key -> encoded CKRecord system fields (change
    /// tag). Persisted so a save of an existing record carries the server's
    /// change tag and reads as an update, not a conflict. Keyed by more than
    /// just `recordName`: a personal match/player mirrored into the
    /// "FriendsHistory" zone shares its `recordName` (same UUID) with the
    /// original in the personal zone, so `recordName` alone is not a unique
    /// key once that mirroring exists — see `metadataKey(for:)`.
    private var recordMetadata: [String: Data] = [:]

    private func metadataKey(for recordID: CKRecord.ID) -> String {
        "\(recordID.zoneID.ownerName)/\(recordID.zoneID.zoneName)/\(recordID.recordName)"
    }

    /// Set while a first-launch migration upload is pending.
    private var migrationPending = false

    /// Ensures `start()` is idempotent — safe if called more than once.
    private var didStart = false

    private init() {}

    // MARK: - Lifecycle

    /// Creates both `CKSyncEngine`s and kicks off first-launch migration /
    /// a Settings upsert. Must run on the main actor **before** interactive
    /// UI can call AppStore save paths — enqueues silently no-op while the
    /// engines are still nil, and CloudKit is the only sync path.
    func start() {
        guard !didStart else { return }
        didStart = true

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

        // Always enqueue Settings once engines exist so identity/match-format
        // converge on devices that already migrated under the old dual-path
        // (those never seed Settings from migrateLocalDataToCloud again).
        enqueueSettingsChange()
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
        enqueueSettingsChange()
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

    /// Reactions (#164) share challenges' always-club-zoned contract.
    func enqueueReactionChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID]) {
        enqueue(upsertedIds: upsertedIds, deletedIds: deletedIds.mapValues { $0 as UUID? })
    }

    /// Mirrors personal match records into the "FriendsHistory" zone. Unlike
    /// `enqueue`, the destination is always the same fixed, self-owned zone —
    /// no per-record clubId resolution needed. Callers (AppStore.saveHistory/
    /// clearHistory) are responsible for only passing ids of records where
    /// `clubId == nil`, and for guarding the call on
    /// SettingsSnapshot.shareHistoryWithFriends being on.
    func enqueueFriendsHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID]) {
        enqueueFriendsHistoryZone(upsertedIds: upsertedIds, deletedIds: deletedIds)
    }

    /// Mirrors personal roster players into the "FriendsHistory" zone — same
    /// contract as `enqueueFriendsHistoryChanges`.
    func enqueueFriendsRosterChanges(upsertedIds: [UUID], deletedIds: [UUID]) {
        enqueueFriendsHistoryZone(upsertedIds: upsertedIds, deletedIds: deletedIds)
    }

    private func enqueueFriendsHistoryZone(upsertedIds: [UUID], deletedIds: [UUID]) {
        guard let privateSyncEngine, !upsertedIds.isEmpty || !deletedIds.isEmpty else { return }
        let zoneID = friendsHistoryZoneID()

        if !upsertedIds.isEmpty {
            privateSyncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
        }
        for id in upsertedIds {
            let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
            privateSyncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        }
        for id in deletedIds {
            let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
            privateSyncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])
        }
    }

    /// Enqueues the fixed Settings record for upload. Call sites: `start()`,
    /// first-launch migration, personal-zone recovery, AppStore
    /// saveRoster/saveHistory/clearHistory, and Settings match-format changes.
    func enqueueSettingsChange() {
        guard let privateSyncEngine else { return }
        privateSyncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(settingsRecordID)])
    }

    /// Upserts the fixed "FriendIdentity" record in the FriendsHistory zone,
    /// rebuilt from `currentFriendIdentitySnapshot()` at send time — call
    /// whenever any of shareAvatarWithFriends/shareGenderWithFriends/
    /// shareBirthdayWithFriends/shareIntroductionWithFriends is on and either
    /// the "Me" roster player or a SettingsSnapshot identity field changed.
    /// Zone existence + participant access are handled separately by
    /// ensureFriendsHistoryShareExists/syncFriendsHistoryParticipants.
    func enqueueFriendIdentityChange() {
        guard let privateSyncEngine else { return }
        privateSyncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: friendsHistoryZoneID()))])
        privateSyncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(friendIdentityRecordID)])
    }

    /// Deletes the "FriendIdentity" record — call when every identity-related
    /// toggle turns off (unlike `SettingsSnapshot.myName`, this record must
    /// disappear entirely rather than round-trip empty, so a friend's cached
    /// copy also gets a clean deletion instead of a stale-but-empty record).
    func removeFriendIdentityRecord() {
        guard let privateSyncEngine else { return }
        privateSyncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(friendIdentityRecordID)])
    }

    /// Upserts the fixed "FriendStats" record — call whenever
    /// shareStatsWithFriends is on and personal history/roster changed.
    func enqueueFriendStatsChange() {
        guard let privateSyncEngine else { return }
        privateSyncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: friendsHistoryZoneID()))])
        privateSyncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(friendStatsRecordID)])
    }

    /// Deletes the "FriendStats" record — call when shareStatsWithFriends
    /// turns off.
    func removeFriendStatsRecord() {
        guard let privateSyncEngine else { return }
        privateSyncEngine.state.add(pendingRecordZoneChanges: [.deleteRecord(friendStatsRecordID)])
    }

    /// Builds this device's own identity snapshot from the current Settings
    /// fields + the "Me" roster player, zeroing out any field whose matching
    /// toggle is off — see SettingsSnapshot's per-field toggle doc comment.
    /// Name always mirrors (no toggle — see that same doc comment).
    private func currentFriendIdentitySnapshot() -> FriendIdentitySnapshot {
        let defaults = UserDefaults.standard
        let myName = defaults.string(forKey: AppStorageKeys.myName) ?? Player.defaultMyName
        let mePlayer = AppStore.shared.roster.first(where: { $0.id == AppStore.shared.localPlayerId })
        let shareAvatar = defaults.object(forKey: AppStorageKeys.shareAvatarWithFriends) as? Bool ?? false
        let shareGender = defaults.object(forKey: AppStorageKeys.shareGenderWithFriends) as? Bool ?? false
        let shareBirthday = defaults.object(forKey: AppStorageKeys.shareBirthdayWithFriends) as? Bool ?? false
        let shareIntroduction = defaults.object(forKey: AppStorageKeys.shareIntroductionWithFriends) as? Bool ?? false
        return FriendIdentitySnapshot(
            participantId: defaults.string(forKey: AppStorageKeys.myParticipantId) ?? "",
            displayName: Player.displayName(for: myName),
            colorIndex: shareAvatar ? mePlayer?.colorIndex : nil,
            iconName: shareAvatar ? mePlayer?.iconName : nil,
            gender: shareGender ? defaults.string(forKey: AppStorageKeys.gender) : nil,
            birthday: shareBirthday ? (defaults.object(forKey: AppStorageKeys.birthday) as? Date) : nil,
            introduction: shareIntroduction ? defaults.string(forKey: AppStorageKeys.introduction) : nil
        )
    }

    /// Builds this device's own stats snapshot from personal (clubId == nil)
    /// history/roster via `FriendStatsSnapshot.compute`.
    private func currentFriendStatsSnapshot() -> FriendStatsSnapshot {
        let myName = Player.displayName(for: UserDefaults.standard.string(forKey: AppStorageKeys.myName) ?? Player.defaultMyName)
        let personalHistory = AppStore.shared.history.filter { $0.clubId == nil }
        let personalRoster = AppStore.shared.roster.filter { $0.clubId == nil }
        return FriendStatsSnapshot.compute(
            participantId: UserDefaults.standard.string(forKey: AppStorageKeys.myParticipantId) ?? "",
            displayName: myName,
            history: personalHistory,
            roster: personalRoster
        )
    }

    private func currentSettingsSnapshot() -> SettingsSnapshot {
        let defaults = UserDefaults.standard
        // Route localPlayerId through AppStore so the first Settings upload
        // never ships an empty value (AppStore generates-and-persists once).
        return SettingsSnapshot(
            myName: defaults.string(forKey: AppStorageKeys.myName) ?? Player.defaultMyName,
            localPlayerId: AppStore.shared.localPlayerId.uuidString,
            pointsToWin: defaults.object(forKey: AppStorageKeys.pointsToWin) as? Int ?? 21,
            gamesInMatch: defaults.object(forKey: AppStorageKeys.gamesInMatch) as? Int ?? 3,
            courtTheme: defaults.string(forKey: AppStorageKeys.courtTheme) ?? "Green",
            announceScore: defaults.object(forKey: AppStorageKeys.announceScore) as? Bool ?? true,
            enableSounds: defaults.object(forKey: AppStorageKeys.enableSounds) as? Bool ?? true,
            enableCrownScoring: defaults.object(forKey: AppStorageKeys.enableCrownScoring) as? Bool ?? true,
            timeModeEnabled: defaults.object(forKey: AppStorageKeys.timeModeEnabled) as? Bool ?? false,
            timeLimitMinutes: defaults.object(forKey: AppStorageKeys.timeLimitMinutes) as? Int ?? 10,
            courtChangeRemindersEnabled: defaults.object(forKey: AppStorageKeys.courtChangeRemindersEnabled) as? Bool ?? false,
            clubLastViewedActivity: ClubActivityCodec.decode(defaults.data(forKey: AppStorageKeys.clubLastViewedActivity) ?? Data()),
            accountLinked: defaults.object(forKey: AppStorageKeys.accountLinked) as? Bool ?? false,
            gameScreenStyle: defaults.string(forKey: AppStorageKeys.gameScreenStyle) ?? "Depth",
            shareHistoryWithFriends: defaults.object(forKey: AppStorageKeys.shareHistoryWithFriends) as? Bool ?? false,
            shareAvatarWithFriends: defaults.object(forKey: AppStorageKeys.shareAvatarWithFriends) as? Bool ?? false,
            shareGenderWithFriends: defaults.object(forKey: AppStorageKeys.shareGenderWithFriends) as? Bool ?? false,
            shareBirthdayWithFriends: defaults.object(forKey: AppStorageKeys.shareBirthdayWithFriends) as? Bool ?? false,
            shareIntroductionWithFriends: defaults.object(forKey: AppStorageKeys.shareIntroductionWithFriends) as? Bool ?? false,
            shareStatsWithFriends: defaults.object(forKey: AppStorageKeys.shareStatsWithFriends) as? Bool ?? false,
            gender: defaults.string(forKey: AppStorageKeys.gender),
            birthday: defaults.object(forKey: AppStorageKeys.birthday) as? Date,
            introduction: defaults.string(forKey: AppStorageKeys.introduction)
        )
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
        if let reaction = AppStore.shared.reactions.first(where: { $0.id == recordId }) {
            return reaction.clubId
        }
        return nil
    }

    private func clubId(from zoneID: CKRecordZone.ID) -> UUID? {
        let prefix = "Club-"
        guard zoneID.zoneName.hasPrefix(prefix) else { return nil }
        let uuidString = String(zoneID.zoneName.dropFirst(prefix.count))
        return UUID(uuidString: uuidString)
    }

    /// Always this device's own "FriendsHistory" zone — the zone we mirror
    /// personal data *into*. A friend's own FriendsHistory zone (as it
    /// appears to us via the shared DB) is identified purely by `ownerName`
    /// differing from `CKCurrentUserDefaultName`, not by a different zone
    /// name — see `applyFetched`.
    private func friendsHistoryZoneID() -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: Self.friendsHistoryZoneName, ownerName: CKCurrentUserDefaultName)
    }

    // Build the CKRecord to upload for a pending save.
    private func materializeRecord(for recordID: CKRecord.ID) -> CKRecord? {
        if recordID == settingsRecordID {
            guard let payload = PersistenceStore.encodeSettingsSnapshot(currentSettingsSnapshot()) else { return nil }
            return record(for: recordID, type: Self.settingsType, payload: payload)
        }
        if recordID == friendIdentityRecordID {
            guard let payload = PersistenceStore.encodeFriendIdentitySnapshot(currentFriendIdentitySnapshot()) else { return nil }
            return record(for: recordID, type: Self.friendIdentityType, payload: payload)
        }
        if recordID == friendStatsRecordID {
            guard let payload = PersistenceStore.encodeFriendStatsSnapshot(currentFriendStatsSnapshot()) else { return nil }
            return record(for: recordID, type: Self.friendStatsType, payload: payload)
        }
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
        if let reaction = AppStore.shared.reactions.first(where: { $0.id == uuid }) {
            guard let payload = PersistenceStore.encodeReaction(reaction) else { return nil }
            return record(for: recordID, type: Self.reactionType, payload: payload)
        }
        return nil
    }

    private func record(for recordID: CKRecord.ID, type: String, payload: Data) -> CKRecord {
        let record = storedRecord(for: recordID) ?? CKRecord(recordType: type, recordID: recordID)
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
        recordMetadata[metadataKey(for: record.recordID)] = coder.encodedData
        persistMetadata()
    }

    private func forget(_ recordID: CKRecord.ID) {
        recordMetadata[metadataKey(for: recordID)] = nil
        persistMetadata()
    }

    private func storedRecord(for recordID: CKRecord.ID) -> CKRecord? {
        guard let data = recordMetadata[metadataKey(for: recordID)],
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

    // MARK: - Friends' shared history (identity-shared, read-only)
    //
    // Unlike Club's `fetchOrCreateShare` (a link-based share anyone can join
    // via UICloudSharingController), the "FriendsHistory" share must only
    // ever be visible to accepted friends — participants are added/removed
    // by identity (CKFetchShareParticipantsOperation, keyed by their
    // participantId) rather than via a shareable link, and
    // `publicPermission` stays `.none`.

    /// Fetches or creates the "FriendsHistory" zone's CKShare. Must run on
    /// this device (the zone is always self-owned). `publicPermission` is
    /// deliberately `.none` — this share must never be joinable by link.
    func ensureFriendsHistoryShareExists() async throws -> CKShare {
        guard let privateSyncEngine else { throw CKError(.internalError) }
        let zoneID = friendsHistoryZoneID()
        let zone = CKRecordZone(zoneID: zoneID)
        privateSyncEngine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        // Also save directly (not just enqueue) so the CKShare save just
        // below doesn't race the async CKSyncEngine flush — a CKShare can
        // only be saved into a zone that already exists server-side.
        _ = try? await privateDatabase.save(zone)

        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            let record = try await privateDatabase.record(for: shareID)
            if let share = record as? CKShare {
                return share
            }
        } catch {
            let ckError = error as? CKError
            if ckError?.code == .unknownItem {
                let share = CKShare(recordZoneID: zoneID)
                share.publicPermission = .none
                let saved = try await privateDatabase.save(share)
                if let savedShare = saved as? CKShare {
                    return savedShare
                }
            }
        }
        throw CKError(.invalidArguments)
    }

    /// Reconciles the "FriendsHistory" share's participant list against the
    /// current accepted-friends graph: adds any accepted friend missing from
    /// the share (read-only), removes any participant who's no longer an
    /// accepted friend. No-ops (leaves the share as-is) if nothing changed.
    /// Call sites: the share toggle turning on, and after any friend-graph
    /// change (accept/decline/unfriend) — always guarded by the caller on
    /// SettingsSnapshot.shareHistoryWithFriends being on.
    func syncFriendsHistoryParticipants() async {
        guard let share = try? await ensureFriendsHistoryShareExists() else { return }

        let friendIds = Set(AppStore.shared.friends.map(\.participantId))
        let nonOwnerParticipants = share.participants.filter { $0.role != .owner }
        let currentParticipantIds = Set(nonOwnerParticipants.compactMap { $0.userIdentity.userRecordID?.recordName })
        let idsToAdd = friendIds.subtracting(currentParticipantIds)
        let participantsToRemove = nonOwnerParticipants.filter { participant in
            guard let recordName = participant.userIdentity.userRecordID?.recordName else { return false }
            return !friendIds.contains(recordName)
        }

        guard !idsToAdd.isEmpty || !participantsToRemove.isEmpty else { return }

        for participant in participantsToRemove {
            share.removeParticipant(participant)
        }

        if !idsToAdd.isEmpty {
            for participant in await fetchShareParticipants(for: idsToAdd) {
                participant.permission = .readOnly
                share.addParticipant(participant)
            }
        }

        _ = try? await privateDatabase.save(share)
    }

    /// Removes every non-owner participant from the "FriendsHistory" share
    /// without deleting the zone/share itself, so re-enabling the toggle
    /// later is just a participant resync rather than a zone re-creation.
    /// Call site: the share toggle turning off.
    func revokeFriendsHistoryAccess() async {
        guard let share = try? await ensureFriendsHistoryShareExists() else { return }
        let nonOwnerParticipants = share.participants.filter { $0.role != .owner }
        guard !nonOwnerParticipants.isEmpty else { return }
        for participant in nonOwnerParticipants {
            share.removeParticipant(participant)
        }
        _ = try? await privateDatabase.save(share)
    }

    /// Erase All My Data (#264): tears down the "FriendsHistory" zone (and
    /// everything in it — the mirrored roster/history records plus the fixed
    /// FriendIdentity/FriendStats records) entirely, rather than just
    /// revoking participants like `revokeFriendsHistoryAccess()` does.
    /// Deleting a zone also revokes every CKShare participant rooted in it
    /// automatically, so no separate participant-removal call is needed.
    func deleteFriendsHistoryZone() async {
        guard let privateSyncEngine else { return }
        privateSyncEngine.state.add(pendingDatabaseChanges: [.deleteZone(friendsHistoryZoneID())])
    }

    /// Resolves participantIds to `CKShare.Participant`s via an identity
    /// lookup (not an email/phone lookup — participantId is already a
    /// `CKRecord.ID.recordName` from `resolveMyParticipantId`/
    /// `CKContainer.userRecordID()`).
    private func fetchShareParticipants(for participantIds: Set<String>) async -> [CKShare.Participant] {
        let lookupInfos = participantIds.map { CKUserIdentity.LookupInfo(userRecordID: CKRecord.ID(recordName: $0)) }
        let operation = CKFetchShareParticipantsOperation(userIdentityLookupInfos: lookupInfos)
        return await withCheckedContinuation { continuation in
            var participants: [CKShare.Participant] = []
            operation.perShareParticipantResultBlock = { _, result in
                if case .success(let participant) = result {
                    participants.append(participant)
                }
            }
            operation.fetchShareParticipantsResultBlock = { [weak self] result in
                if case .failure(let error) = result {
                    self?.logger.error("Failed to fetch share participants: \(error.localizedDescription)")
                }
                continuation.resume(returning: participants)
            }
            container.add(operation)
        }
    }

    // MARK: - Friends (v1, graph-only; public database, no CKSyncEngine)
    //
    // The public database isn't wired to a CKSyncEngine (private/shared DB
    // only) — these methods talk to it directly. applyRemoteUpsert/
    // applyRemoteDeletions are deliberately not involved here: there is no
    // CKSyncEngineDelegate event for public-DB changes to route through them.
    // A best-effort CKQuerySubscription (Phase 7f, ensureFriendRequestSubscriptionExists)
    // can trigger a silent push on a new incoming request, but the Friends
    // screen's poll-on-appear/pull-to-refresh (fetchMyFriendRequests) remains
    // the source of truth regardless of whether that push ever arrives.

    enum FriendRequestError: Error {
        case selfRequest
        case alreadyPending
    }

    /// The current iCloud account's durable per-Apple-ID key. Stable for the
    /// life of the account, so it's resolved once and cached.
    func resolveMyParticipantId() async throws -> String {
        if let cached = UserDefaults.standard.string(forKey: AppStorageKeys.myParticipantId) {
            return cached
        }
        let recordID = try await container.userRecordID()
        UserDefaults.standard.set(recordID.recordName, forKey: AppStorageKeys.myParticipantId)
        return recordID.recordName
    }

    /// Fetch-or-create my public `FriendProfile`, keyed by a deterministic
    /// `recordName == participantId` (one profile per Apple ID, upserted —
    /// never freely appended). Re-saves only if the display name changed.
    func ensureMyProfileExists(displayName: String) async throws {
        let participantId = try await resolveMyParticipantId()
        let recordID = CKRecord.ID(recordName: participantId)

        let existingRecord = try? await publicDatabase.record(for: recordID)
        if let existingRecord,
           let payload = existingRecord[Self.payloadField] as? Data,
           let existingProfile = PersistenceStore.decodeFriendProfile(payload),
           existingProfile.displayName == displayName {
            return
        }

        let profile = FriendProfile(participantId: participantId, displayName: displayName)
        guard let payload = PersistenceStore.encodeFriendProfile(profile) else { return }
        let record = existingRecord ?? CKRecord(recordType: Self.friendProfileType, recordID: recordID)
        record[Self.payloadField] = payload as CKRecordValue
        _ = try await publicDatabase.save(record)
    }

    /// Used to show "X wants to add you" when consuming an invite link.
    /// Fails soft (nil) rather than blocking — the caller falls back to a
    /// generic label rather than stalling the confirmation sheet.
    func fetchProfile(participantId: String) async -> FriendProfile? {
        let recordID = CKRecord.ID(recordName: participantId)
        guard let record = try? await publicDatabase.record(for: recordID),
              let payload = record[Self.payloadField] as? Data else { return nil }
        return PersistenceStore.decodeFriendProfile(payload)
    }

    /// The sync entry point: a direct query, since there's no
    /// CKSyncEngine-driven fetch for the public database. Called by the
    /// Friends screen on appear + pull-to-refresh (no push in v1).
    func fetchMyFriendRequests() async throws -> [FriendRequest] {
        let participantId = try await resolveMyParticipantId()
        let predicate = NSPredicate(
            format: "fromParticipantId == %@ OR toParticipantId == %@",
            participantId, participantId
        )
        let query = CKQuery(recordType: Self.friendRequestType, predicate: predicate)
        let (results, _) = try await publicDatabase.records(matching: query)
        return results.compactMap { _, result in
            guard case .success(let record) = result,
                  let payload = record[Self.payloadField] as? Data else { return nil }
            return PersistenceStore.decodeFriendRequest(payload)
        }
    }

    private static let friendRequestSubscriptionID = "friend-request-inbox"

    /// Best-effort (Phase 7f): registers a CKQuerySubscription so a new
    /// incoming FriendRequest triggers a silent push. Never throws to the
    /// caller — if it fails (bad entitlement, simulator, no device token
    /// yet), the Friends screen's existing poll-on-appear/pull-to-refresh is
    /// unaffected. Not verifiable without a real device + real push
    /// delivery; see ROADMAP.md's 7f note.
    func ensureFriendRequestSubscriptionExists() async {
        guard let participantId = try? await resolveMyParticipantId() else { return }
        let registeredFor = UserDefaults.standard.string(forKey: AppStorageKeys.friendRequestSubscriptionParticipantId)
        guard registeredFor != participantId else { return }

        let predicate = NSPredicate(format: "toParticipantId == %@", participantId)
        let subscription = CKQuerySubscription(
            recordType: Self.friendRequestType,
            predicate: predicate,
            subscriptionID: Self.friendRequestSubscriptionID,
            options: .firesOnRecordCreation
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await publicDatabase.save(subscription)
            UserDefaults.standard.set(participantId, forKey: AppStorageKeys.friendRequestSubscriptionParticipantId)
        } catch {
            // Best effort — see doc comment above.
        }
    }

    /// Guards against self-requests and an existing pending request in
    /// either direction (mirrors `ClubDetailView.hasPendingChallenge`'s
    /// bidirectional check), then saves a new `FriendRequest`.
    func sendFriendRequest(toParticipantId: String, toDisplayName: String) async throws {
        let myParticipantId = try await resolveMyParticipantId()
        guard myParticipantId != toParticipantId else { throw FriendRequestError.selfRequest }

        let existing = try await fetchMyFriendRequests()
        let alreadyPending = existing.contains {
            $0.status == .pending &&
            (($0.fromParticipantId == myParticipantId && $0.toParticipantId == toParticipantId) ||
             ($0.fromParticipantId == toParticipantId && $0.toParticipantId == myParticipantId))
        }
        guard !alreadyPending else { throw FriendRequestError.alreadyPending }

        let storedMyName = UserDefaults.standard.string(forKey: AppStorageKeys.myName) ?? Player.defaultMyName
        let myDisplayName = Player.displayName(for: storedMyName)
        let request = FriendRequest(
            fromParticipantId: myParticipantId, fromDisplayName: myDisplayName,
            toParticipantId: toParticipantId, toDisplayName: toDisplayName
        )
        guard let payload = PersistenceStore.encodeFriendRequest(request) else { return }
        let record = CKRecord(recordType: Self.friendRequestType, recordID: CKRecord.ID(recordName: request.id.uuidString))
        record[Self.payloadField] = payload as CKRecordValue
        _ = try await publicDatabase.save(record)
    }

    /// Flips `status` in place and re-saves — same mutate-don't-delete
    /// convention as `ClubDetailView.respond(to:accept:)`.
    func respondToFriendRequest(_ request: FriendRequest, accept: Bool) async throws {
        let recordID = CKRecord.ID(recordName: request.id.uuidString)
        let record = try await publicDatabase.record(for: recordID)
        var updated = request
        updated.status = accept ? .accepted : .declined
        guard let payload = PersistenceStore.encodeFriendRequest(updated) else { return }
        record[Self.payloadField] = payload as CKRecordValue
        _ = try await publicDatabase.save(record)
    }

    /// Erase All My Data (#264): deletes the public-database `FriendProfile`
    /// record for this Apple ID, so this device is no longer discoverable by
    /// an invite link/code. Best-effort — a partial CloudKit failure here
    /// shouldn't block the rest of the erase flow.
    func deleteMyFriendProfile() async {
        guard let participantId = try? await resolveMyParticipantId() else { return }
        _ = try? await publicDatabase.deleteRecord(withID: CKRecord.ID(recordName: participantId))
    }

    /// Erase All My Data (#264): deletes every public-database `FriendRequest`
    /// this account is party to, on either side (mirrors `fetchMyFriendRequests`'s
    /// bidirectional query). Best-effort per record, same convention as
    /// `deleteMyFriendProfile()`.
    func deleteAllMyFriendRequests() async {
        guard let requests = try? await fetchMyFriendRequests() else { return }
        for request in requests {
            _ = try? await publicDatabase.deleteRecord(withID: CKRecord.ID(recordName: request.id.uuidString))
        }
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
             .willFetchChanges, .didFetchChanges, .willSendChanges, .didSendChanges,
             .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
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
        var upsertedReactions: [ReactionRecord] = []
        // Friends' shared roster/history, keyed by the owning friend's
        // participantId (== the zone's ownerName) — deliberately kept
        // separate from the caches above and never merged into them, since
        // this is someone else's data (see AppStore.applyRemoteFriendActivity).
        var friendUpsertedMatches: [String: [MatchRecord]] = [:]
        var friendUpsertedPlayers: [String: [Player]] = [:]
        var friendUpsertedIdentities: [String: FriendIdentitySnapshot] = [:]
        var friendUpsertedStats: [String: FriendStatsSnapshot] = [:]

        for modification in changes.modifications {
            let record = modification.record
            remember(record)
            guard let payload = record[Self.payloadField] as? Data else { continue }
            let zoneID = record.recordID.zoneID

            if zoneID.zoneName == Self.friendsHistoryZoneName {
                // A second copy of this device's own mirrored data (synced
                // across this Apple ID's other devices via the private DB)
                // is redundant with the personal-zone original — only a
                // zone owned by someone else is new information.
                if zoneID.ownerName != CKCurrentUserDefaultName {
                    switch record.recordType {
                    case Self.matchType:
                        if let match = PersistenceStore.decodeRecord(payload) {
                            friendUpsertedMatches[zoneID.ownerName, default: []].append(match)
                        }
                    case Self.playerType:
                        if let player = PersistenceStore.decodePlayer(payload) {
                            friendUpsertedPlayers[zoneID.ownerName, default: []].append(player)
                        }
                    case Self.friendIdentityType:
                        if let identity = PersistenceStore.decodeFriendIdentitySnapshot(payload) {
                            friendUpsertedIdentities[zoneID.ownerName] = identity
                        }
                    case Self.friendStatsType:
                        if let stats = PersistenceStore.decodeFriendStatsSnapshot(payload) {
                            friendUpsertedStats[zoneID.ownerName] = stats
                        }
                    default:
                        break
                    }
                }
                continue
            }

            let recordClubId = clubId(from: zoneID)

            switch record.recordType {
            case Self.settingsType:
                if let snapshot = PersistenceStore.decodeSettingsSnapshot(payload) {
                    AppStore.shared.applyRemoteSettings(snapshot)
                }
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
            case Self.reactionType:
                if let reaction = PersistenceStore.decodeReaction(payload) {
                    upsertedReactions.append(reaction)
                }
            default:
                break
            }
        }

        var deletedMatchIds: [UUID] = []
        var deletedPlayerIds: [UUID] = []
        var deletedClubIds: [UUID] = []
        var deletedChallengeIds: [UUID] = []
        var deletedReactionIds: [UUID] = []
        var friendDeletedMatchIds: [String: [UUID]] = [:]
        var friendDeletedPlayerIds: [String: [UUID]] = [:]
        var friendDeletedIdentityOwners: Set<String> = []
        var friendDeletedStatsOwners: Set<String> = []

        for deletion in changes.deletions {
            forget(deletion.recordID)
            let zoneID = deletion.recordID.zoneID

            if zoneID.zoneName == Self.friendsHistoryZoneName {
                if zoneID.ownerName != CKCurrentUserDefaultName {
                    switch deletion.recordType {
                    case Self.friendIdentityType: friendDeletedIdentityOwners.insert(zoneID.ownerName)
                    case Self.friendStatsType: friendDeletedStatsOwners.insert(zoneID.ownerName)
                    default:
                        if let uuid = UUID(uuidString: deletion.recordID.recordName) {
                            switch deletion.recordType {
                            case Self.matchType: friendDeletedMatchIds[zoneID.ownerName, default: []].append(uuid)
                            case Self.playerType: friendDeletedPlayerIds[zoneID.ownerName, default: []].append(uuid)
                            default: break
                            }
                        }
                    }
                }
                continue
            }
            guard let uuid = UUID(uuidString: deletion.recordID.recordName) else { continue }

            switch deletion.recordType {
            case Self.matchType: deletedMatchIds.append(uuid)
            case Self.playerType: deletedPlayerIds.append(uuid)
            case Self.clubType: deletedClubIds.append(uuid)
            case Self.challengeType: deletedChallengeIds.append(uuid)
            case Self.reactionType: deletedReactionIds.append(uuid)
            default: break
            }
        }

        if !upsertedMatches.isEmpty || !upsertedPlayers.isEmpty || !upsertedClubs.isEmpty
            || !upsertedChallenges.isEmpty || !upsertedReactions.isEmpty {
            AppStore.shared.applyRemoteUpsert(
                records: upsertedMatches, players: upsertedPlayers, clubs: upsertedClubs,
                challenges: upsertedChallenges, reactions: upsertedReactions
            )
        }
        if !deletedMatchIds.isEmpty || !deletedPlayerIds.isEmpty || !deletedClubIds.isEmpty
            || !deletedChallengeIds.isEmpty || !deletedReactionIds.isEmpty {
            AppStore.shared.applyRemoteDeletions(
                recordIds: deletedMatchIds, playerIds: deletedPlayerIds, clubIds: deletedClubIds,
                challengeIds: deletedChallengeIds, reactionIds: deletedReactionIds
            )
        }

        for ownerId in Set(friendUpsertedMatches.keys).union(friendUpsertedPlayers.keys) {
            AppStore.shared.applyRemoteFriendActivity(
                participantId: ownerId,
                matches: friendUpsertedMatches[ownerId] ?? [],
                players: friendUpsertedPlayers[ownerId] ?? []
            )
        }
        for ownerId in Set(friendDeletedMatchIds.keys).union(friendDeletedPlayerIds.keys) {
            AppStore.shared.applyRemoteFriendActivityDeletions(
                participantId: ownerId,
                matchIds: friendDeletedMatchIds[ownerId] ?? [],
                playerIds: friendDeletedPlayerIds[ownerId] ?? []
            )
        }
        for (ownerId, identity) in friendUpsertedIdentities {
            AppStore.shared.applyRemoteFriendIdentity(participantId: ownerId, snapshot: identity)
        }
        for ownerId in friendDeletedIdentityOwners {
            AppStore.shared.applyRemoteFriendIdentityDeletion(participantId: ownerId)
        }
        for (ownerId, stats) in friendUpsertedStats {
            AppStore.shared.applyRemoteFriendStats(participantId: ownerId, snapshot: stats)
        }
        for ownerId in friendDeletedStatsOwners {
            AppStore.shared.applyRemoteFriendStatsDeletion(participantId: ownerId)
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
                    enqueueSettingsChange()
                } else if zoneID.zoneName == Self.friendsHistoryZoneName {
                    enqueueFriendsHistoryChanges(upsertedIds: AppStore.shared.history.filter { $0.clubId == nil }.map(\.id), deletedIds: [])
                    enqueueFriendsRosterChanges(upsertedIds: AppStore.shared.roster.filter { $0.clubId == nil }.map(\.id), deletedIds: [])
                    if AppStore.shared.isSharingAnyFriendIdentityField { enqueueFriendIdentityChange() }
                    if AppStore.shared.isSharingStatsWithFriends { enqueueFriendStatsChange() }
                } else if let clubId = clubId(from: zoneID) {
                    enqueueClubChanges(upsertedIds: [clubId], deletedIds: [:])
                    enqueueHistoryChanges(upsertedIds: AppStore.shared.history.filter { $0.clubId == clubId }.map(\.id), deletedIds: [:])
                    enqueueRosterChanges(upsertedIds: AppStore.shared.roster.filter { $0.clubId == clubId }.map(\.id), deletedIds: [:])
                }
            }
        case .unknownItem:
            forget(recordID)
        case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
            break // CKSyncEngine retries these automatically.
        default:
            logger.error("Unhandled record-save failure \(error.code.rawValue) for \(recordID.recordName)")
        }
    }

    private func applyServerRecord(_ record: CKRecord, payload: Data) {
        let recordClubId = clubId(from: record.recordID.zoneID)
        switch record.recordType {
        case Self.settingsType:
            if let snapshot = PersistenceStore.decodeSettingsSnapshot(payload) {
                AppStore.shared.applyRemoteSettings(snapshot)
            }
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
        case Self.reactionType:
            if let reaction = PersistenceStore.decodeReaction(payload) {
                AppStore.shared.applyRemoteUpsert(records: [], players: [], clubs: [], reactions: [reaction])
            }
        default:
            break
        }
    }
}
