//
//  AppStore.swift
//  badminton score tracker (iOS)
//
//  Cached, decoded roster and history for the iPhone companion app. Views read
//  @Published arrays instead of calling PersistenceStore.decode* on every
//  render. Every save updates the local cache then enqueues precise
//  per-record upserts/deletes through CloudKitSyncManager — the only sync
//  path. Mirrors the Watch App's AppStore.
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
    /// Friends' shared personal roster/history, keyed by their participantId
    /// — mirrored in from each friend's own "FriendsHistory" CKShare zone
    /// once SettingsSnapshot.shareHistoryWithFriends is on (see
    /// CloudKitSyncManager.applyFetched's friends-zone branch). Deliberately
    /// separate from `roster`/`history`: this is someone else's data, shown
    /// read-only, and must never be merged into the viewer's own caches or
    /// stats.
    @Published private(set) var friendActivity: [String: FriendHistorySnapshot]
    /// Friends' shared profile identity fields (avatar/gender/birthday/
    /// introduction), keyed by participantId — same "never merged into your
    /// own data" contract as `friendActivity`, mirrored from each friend's
    /// "FriendIdentity" record. See FriendIdentitySnapshot.swift.
    @Published private(set) var friendIdentities: [String: FriendIdentitySnapshot]
    /// Friends' shared derived stats, keyed by participantId — same contract
    /// as `friendIdentities`, mirrored from each friend's "FriendStats"
    /// record. See FriendStatsSnapshot.swift.
    @Published private(set) var friendStats: [String: FriendStatsSnapshot]

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
        let fr = UserDefaults.standard.data(forKey: AppStorageKeys.friendRequests) ?? Data()
        let fa = UserDefaults.standard.data(forKey: AppStorageKeys.friendActivity) ?? Data()
        let fi = UserDefaults.standard.data(forKey: AppStorageKeys.friendIdentities) ?? Data()
        let fs = UserDefaults.standard.data(forKey: AppStorageKeys.friendStats) ?? Data()
        roster = PersistenceStore.decodeRoster(r)
        history = PersistenceStore.decodeHistory(h)
        clubs = PersistenceStore.decodeClubs(c)
        challenges = PersistenceStore.decodeChallenges(ch)
        reactions = PersistenceStore.decodeReactions(re)
        friendRequests = PersistenceStore.decodeFriendRequests(fr)
        friendActivity = Dictionary(
            uniqueKeysWithValues: PersistenceStore.decodeFriendActivity(fa).map { ($0.participantId, $0) }
        )
        friendIdentities = Dictionary(
            uniqueKeysWithValues: PersistenceStore.decodeFriendIdentities(fi).map { ($0.participantId, $0) }
        )
        friendStats = Dictionary(
            uniqueKeysWithValues: PersistenceStore.decodeFriendStats(fs).map { ($0.participantId, $0) }
        )
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

        if isSharingHistoryWithFriends {
            let newClubIds = Dictionary(players.map { ($0.id, $0.clubId) }, uniquingKeysWith: { first, _ in first })
            let personalUpserts = personalIds(among: diff.upsertedIds, clubIds: newClubIds)
            let personalDeletes = personalIds(among: diff.deletedIds, clubIds: deletedClubIds)
            if !personalUpserts.isEmpty || !personalDeletes.isEmpty {
                CloudKitSyncManager.shared.enqueueFriendsRosterChanges(upsertedIds: personalUpserts, deletedIds: personalDeletes)
            }
        }
        // Avatar is the one identity sub-field stored on the roster (the "Me"
        // player) rather than SettingsSnapshot — only re-mirror when that
        // player actually changed, not on every roster edit.
        if diff.upsertedIds.contains(localPlayerId) || diff.deletedIds.contains(localPlayerId) {
            refreshMyIdentitySnapshotIfSharing()
        }
        if isSharingStatsWithFriends {
            CloudKitSyncManager.shared.enqueueFriendStatsChange()
        }
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

        if isSharingHistoryWithFriends {
            let newClubIds = Dictionary(records.map { ($0.id, $0.clubId) }, uniquingKeysWith: { first, _ in first })
            let personalUpserts = personalIds(among: diff.upsertedIds, clubIds: newClubIds)
            let personalDeletes = personalIds(among: diff.deletedIds, clubIds: deletedClubIds)
            if !personalUpserts.isEmpty || !personalDeletes.isEmpty {
                CloudKitSyncManager.shared.enqueueFriendsHistoryChanges(upsertedIds: personalUpserts, deletedIds: personalDeletes)
            }
        }
        if isSharingStatsWithFriends {
            CloudKitSyncManager.shared.enqueueFriendStatsChange()
        }
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

        if isSharingHistoryWithFriends {
            let personalDeletes = personalIds(among: Array(deletedClubIds.keys), clubIds: deletedClubIds)
            if !personalDeletes.isEmpty {
                CloudKitSyncManager.shared.enqueueFriendsHistoryChanges(upsertedIds: [], deletedIds: personalDeletes)
            }
        }
        if isSharingStatsWithFriends {
            CloudKitSyncManager.shared.enqueueFriendStatsChange()
        }
    }

    /// Erase All My Data (#264): wipes every local + CloudKit-synced record
    /// this account owns — roster, history, clubs (deletes owned clubs
    /// outright, leaves joined clubs via the existing `saveClubs` diffing),
    /// challenges, reactions, the Friends graph (public-DB FriendRequest/
    /// FriendProfile records plus the FriendsHistory share zone), and every
    /// scalar setting (`AppStorageKeys.eraseAllDataResetKeys`) — so the app
    /// reads back as a fresh install. Deliberately leaves CloudKit-transport
    /// bookkeeping (ckSyncEngineState/ckRecordMetadata/etc.) untouched:
    /// deletions flow through the already-running CKSyncEngine instances
    /// exactly like any other delete, so there's no need to tear down or
    /// rebuild them.
    func eraseAllData() async {
        // Reset the share*WithFriends/shareStatsWithFriends toggles (part of
        // eraseAllDataResetKeys) BEFORE calling saveRoster/clearHistory below:
        // those methods re-enqueue a FriendStats/FriendIdentity save into the
        // FriendsHistory zone whenever sharing is on, which would otherwise
        // race the deleteFriendsHistoryZone() call just below it — the save
        // and the zone delete would both be pending on the same sync engine
        // with no guaranteed ordering, risking a save "winning" and leaving
        // the zone non-empty. Resetting the toggles first makes
        // isSharingHistoryWithFriends/isSharingStatsWithFriends read false,
        // so saveRoster/clearHistory never re-enqueue anything into the zone
        // this method is about to tear down.
        for key in AppStorageKeys.eraseAllDataResetKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        saveRoster([])
        clearHistory()
        saveClubs([])
        saveChallenges([])
        saveReactions([])

        await CloudKitSyncManager.shared.deleteAllMyFriendRequests()
        saveFriendRequests([])
        await CloudKitSyncManager.shared.deleteMyFriendProfile()
        await CloudKitSyncManager.shared.deleteFriendsHistoryZone()

        CloudKitSyncManager.shared.enqueueSettingsChange()
    }

    private var isSharingHistoryWithFriends: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.shareHistoryWithFriends)
    }

    var isSharingAnyFriendIdentityField: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: AppStorageKeys.shareAvatarWithFriends)
            || defaults.bool(forKey: AppStorageKeys.shareGenderWithFriends)
            || defaults.bool(forKey: AppStorageKeys.shareBirthdayWithFriends)
            || defaults.bool(forKey: AppStorageKeys.shareIntroductionWithFriends)
    }

    var isSharingStatsWithFriends: Bool {
        UserDefaults.standard.bool(forKey: AppStorageKeys.shareStatsWithFriends)
    }

    /// Whether any of the six per-field friend-sharing toggles is on — the
    /// FriendsHistory share/zone and its participant list must exist
    /// whenever this is true, and get torn down only when every toggle
    /// (including shareHistoryWithFriends) is off. See CloudKitSyncManager's
    /// ensureFriendsHistoryShareExists/syncFriendsHistoryParticipants/
    /// revokeFriendsHistoryAccess.
    var isSharingAnyProfileData: Bool {
        isSharingAnyFriendIdentityField || isSharingStatsWithFriends || isSharingHistoryWithFriends
    }

    /// Recomputes and re-enqueues this device's own "FriendIdentity" record
    /// if any identity sub-field toggle is on — call after a SettingsSnapshot
    /// identity field (gender/birthday/introduction) or its toggle changes,
    /// so the mirror stays in sync without duplicating the per-field gating
    /// logic at every call site.
    func refreshMyIdentitySnapshotIfSharing() {
        if isSharingAnyFriendIdentityField {
            CloudKitSyncManager.shared.enqueueFriendIdentityChange()
        } else {
            CloudKitSyncManager.shared.removeFriendIdentityRecord()
        }
    }

    /// Ids whose (new, for upserts; old, for deletes) clubId is nil —
    /// personal records are the only ones mirrored into "FriendsHistory".
    private func personalIds(among ids: [UUID], clubIds: [UUID: UUID?]) -> [UUID] {
        ids.filter { clubIds[$0].flatMap { $0 } == nil }
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
        pruneFriendActivityToCurrentFriends()
    }

    /// Drops any cached `friendActivity` entry for a participantId no longer
    /// in the accepted-friends graph (e.g. a declined/no-longer-accepted
    /// request) — a friend's shared history must stop being visible the
    /// moment they're no longer a friend, even before the next CloudKit fetch.
    private func pruneFriendActivityToCurrentFriends() {
        let friendIds = Set(friends.map(\.participantId))
        let staleActivity = friendActivity.keys.filter { !friendIds.contains($0) }
        if !staleActivity.isEmpty {
            for id in staleActivity { friendActivity[id] = nil }
            persist(friendActivity: Array(friendActivity.values))
        }
        let staleIdentities = friendIdentities.keys.filter { !friendIds.contains($0) }
        if !staleIdentities.isEmpty {
            for id in staleIdentities { friendIdentities[id] = nil }
            persist(friendIdentities: Array(friendIdentities.values))
        }
        let staleStats = friendStats.keys.filter { !friendIds.contains($0) }
        if !staleStats.isEmpty {
            for id in staleStats { friendStats[id] = nil }
            persist(friendStats: Array(friendStats.values))
        }
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
        defaults.set(snapshot.courtChangeRemindersEnabled, forKey: AppStorageKeys.courtChangeRemindersEnabled)
        defaults.set(snapshot.accountLinked, forKey: AppStorageKeys.accountLinked)
        defaults.set(snapshot.gameScreenStyle, forKey: AppStorageKeys.gameScreenStyle)
        defaults.set(snapshot.shareHistoryWithFriends, forKey: AppStorageKeys.shareHistoryWithFriends)
        defaults.set(snapshot.shareAvatarWithFriends, forKey: AppStorageKeys.shareAvatarWithFriends)
        defaults.set(snapshot.shareGenderWithFriends, forKey: AppStorageKeys.shareGenderWithFriends)
        defaults.set(snapshot.shareBirthdayWithFriends, forKey: AppStorageKeys.shareBirthdayWithFriends)
        defaults.set(snapshot.shareIntroductionWithFriends, forKey: AppStorageKeys.shareIntroductionWithFriends)
        defaults.set(snapshot.shareStatsWithFriends, forKey: AppStorageKeys.shareStatsWithFriends)
        if let gender = snapshot.gender {
            defaults.set(gender, forKey: AppStorageKeys.gender)
        } else {
            defaults.removeObject(forKey: AppStorageKeys.gender)
        }
        if let birthday = snapshot.birthday {
            defaults.set(birthday, forKey: AppStorageKeys.birthday)
        } else {
            defaults.removeObject(forKey: AppStorageKeys.birthday)
        }
        if let introduction = snapshot.introduction {
            defaults.set(introduction, forKey: AppStorageKeys.introduction)
        } else {
            defaults.removeObject(forKey: AppStorageKeys.introduction)
        }
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

    /// Merges a friend's shared roster/history into their `friendActivity`
    /// snapshot. Never touches `roster`/`history` — this is someone else's
    /// data (see the `friendActivity` doc comment). `participantId` is the
    /// owning friend's, i.e. the fetched zone's `ownerName`.
    func applyRemoteFriendActivity(participantId: String, matches: [MatchRecord], players: [Player]) {
        guard !matches.isEmpty || !players.isEmpty else { return }
        let displayName = friends.first { $0.participantId == participantId }?.displayName
            ?? friendActivity[participantId]?.displayName
            ?? participantId
        var snapshot = friendActivity[participantId] ?? FriendHistorySnapshot(participantId: participantId, displayName: displayName)
        snapshot.displayName = displayName

        if !matches.isEmpty {
            var byId = Dictionary(snapshot.history.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            for match in matches { byId[match.id] = match }
            snapshot.history = byId.values.sorted { $0.date < $1.date }
        }
        if !players.isEmpty {
            var updated = snapshot.roster
            var indexById = Dictionary(snapshot.roster.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for player in players {
                if let idx = indexById[player.id] {
                    updated[idx] = player
                } else {
                    indexById[player.id] = updated.count
                    updated.append(player)
                }
            }
            snapshot.roster = updated
        }

        friendActivity[participantId] = snapshot
        persist(friendActivity: Array(friendActivity.values))
    }

    /// Removes remotely-deleted records from a friend's `friendActivity`
    /// snapshot.
    func applyRemoteFriendActivityDeletions(participantId: String, matchIds: [UUID], playerIds: [UUID]) {
        guard var snapshot = friendActivity[participantId], !matchIds.isEmpty || !playerIds.isEmpty else { return }
        if !matchIds.isEmpty {
            let removed = Set(matchIds)
            snapshot.history = snapshot.history.filter { !removed.contains($0.id) }
        }
        if !playerIds.isEmpty {
            let removed = Set(playerIds)
            snapshot.roster = snapshot.roster.filter { !removed.contains($0.id) }
        }
        friendActivity[participantId] = snapshot
        persist(friendActivity: Array(friendActivity.values))
    }

    /// Replaces a friend's cached identity snapshot wholesale — unlike
    /// `applyRemoteFriendActivity`'s per-record merge, the "FriendIdentity"
    /// record is a single record carrying every field, so the fetched
    /// snapshot always supersedes what's cached.
    func applyRemoteFriendIdentity(participantId: String, snapshot: FriendIdentitySnapshot) {
        friendIdentities[participantId] = snapshot
        persist(friendIdentities: Array(friendIdentities.values))
    }

    /// Removes a friend's cached identity snapshot — the owner deleted their
    /// "FriendIdentity" record (every identity toggle turned off).
    func applyRemoteFriendIdentityDeletion(participantId: String) {
        guard friendIdentities[participantId] != nil else { return }
        friendIdentities[participantId] = nil
        persist(friendIdentities: Array(friendIdentities.values))
    }

    /// Replaces a friend's cached stats snapshot wholesale, same contract as
    /// `applyRemoteFriendIdentity`.
    func applyRemoteFriendStats(participantId: String, snapshot: FriendStatsSnapshot) {
        friendStats[participantId] = snapshot
        persist(friendStats: Array(friendStats.values))
    }

    /// Removes a friend's cached stats snapshot — the owner deleted their
    /// "FriendStats" record (shareStatsWithFriends turned off).
    func applyRemoteFriendStatsDeletion(participantId: String) {
        guard friendStats[participantId] != nil else { return }
        friendStats[participantId] = nil
        persist(friendStats: Array(friendStats.values))
    }

    private func persist(friendActivity snapshots: [FriendHistorySnapshot]) {
        if let encoded = PersistenceStore.encodeFriendActivity(snapshots) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.friendActivity)
        }
    }

    private func persist(friendIdentities snapshots: [FriendIdentitySnapshot]) {
        if let encoded = PersistenceStore.encodeFriendIdentities(snapshots) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.friendIdentities)
        }
    }

    private func persist(friendStats snapshots: [FriendStatsSnapshot]) {
        if let encoded = PersistenceStore.encodeFriendStats(snapshots) {
            UserDefaults.standard.set(encoded, forKey: AppStorageKeys.friendStats)
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
