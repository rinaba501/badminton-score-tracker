//
//  SyncEngine.swift
//  BadmintonCore
//
//  The outbound half of AppStore's sync boundary: every method AppStore
//  calls to push a local change out to a sync backend. `SupabaseSyncEngine`
//  (both targets) is the real conformer; `NoOpSyncEngine` (below) is the
//  local-only default for a device that has never signed in. This protocol
//  is what let the backend be swapped from CloudKit to Supabase (Roadmap
//  Phase 9, ROADMAP.md/docs/supabase-migration-plan.md) without touching
//  AppStore's call sites — CloudKitSyncManager was the original sole
//  conformer through Phase 9f-2, deleted entirely in 9f-3. The reverse
//  direction — a backend calling back into AppStore.applyRemote* when
//  remote data arrives — is deliberately NOT part of this protocol:
//  AppStore stays a concrete singleton any backend can call into directly,
//  since only the outbound direction needs the polymorphism this seam buys.
//
//  Foundation-only signatures (no SwiftUI/WatchKit types) so this lives in
//  BadmintonCore rather than being duplicated per target, unlike
//  HapticsProvider (which is genuinely per-platform because its haptic-type
//  argument differs). @MainActor because both `SupabaseSyncEngine` and
//  `AppStore` already are.
//

import Foundation

@MainActor
public protocol SyncEngine {
    func enqueueRosterChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID?])
    func enqueueHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID?])
    func enqueueSettingsChange()
    func enqueueClubChanges(upsertedIds: [UUID], deletedIds: [UUID: String?])
    func enqueueChallengeChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID])
    func enqueueReactionChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID])
    func enqueueFriendsRosterChanges(upsertedIds: [UUID], deletedIds: [UUID])
    func enqueueFriendsHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID])
    func enqueueFriendIdentityChange()
    func removeFriendIdentityRecord()
    func enqueueFriendStatsChange()
    /// Mirrors `removeFriendIdentityRecord()`'s shape for stats — added
    /// because an early View call site called into the sync manager
    /// directly rather than through this protocol, a View-bypass bug class
    /// this codebase has hit more than once (see AppStore.swift's own
    /// history of the same fix).
    func removeFriendStatsRecord()
    func deleteFriendsHistoryZone() async
    func deleteMyFriendProfile() async
    func deleteAllMyFriendRequests() async
    /// Roadmap Phase 10a: push a "did this happen?" invite for a just-saved
    /// personal singles `MatchRecord` (`recordId`) whose opponent was picked
    /// from Friends (`opponentParticipantId`). Called from
    /// `AppStore.saveHistory` for every newly-upserted record that qualifies
    /// — see that method's `sourceMatchId == nil` guard, which stops a
    /// *mirrored* record from spawning its own invite chain.
    func enqueueMatchInvite(recordId: UUID, opponentParticipantId: String)
    /// Roadmap Phase 10a: the one call path used both by
    /// `AppStore.autoResolvePendingMatchInvites()`'s silent auto-accept and
    /// by a human tapping Accept-anyway/Ignore in `FriendsView`'s conflict
    /// review — see `AppStore.respondToMatchInvite(_:accept:)`.
    func enqueueMatchInviteResponse(id: UUID, accept: Bool)
    func deleteAllMyMatchInvites() async
}

/// The default for a device that has never signed into Supabase —
/// `AppStore.shared`/`deactivateSupabaseSync()` (both targets) use this.
/// Local-only: saves still work (roster/history/settings persist via
/// `PersistenceStore` as always), nothing leaves the device until an
/// explicit Supabase sign-in swaps `syncEngine` to `SupabaseSyncEngine.shared`.
public struct NoOpSyncEngine: SyncEngine {
    public init() {}

    public func enqueueRosterChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID?]) {}
    public func enqueueHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID?]) {}
    public func enqueueSettingsChange() {}
    public func enqueueClubChanges(upsertedIds: [UUID], deletedIds: [UUID: String?]) {}
    public func enqueueChallengeChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID]) {}
    public func enqueueReactionChanges(upsertedIds: [UUID], deletedIds: [UUID: UUID]) {}
    public func enqueueFriendsRosterChanges(upsertedIds: [UUID], deletedIds: [UUID]) {}
    public func enqueueFriendsHistoryChanges(upsertedIds: [UUID], deletedIds: [UUID]) {}
    public func enqueueFriendIdentityChange() {}
    public func removeFriendIdentityRecord() {}
    public func enqueueFriendStatsChange() {}
    public func removeFriendStatsRecord() {}
    public func deleteFriendsHistoryZone() async {}
    public func deleteMyFriendProfile() async {}
    public func deleteAllMyFriendRequests() async {}
    public func enqueueMatchInvite(recordId: UUID, opponentParticipantId: String) {}
    public func enqueueMatchInviteResponse(id: UUID, accept: Bool) {}
    public func deleteAllMyMatchInvites() async {}
}
