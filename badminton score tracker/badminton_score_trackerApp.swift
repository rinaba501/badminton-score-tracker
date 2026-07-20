//
//  badminton_score_trackerApp.swift
//  badminton score tracker (iOS)
//
//  Entry point for the iPhone companion app (ROADMAP Phase 6, #41).
//  Injects the shared AppStore so the phone reads the same history/roster/
//  settings the Watch writes. Roadmap Phase 9f-1: no longer starts CloudKit
//  sync here — an unlinked device is local-only (NoOpSyncEngine) until an
//  explicit Supabase sign-in. The Watch remains the richest scoring device;
//  the phone also has its own live-scoring flow.
//

import SwiftUI
import BadmintonCore

@main
struct BadmintonScoreTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

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
        }
    }
}
