//
//  WatchAppDelegate.swift
//  badminton score tracker Watch App
//
//  WKApplicationDelegate implementation for watchOS to catch and handle
//  CloudKit share acceptance events. Roadmap Phase 7f adds best-effort
//  remote-push registration for the Friends FriendRequest subscription —
//  never required for Friends to work since FriendsView still polls on
//  appear/pull-to-refresh regardless.
//

import WatchKit
import CloudKit

class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func userDidAcceptCloudKitShare(with cloudKitShareMetadata: CKShare.Metadata) {
        CloudKitSyncManager.shared.acceptShare(metadata: cloudKitShareMetadata)
    }

    func applicationDidFinishLaunching() {
        WKExtension.shared().registerForRemoteNotifications()
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        Task { await CloudKitSyncManager.shared.ensureFriendRequestSubscriptionExists() }
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {}

    func didReceiveRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        guard let requests = try? await CloudKitSyncManager.shared.fetchMyFriendRequests() else { return .failed }
        await AppStore.shared.saveFriendRequests(requests)
        return .newData
    }
}
