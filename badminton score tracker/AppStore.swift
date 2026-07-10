//
//  AppStore.swift
//  badminton score tracker (iOS)
//
//  Cached, decoded roster and history for the iPhone companion app. Views read
//  @Published arrays instead of calling PersistenceStore.decode* on every
//  render. Every save always pushes to the KV store via
//  CloudSyncManager.pushToCloud; when CloudKitSyncManager.isEnabled it also
//  gets precise per-record upserts/deletes through CloudKit (see
//  CloudKitSyncManager). Mirrors the Watch App's AppStore.
//

import Foundation
import SwiftUI
import BadmintonCore

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published private(set) var roster: [Player]
    @Published private(set) var history: [MatchRecord]
    /// Roadmap Phase 5b: local-only club list — no CloudKit sync yet, so
    /// unlike roster/history this never pushes through CloudSyncManager (see
    /// saveClubs).
    @Published private(set) var clubs: [Club]
    /// Roadmap Phase 5 backlog (#162): CloudKit-only — there's no meaningful
    /// "personal" challenge, so unlike roster/history there's no KV fallback
    /// at all (see saveChallenges).
    @Published private(set) var challenges: [ChallengeRecord]
    /// Roadmap Phase 5 backlog (#164): CloudKit-only, same contract as
    /// `challenges` — no KV fallback (see saveReactions).
    @Published private(set) var reactions: [ReactionRecord]

    @AppStorage(AppStorageKeys.localPlayerId) private var localPlayerIdString: String = ""

    /// A stable identity for the local user, independent of their display
    /// name (which can be renamed) and independent of the roster ("me" is
    /// deliberately never added there — see `Player.shouldBeStoredAsSavedPlayer`).
    /// `localPlayerId` is a synced scalar, so the phone adopts the Watch's id on
    /// first pull, keeping the "Me"/iWon perspective consistent across devices.
    var localPlayerId: UUID {
        if let existing = UUID(uuidString: localPlayerIdString) { return existing }
        let new = UUID()
        localPlayerIdString = new.uuidString
        return new
    }

    private init() {
        Self.runMigrations()
        let r = UserDefaults.standard.data(forKey: AppStorageKeys.playerRoster) ?? Data()
        let h = UserDefaults.standard.data(forKey: AppStorageKeys.matchHistory) ?? Data()
        let c = UserDefaults.standard.data(forKey: AppStorageKeys.clubs) ?? Data()
        let ch = UserDefaults.standard.data(forKey: AppStorageKeys.challenges) ?? Data()
        let re = UserDefaults.standard.data(forKey: AppStorageKeys.reactions) ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
        clubs = PersistenceStore.decodeClubs(c)
        challenges = PersistenceStore.decodeChallenges(ch)
        reactions = PersistenceStore.decodeReactions(re)
    }

    // Upgrades on-disk data to the current schema before the first decode.
    // The designated place for future schema migrations (see PersistenceStore).
    private static func runMigrations() {
        if let data = UserDefaults.standard.data(forKey: AppStorageKeys.playerRoster),
           let migrated = PersistenceStore.migratedRosterData(from: data) {
            UserDefaults.standard.set(migrated, forKey: AppStorageKeys.playerRoster)
        }
        if let data = UserDefaults.standard.data(forKey: AppStorageKeys.matchHistory),
           let migrated = PersistenceStore.migratedHistoryData(from: data) {
            UserDefaults.standard.set(migrated, forKey: AppStorageKeys.matchHistory)
        }
    }

    // Each save updates the local cache + UserDefaults, then syncs. When
    // CloudKit owns history/roster it gets precise per-record upserts/deletes;
    // CloudSyncManager.pushToCloud is still called either way — it carries the
    // scalar settings, and (only when CloudKit is disabled) the history/roster
    // blobs as the fallback. See CloudSyncManager for how it skips the data
    // blobs when CloudKit is enabled.
    func saveRoster(_ players: [Player]) {
        guard let encoded = PersistenceStore.encodeRoster(players) else { return }
        let diff = PersistenceStore.diffRoster(from: roster, to: players)
        let deletedClubIds = Dictionary(
            roster.filter { oldPlayer in diff.deletedIds.contains(oldPlayer.id) }
                .map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.playerRoster)
        roster = players
        if CloudKitSyncManager.isEnabled {
            CloudKitSyncManager.shared.enqueueRosterChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedClubIds)
        }
        CloudSyncManager.shared.pushToCloud()
    }

    func saveHistory(_ records: [MatchRecord]) {
        guard let encoded = PersistenceStore.encodeHistory(records) else { return }
        // Compute both against the OLD `history` before reassigning it.
        let diff = PersistenceStore.diffHistory(from: history, to: records)
        let deletedClubIds = Dictionary(
            history.filter { oldRecord in diff.deletedIds.contains(oldRecord.id) }
                .map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        // KV fallback only: a deletion must push as an authoritative overwrite,
        // not merge — merging would silently resurrect the removed record(s)
        // from iCloud's still-unshrunk copy. The CloudKit path deletes per
        // record instead (below), so it has no such hazard.
        let isShrink = PersistenceStore.isHistoryShrink(from: history, to: records)
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.matchHistory)
        history = records
        if CloudKitSyncManager.isEnabled {
            CloudKitSyncManager.shared.enqueueHistoryChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedClubIds)
        }
        CloudSyncManager.shared.pushToCloud(overwriteHistory: isShrink)
    }

    func clearHistory() {
        let deletedClubIds = Dictionary(
            history.map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(Data(), forKey: AppStorageKeys.matchHistory)
        history = []
        if CloudKitSyncManager.isEnabled {
            CloudKitSyncManager.shared.enqueueHistoryChanges(upsertedIds: [], deletedIds: deletedClubIds)
        }
        CloudSyncManager.shared.pushToCloud(overwriteHistory: true)
    }

    // Roadmap Phase 5b/c: a Club only becomes a real shared group
    // once Phase 5c wires it to a CloudKit CKShare zone. If CloudKit is enabled,
    // we enqueue club changes.
    func saveClubs(_ clubs: [Club]) {
        guard let encoded = PersistenceStore.encodeClubs(clubs) else { return }
        let diff = PersistenceStore.diffClubs(from: self.clubs, to: clubs)
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.clubs)
        let oldClubs = self.clubs
        self.clubs = clubs
        if CloudKitSyncManager.isEnabled {
            let deletedClubs = Dictionary(
                oldClubs.filter { oldClub in diff.deletedIds.contains(oldClub.id) }
                    .map { ($0.id, $0.ownerRecordName) },
                uniquingKeysWith: { first, _ in first }
            )
            CloudKitSyncManager.shared.enqueueClubChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedClubs)
        }
    }

    // Roadmap Phase 5 backlog (#162): challenges only exist as a CloudKit
    // concept (a ping between two real CKShare participants), so — unlike
    // saveRoster/saveHistory — there's no KV-store fallback path at all;
    // when CloudKit sync is off, the feature is simply invisible (see the
    // ClubDetailView challenge UI, which is gated behind cloudKitSyncEnabled).
    func saveChallenges(_ challenges: [ChallengeRecord]) {
        guard let encoded = PersistenceStore.encodeChallenges(challenges) else { return }
        let diff = PersistenceStore.diffChallenges(from: self.challenges, to: challenges)
        let deletedChallengeClubIds = Dictionary(
            self.challenges.filter { diff.deletedIds.contains($0.id) }.map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.challenges)
        self.challenges = challenges
        if CloudKitSyncManager.isEnabled {
            CloudKitSyncManager.shared.enqueueChallengeChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedChallengeClubIds)
        }
    }

    // Roadmap Phase 5 backlog (#164): reactions follow saveChallenges'
    // CloudKit-only contract exactly — no KV-store fallback; with CloudKit
    // sync off the reaction UI is read-only over whatever was already synced.
    func saveReactions(_ reactions: [ReactionRecord]) {
        guard let encoded = PersistenceStore.encodeReactions(reactions) else { return }
        let diff = PersistenceStore.diffReactions(from: self.reactions, to: reactions)
        let deletedReactionClubIds = Dictionary(
            self.reactions.filter { diff.deletedIds.contains($0.id) }.map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.reactions)
        self.reactions = reactions
        if CloudKitSyncManager.isEnabled {
            CloudKitSyncManager.shared.enqueueReactionChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedReactionClubIds)
        }
    }

    // Called by CloudSyncManager after external iCloud data lands in UserDefaults
    // (KV path). The CloudKit path uses the targeted apply* methods below instead.
    func reloadFromStorage() {
        let r = UserDefaults.standard.data(forKey: AppStorageKeys.playerRoster) ?? Data()
        let h = UserDefaults.standard.data(forKey: AppStorageKeys.matchHistory) ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
    }

    // MARK: - CloudKit apply (called by CloudKitSyncManager)

    /// Merge remotely-fetched records into the caches by id and persist to the
    /// UserDefaults cache. Targeted (per id) rather than a full re-decode so a
    /// fetch landing mid-edit doesn't clobber an unrelated local change. History
    /// stays date-sorted; roster keeps its stored order (updates in place,
    /// appends new).
    func applyRemoteUpsert(
        records: [MatchRecord], players: [Player], clubs newClubs: [Club],
        challenges newChallenges: [ChallengeRecord] = [],
        reactions newReactions: [ReactionRecord] = []
    ) {
        if !records.isEmpty {
            var byId = Dictionary(history.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for record in records { byId[record.id] = record }
            history = byId.values.sorted { $0.date < $1.date }
            persist(history: history)
        }
        if !players.isEmpty {
            var updated = roster
            var indexById = Dictionary(roster.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for player in players {
                if let idx = indexById[player.id] {
                    updated[idx] = player
                } else {
                    indexById[player.id] = updated.count
                    updated.append(player)
                }
            }
            roster = updated
            persist(roster: roster)
        }
        if !newClubs.isEmpty {
            var updated = clubs
            var indexById = Dictionary(clubs.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for club in newClubs {
                if let idx = indexById[club.id] {
                    updated[idx] = club
                } else {
                    indexById[club.id] = updated.count
                    updated.append(club)
                }
            }
            clubs = updated
            persist(clubs: clubs)
        }
        if !newChallenges.isEmpty {
            var updated = challenges
            var indexById = Dictionary(challenges.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for challenge in newChallenges {
                if let idx = indexById[challenge.id] {
                    updated[idx] = challenge
                } else {
                    indexById[challenge.id] = updated.count
                    updated.append(challenge)
                }
            }
            challenges = updated
            persist(challenges: challenges)
        }
        if !newReactions.isEmpty {
            var updated = reactions
            var indexById = Dictionary(reactions.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for reaction in newReactions {
                if let idx = indexById[reaction.id] {
                    updated[idx] = reaction
                } else {
                    indexById[reaction.id] = updated.count
                    updated.append(reaction)
                }
            }
            reactions = updated
            persist(reactions: reactions)
        }
    }

    /// Remove remotely-deleted records by id from the caches and persist.
    func applyRemoteDeletions(
        recordIds: [UUID], playerIds: [UUID], clubIds: [UUID],
        challengeIds: [UUID] = [], reactionIds: [UUID] = []
    ) {
        if !recordIds.isEmpty {
            let removed = Set(recordIds)
            history = history.filter { !removed.contains($0.id) }
            persist(history: history)
        }
        if !playerIds.isEmpty {
            let removed = Set(playerIds)
            roster = roster.filter { !removed.contains($0.id) }
            persist(roster: roster)
        }
        if !clubIds.isEmpty {
            let removed = Set(clubIds)
            clubs = clubs.filter { !removed.contains($0.id) }
            persist(clubs: clubs)
        }
        if !challengeIds.isEmpty {
            let removed = Set(challengeIds)
            challenges = challenges.filter { !removed.contains($0.id) }
            persist(challenges: challenges)
        }
        if !reactionIds.isEmpty {
            let removed = Set(reactionIds)
            reactions = reactions.filter { !removed.contains($0.id) }
            persist(reactions: reactions)
        }
    }

    private func persist(history records: [MatchRecord]) {
        if let encoded = PersistenceStore.encodeHistory(records) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.matchHistory)
        }
    }

    private func persist(roster players: [Player]) {
        if let encoded = PersistenceStore.encodeRoster(players) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.playerRoster)
        }
    }

    private func persist(clubs: [Club]) {
        if let encoded = PersistenceStore.encodeClubs(clubs) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.clubs)
        }
    }

    private func persist(challenges: [ChallengeRecord]) {
        if let encoded = PersistenceStore.encodeChallenges(challenges) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.challenges)
        }
    }

    private func persist(reactions: [ReactionRecord]) {
        if let encoded = PersistenceStore.encodeReactions(reactions) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.reactions)
        }
    }
}
