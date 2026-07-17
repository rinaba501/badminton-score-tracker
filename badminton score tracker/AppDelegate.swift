//
//  AppDelegate.swift
//  badminton score tracker (iOS)
//
//  Registers the SceneDelegate class to handle incoming scene connections,
//  enabling CloudKit share acceptance callbacks. Roadmap Phase 7f adds
//  best-effort remote-push registration for the Friends FriendRequest
//  subscription — never required for Friends to work since FriendsView
//  still polls on appear/pull-to-refresh regardless.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    /// App-wide orientation lock, read back to UIKit via
    /// `application(_:supportedInterfaceOrientationsFor:)`. The app is
    /// portrait-only except while GameView shows the landscape-native
    /// Scoreboard style (GameScreenStyle.isLandscape), which flips this to
    /// `.landscape` on appear and back on exit. A static var (not per-view
    /// preference plumbing) because SwiftUI has no per-view orientation API —
    /// the delegate callback is the only hook, and exactly one screen ever
    /// wants non-portrait.
    static var orientationLock: UIInterfaceOrientationMask = .portrait

    /// Sets the lock and asks UIKit to re-evaluate + rotate immediately.
    /// Forcing geometry (not just updating the mask) matters both ways: on
    /// entry the device may be physically portrait, and on exit iOS won't
    /// rotate back on its own if the device is still held sideways.
    static func setOrientation(_ mask: UIInterfaceOrientationMask) {
        orientationLock = mask
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                window.rootViewController?.presentedViewController?
                    .setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

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
        application.registerForRemoteNotifications()
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
