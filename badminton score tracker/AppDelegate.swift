//
//  AppDelegate.swift
//  badminton score tracker (iOS)
//
//  Activates WCSession to relay a signed-in Supabase session to the paired
//  watch (docs/supabase-migration-plan.md) — the phone always performs the
//  actual Google OAuth handshake; the watch only ever adopts a relayed
//  session, since watchOS has no in-app browser. Also owns the app-wide
//  orientation lock (#252) since UIKit's rotation hooks only exist on
//  UIApplicationDelegate, not in SwiftUI.
//

import UIKit
import WatchConnectivity
import CloudSyncSpike

class AppDelegate: NSObject, UIApplicationDelegate, WCSessionDelegate {
    /// Relays over two paths: `transferUserInfo` (queued, delivered whenever
    /// the watch next becomes reachable — may take a while) and, when the
    /// watch is reachable right now, `sendMessage` too. Spike testing (see
    /// git history) found `transferUserInfo` alone didn't reliably deliver
    /// Simulator-to-Simulator, while `sendMessage` did; keeping both covers
    /// real hardware whichever way its reliability differs.
    static func relaySessionToWatch(tokens: [String: Any]) {
        let session = WCSession.default
        let activated = session.activationState == .activated
        logSync(
            "WCSession: supported=\(WCSession.isSupported()) activated=\(activated) "
            + "paired=\(session.isPaired) watchAppInstalled=\(session.isWatchAppInstalled) reachable=\(session.isReachable)"
        )
        guard WCSession.isSupported(), activated else { return }

        session.transferUserInfo(tokens)
        logSync("transferUserInfo queued")

        guard session.isReachable else { return }
        session.sendMessage(tokens, replyHandler: { _ in
            logSync("sendMessage: watch replied")
        }, errorHandler: { error in
            logSync("sendMessage failed: \(error.localizedDescription)")
        })
    }

    private static func logSync(_ message: String) {
        Task { @MainActor in SupabaseSyncManager.shared.logDiagnostic(message) }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

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
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
        return true
    }
}
