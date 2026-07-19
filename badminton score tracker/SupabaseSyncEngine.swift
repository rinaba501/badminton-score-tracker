//
//  SupabaseSyncEngine.swift
//  badminton score tracker (iOS)
//
//  Roadmap Phase 9c: the SyncEngine conformer AppStore swaps to when a
//  device opts into the Supabase backend (see AppStore.swift's syncEngine
//  property). Thin adapter over CloudSyncSpike's SupabaseSyncManager (the
//  low-level Supabase transport, which cannot import AppStore itself since
//  it lives in a shared package) — reads AppStore.shared's live roster/
//  history/settings by id and re-encodes via PersistenceStore, the same
//  "materialize fresh from the live cache" pattern CloudKitSyncManager's
//  own materializeRecord already uses. Mirrors the Watch's.
//
//  Only the personal-data tier (settings + personal players/match_records)
//  is real — clubs/challenges/reactions/friends-* stay no-ops here until
//  9d/9e migrate them, matching BadmintonCore.NoOpSyncEngine's shape.
//

import Foundation
import BadmintonCore
import CloudSyncSpike

@MainActor
final class SupabaseSyncEngine: SyncEngine {
    static let shared = SupabaseSyncEngine()

    private let manager = SupabaseSyncManager.shared

    private init() {}

    func enqueueRosterChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID?]) {
        Task {
            guard let ownerId = await manager.currentUserId() else { return }
            for id in upsertedIds {
                guard let player = AppStore.shared.roster.first(where: { $0.id == id }),
                      let payload = PersistenceStore.encodePlayer(player) else { continue }
                await manager.upsertPlayer(id: id, ownerId: ownerId, clubId: player.clubId, payload: payload)
            }
            for id in deletedIds.keys {
                await manager.deletePlayer(id: id)
            }
        }
    }

    func enqueueHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID?]) {
        Task {
            guard let ownerId = await manager.currentUserId() else { return }
            for id in upsertedIds {
                guard let record = AppStore.shared.history.first(where: { $0.id == id }),
                      let payload = PersistenceStore.encodeRecord(record) else { continue }
                await manager.upsertMatchRecord(id: id, ownerId: ownerId, clubId: record.clubId, payload: payload)
            }
            for id in deletedIds.keys {
                await manager.deleteMatchRecord(id: id)
            }
        }
    }

    func enqueueSettingsChange() {
        Task {
            guard let ownerId = await manager.currentUserId(),
                  let payload = PersistenceStore.encodeSettingsSnapshot(currentSettingsSnapshot()) else { return }
            await manager.upsertSettings(ownerId: ownerId, payload: payload)
        }
    }

    /// Settings live as scattered `@AppStorage` scalars, not in AppStore's
    /// own cache — same read-straight-from-UserDefaults shape as
    /// CloudKitSyncManager.currentSettingsSnapshot().
    private func currentSettingsSnapshot() -> SettingsSnapshot {
        let defaults = UserDefaults.standard
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

    // MARK: - Not yet migrated (Phase 9d club data, 9e Friends graph)

    func enqueueClubChanges(upsertedIds: [UUID], deletedIds: [UUID: String?]) {}
    func enqueueChallengeChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID]) {}
    func enqueueReactionChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID]) {}
    func enqueueFriendsRosterChanges(upsertedIds: [UUID], deletedIds: [UUID]) {}
    func enqueueFriendsHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID]) {}
    func enqueueFriendIdentityChange() {}
    func removeFriendIdentityRecord() {}
    func enqueueFriendStatsChange() {}
    func deleteFriendsHistoryZone() async {}
    func deleteMyFriendProfile() async {}
    func deleteAllMyFriendRequests() async {}
}
