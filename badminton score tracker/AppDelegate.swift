//
//  AppDelegate.swift
//  badminton score tracker (iOS)
//
//  Registers the SceneDelegate class to handle incoming scene connections,
//  enabling CloudKit share acceptance callbacks. Roadmap Phase 7f adds
//  best-effort remote-push registration for the Friends FriendRequest
//  subscription — gated behind cloudKitSyncEnabled, and never required for
//  Friends to work since FriendsView still polls on appear/pull-to-refresh
//  regardless.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if CloudKitSyncManager.isEnabled {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await CloudKitSyncManager.shared.ensureFriendRequestSubscriptionExists() }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task {
            guard let requests = try? await CloudKitSyncManager.shared.fetchMyFriendRequests() else {
                completionHandler(.failed)
                return
            }
            await AppStore.shared.saveFriendRequests(requests)
            completionHandler(.newData)
        }
    }
}
