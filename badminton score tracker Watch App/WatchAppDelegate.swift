//
//  WatchAppDelegate.swift
//  badminton score tracker Watch App
//
//  WKApplicationDelegate implementation for watchOS to catch and handle
//  CloudKit share acceptance events. Roadmap Phase 7f adds best-effort
//  remote-push registration for the Friends FriendRequest subscription —
//  never required for Friends to work since FriendsView still polls on
//  appear/pull-to-refresh regardless. Also activates WCSession to receive a
//  Supabase session relayed from the iPhone for the CloudSyncSpike
//  feasibility experiment (CLAUDE.md) — watchOS has no in-app browser, so it
//  never performs Google OAuth itself, only adopts a session handed off by
//  the paired phone.
//

import WatchKit
import CloudKit
import WatchConnectivity
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
        logToSpike("Watch WCSession activated=\(activationState == .activated) error=\(error?.localizedDescription ?? "none")")
    }

    /// Two relay paths land here: `transferUserInfo` (queued, delivered once
    /// reachable) and `sendMessage` (immediate, only when reachable now).
    /// Spike testing found `sendMessage` was the one that actually delivered
    /// Simulator-to-Simulator; both are kept since real hardware may differ —
    /// see AppDelegate.relaySessionToWatch.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        logToSpike("Watch received userInfo relay")
        adoptSession(from: userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        logToSpike("Watch received sendMessage relay")
        adoptSession(from: message)
        replyHandler(["received": true])
    }

    private func adoptSession(from payload: [String: Any]) {
        guard let accessToken = payload["accessToken"] as? String,
              let refreshToken = payload["refreshToken"] as? String else { return }
        Task { await SupabaseSpikeClient.shared.adoptRelayedSession(accessToken: accessToken, refreshToken: refreshToken) }
    }

    private func logToSpike(_ message: String) {
        Task { @MainActor in SupabaseSpikeClient.shared.logDiagnostic(message) }
    }

    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        Task { await CloudKitSyncManager.shared.ensureFriendRequestSubscriptionExists() }
    }

    func didFailToRegisterForRemoteNotificationsWithError(_ error: Error) {}

    nonisolated func didReceiveRemoteNotification(_ userInfo: sending [AnyHashable: Any]) async -> WKBackgroundFetchResult {
        guard let requests = try? await CloudKitSyncManager.shared.fetchMyFriendRequests() else { return .failed }
        await AppStore.shared.saveFriendRequests(requests)
        return .newData
    }
}
