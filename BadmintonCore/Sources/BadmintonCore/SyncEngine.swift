//
//  SyncEngine.swift
//  BadmintonCore
//
//  The outbound half of AppStore's sync boundary: every method AppStore
//  calls to push a local change out to a sync backend. CloudKitSyncManager
//  (both targets) is the only conformer today; Phase 9 (ROADMAP.md,
//  docs/supabase-migration-plan.md) will add a Supabase-backed one. The
//  reverse direction — a backend calling back into AppStore.applyRemote*
//  when remote data arrives — is deliberately NOT part of this protocol:
//  AppStore stays a concrete singleton any backend can call into directly,
//  since only the outbound direction needs polymorphism to let 9c swap
//  backends without touching AppStore's call sites again.
//
//  Foundation-only signatures (no CloudKit/SwiftUI/WatchKit types) so this
//  lives in BadmintonCore rather than being duplicated per target, unlike
//  HapticsProvider (which is genuinely per-platform because its haptic-type
//  argument differs). @MainActor because both CloudKitSyncManager and
//  AppStore already are.
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
    func deleteFriendsHistoryZone() async
    func deleteMyFriendProfile() async
    func deleteAllMyFriendRequests() async
}

/// Test double — no call site yet, kept for future AppStore unit tests, same
/// precedent as HapticsProvider's currently-unused iOS NoOpHapticsProvider.
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
    public func deleteFriendsHistoryZone() async {}
    public func deleteMyFriendProfile() async {}
    public func deleteAllMyFriendRequests() async {}
}
