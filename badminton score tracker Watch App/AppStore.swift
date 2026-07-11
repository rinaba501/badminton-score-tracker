//
//  AppStore.swift
//  badminton score tracker Watch App
//
//  Cached, decoded roster and history. Views read @Published arrays instead
//  of calling PersistenceStore.decode* on every render.
//

import Foundation
import SwiftUI
import BadmintonCore

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published private(set) var roster: [Player]
    @Published private(set) var history: [MatchRecord]
    @Published private(set) var clubs: [Club]
    /// Roadmap Phase 5 backlog (#162): CloudKit-only — there's no meaningful
    /// "personal" challenge, so unlike roster/history there's no KV fallback
    /// at all (see saveChallenges).
    @Published private(set) var challenges: [ChallengeRecord]
    /// Roadmap Phase 5 backlog (#164): CloudKit-only, same contract as
    /// `challenges` — no KV fallback (see saveReactions).
    @Published private(set) var reactions: [ReactionRecord]
    /// Friends v1 (graph-only, #7c): public-database CloudKit only — unlike
    /// challenges/reactions (club-scoped, still synced via CKSyncEngine's
    /// shared/private DB `enqueue*` path), friend-request writes bypass
    /// CKSyncEngine entirely and go straight to the public DB via
    /// `CloudKitSyncManager.sendFriendRequest`/`respondToFriendRequest` (see
    /// saveFriendRequests). This cache is updated only after such a direct
    /// call succeeds, or after a `fetchMyFriendRequests()` poll.
    @Published private(set) var friendRequests: [FriendRequest]

    /// Accepted friend requests, derived — Friends v1 has no separate
    /// `Friendship` record (see `FriendRequest.swift`).
    var friends: [(participantId: String, displayName: String)] {
        friendRequests.compactMap { request in
            guard request.status == .accepted else { return nil }
            guard let myId = UserDefaults.standard.string(forKey: AppStorageKeys.myParticipantId) else { return nil }
            if request.fromParticipantId == myId {
                return (request.toParticipantId, request.toDisplayName)
            } else if request.toParticipantId == myId {
                return (request.fromParticipantId, request.fromDisplayName)
            }
            return nil
        }
    }

    @AppStorage(AppStorageKeys.localPlayerId) private var localPlayerIdString: String = ""

    /// A stable identity for the local user, independent of their display
    /// name (which can be renamed) and independent of the roster ("me" is
    /// deliberately never added there — see `Player.shouldBeStoredAsSavedPlayer`).
    /// Generated once on first access and persisted thereafter.
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
        let fr = UserDefaults.standard.data(forKey: AppStorageKeys.friendRequests) ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
        clubs = PersistenceStore.decodeClubs(c)
        challenges = PersistenceStore.decodeChallenges(ch)
        reactions = PersistenceStore.decodeReactions(re)
        friendRequests = PersistenceStore.decodeFriendRequests(fr)
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

    // Each save updates the local cache + UserDefaults, then enqueues precise
    // per-record upserts/deletes to CloudKitSyncManager — the only sync path.
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
        CloudKitSyncManager.shared.enqueueRosterChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedClubIds)
        CloudKitSyncManager.shared.enqueueSettingsChange()
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
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.matchHistory)
        history = records
        CloudKitSyncManager.shared.enqueueHistoryChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedClubIds)
        CloudKitSyncManager.shared.enqueueSettingsChange()
    }

    func clearHistory() {
        let deletedClubIds = Dictionary(
            history.map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(Data(), forKey: AppStorageKeys.matchHistory)
        history = []
        CloudKitSyncManager.shared.enqueueHistoryChanges(upsertedIds: [], deletedIds: deletedClubIds)
        CloudKitSyncManager.shared.enqueueSettingsChange()
    }

    // Roadmap Phase 5b/c: a Club only becomes a real shared group
    // once Phase 5c wires it to a CloudKit CKShare zone.
    func saveClubs(_ clubs: [Club]) {
        guard let encoded = PersistenceStore.encodeClubs(clubs) else { return }
        let diff = PersistenceStore.diffClubs(from: self.clubs, to: clubs)
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.clubs)
        let oldClubs = self.clubs
        self.clubs = clubs
        let deletedClubs = Dictionary(
            oldClubs.filter { oldClub in diff.deletedIds.contains(oldClub.id) }
                .map { ($0.id, $0.ownerRecordName) },
            uniquingKeysWith: { first, _ in first }
        )
        CloudKitSyncManager.shared.enqueueClubChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedClubs)
    }

    // Roadmap Phase 5 backlog (#162): challenges only exist as a CloudKit
    // concept (a ping between two real CKShare participants) — no
    // "personal" challenge, so unlike roster/history there's no local-only
    // state to reconcile.
    func saveChallenges(_ challenges: [ChallengeRecord]) {
        guard let encoded = PersistenceStore.encodeChallenges(challenges) else { return }
        let diff = PersistenceStore.diffChallenges(from: self.challenges, to: challenges)
        let deletedChallengeClubIds = Dictionary(
            self.challenges.filter { diff.deletedIds.contains($0.id) }.map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.challenges)
        self.challenges = challenges
        CloudKitSyncManager.shared.enqueueChallengeChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedChallengeClubIds)
    }

    // Roadmap Phase 5 backlog (#164): reactions follow saveChallenges'
    // CloudKit-only contract.
    func saveReactions(_ reactions: [ReactionRecord]) {
        guard let encoded = PersistenceStore.encodeReactions(reactions) else { return }
        let diff = PersistenceStore.diffReactions(from: self.reactions, to: reactions)
        let deletedReactionClubIds = Dictionary(
            self.reactions.filter { diff.deletedIds.contains($0.id) }.map { ($0.id, $0.clubId) },
            uniquingKeysWith: { first, _ in first }
        )
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.reactions)
        self.reactions = reactions
        CloudKitSyncManager.shared.enqueueReactionChanges(upsertedIds: diff.upsertedIds, deletedIds: deletedReactionClubIds)
    }

    // Friends v1 (#7c): unlike every other save* method here, this does NOT
    // enqueue to CloudKitSyncManager's CKSyncEngine — friend requests live in
    // the public database, which has no CKSyncEngine of its own (see
    // CloudKitSyncManager's "Friends" section). The actual network write
    // already happened via a direct sendFriendRequest/respondToFriendRequest
    // call (or a fetchMyFriendRequests() poll); this just reconciles the
    // local cache to match afterward, the same shape as applyRemoteUpsert
    // but driven by a poll result instead of a CKSyncEngine event.
    func saveFriendRequests(_ friendRequests: [FriendRequest]) {
        guard let encoded = PersistenceStore.encodeFriendRequests(friendRequests) else { return }
        UserDefaults.standard.set(encoded, forKey: AppStorageKeys.friendRequests)
        self.friendRequests = friendRequests
    }

    /// Writes a remotely-fetched settings snapshot straight to UserDefaults.
    /// `@AppStorage` observes external `UserDefaults` writes via KVO, so
    /// every view bound to these keys stays reactive with no further wiring.
    /// Empty/invalid `localPlayerId` is ignored so a device that materializes
    /// Settings before generating an id cannot wipe a valid "Me" identity.
    func applyRemoteSettings(_ snapshot: SettingsSnapshot) {
        let defaults = UserDefaults.standard
        defaults.set(snapshot.myName, forKey: AppStorageKeys.myName)
        if UUID(uuidString: snapshot.localPlayerId) != nil {
            defaults.set(snapshot.localPlayerId, forKey: AppStorageKeys.localPlayerId)
        }
        defaults.set(snapshot.pointsToWin, forKey: AppStorageKeys.pointsToWin)
        defaults.set(snapshot.gamesInMatch, forKey: AppStorageKeys.gamesInMatch)
        defaults.set(snapshot.courtTheme, forKey: AppStorageKeys.courtTheme)
        defaults.set(snapshot.announceScore, forKey: AppStorageKeys.announceScore)
        defaults.set(snapshot.enableSounds, forKey: AppStorageKeys.enableSounds)
        defaults.set(snapshot.enableCrownScoring, forKey: AppStorageKeys.enableCrownScoring)
        defaults.set(snapshot.timeModeEnabled, forKey: AppStorageKeys.timeModeEnabled)
        defaults.set(snapshot.timeLimitMinutes, forKey: AppStorageKeys.timeLimitMinutes)
        defaults.set(snapshot.myFriendsDisplayName, forKey: AppStorageKeys.myFriendsDisplayName)
        // Merge (per-club max), never overwrite: two devices can mark different
        // clubs viewed before their Settings records converge, and a blind
        // overwrite would re-raise an unread dot the user already cleared.
        var merged = ClubActivityCodec.decode(defaults.data(forKey: AppStorageKeys.clubLastViewedActivity) ?? Data())
        for (clubId, remoteDate) in snapshot.clubLastViewedActivity {
            merged[clubId] = max(merged[clubId] ?? .distantPast, remoteDate)
        }
        defaults.set(ClubActivityCodec.encode(merged), forKey: AppStorageKeys.clubLastViewedActivity)
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
