//
//  badminton_score_trackerApp.swift
//  badminton score tracker Watch App
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//

import SwiftUI
import BadmintonCore

@main
struct badminton_score_tracker_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate

    init() {
        // Roadmap Phase 9f-1: CloudKit is no longer started at launch —
        // AppStore.shared now defaults an unlinked device to NoOpSyncEngine
        // (local-only) rather than CloudKitSyncManager.
        Task { @MainActor in
            StoreManager.shared.start()
            // Phase 9c-6: reconnect this device's Realtime subscription +
            // catch-up pull if it was left Supabase-linked from a prior
            // session — the common case (not yet signed in) skips this
            // entirely.
            if UserDefaults.standard.bool(forKey: AppStorageKeys.supabaseAccountLinked) {
                SupabaseSyncEngine.shared.startIfActive()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppStore.shared)
                .environmentObject(StoreManager.shared)
                .onOpenURL { url in
                    guard url.scheme == "badminton", url.host == "newmatch" else { return }
                    NotificationCenter.default.post(name: .startNewMatch, object: nil)
                }
        }
    }
}

extension Notification.Name {
    static let startNewMatch = Notification.Name("startNewMatch")
}
