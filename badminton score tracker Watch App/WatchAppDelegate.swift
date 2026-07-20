//
//  WatchAppDelegate.swift
//  badminton score tracker Watch App
//
//  WKApplicationDelegate implementation for watchOS to catch and handle
//  CloudKit share acceptance events. Roadmap Phase 7f adds best-effort
//  remote-push registration for the Friends FriendRequest subscription —
//  never required for Friends to work since FriendsView still polls on
//  appear/pull-to-refresh regardless. Also activates WCSession to receive a
//  Supabase session relayed from the iPhone (Roadmap Phase 9c,
//  docs/supabase-migration-plan.md) — watchOS has no in-app browser, so it
//  never performs Google OAuth itself, only adopts a session handed off by
//  the paired phone.
//

import WatchKit
import CloudKit
import WatchConnectivity
import BadmintonCore
import CloudSyncSpike

class WatchAppDelegate: NSObject, WKApplicationDelegate, WCSessionDelegate {
    func userDidAcceptCloudKitShare(with cloudKitShareMetadata: CKShare.Metadata) {
        CloudKitSyncManager.shared.acceptShare(metadata: cloudKitShareMetadata)
    }

    func applicationDidFinishLaunching() {
        WKExtension.shared().registerForRemoteNotifications()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        logSync("Watch WCSession activated=\(activationState == .activated) error=\(error?.localizedDescription ?? "none")")
    }

    /// Two relay paths land here: `transferUserInfo` (queued, delivered once
    /// reachable) and `sendMessage` (immediate, only when reachable now).
    /// Spike testing (see git history) found `sendMessage` was the one that
    /// actually delivered Simulator-to-Simulator; both are kept since real
    /// hardware may differ — see AppDelegate.relaySessionToWatch.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        logSync("Watch received userInfo relay")
        adoptSession(from: userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        logSync("Watch received sendMessage relay")
        adoptSession(from: message)
        replyHandler(["received": true])
    }

    private func adoptSession(from payload: [String: Any]) {
        guard let accessToken = payload["accessToken"] as? String,
              let refreshToken = payload["refreshToken"] as? String else { return }
        Task { await SupabaseSyncManager.shared.adoptRelayedSession(accessToken: accessToken, refreshToken: refreshToken) }
    }

    private func logSync(_ message: String) {
        Task { @MainActor in SupabaseSyncManager.shared.logDiagnostic(message) }
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        // Roadmap Phase 9f-2: gated on !supabaseAccountLinked — this used to
        // run unconditionally on every device, registering a CloudKit push
        // subscription even for Supabase-active devices that never write to
        // CloudKit at all.
        guard !UserDefaults.standard.bool(forKey: AppStorageKeys.supabaseAccountLinked) else { return }
        Task { await CloudKitSyncManager.shared.ensureFriendRequestSubscriptionExists() }
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {}

    // Roadmap Phase 9f-2: gated on !supabaseAccountLinked — this used to
    // unconditionally overwrite AppStore.friendRequests with a CloudKit
    // fetch on every push, which is a full reconcile (not a merge). A stray
    // push on a Supabase-active device (e.g. a leftover subscription from
    // before this device switched) would have silently wiped the real,
    // Supabase-sourced friends list.
    nonisolated func didReceiveRemoteNotification(_ userInfo: sending [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        guard !UserDefaults.standard.bool(forKey: AppStorageKeys.supabaseAccountLinked) else { return .noData }
        guard let requests = try? await CloudKitSyncManager.shared.fetchMyFriendRequests() else { return .failed }
        await AppStore.shared.saveFriendRequests(requests)
        return .newData
    }
}
