//
//  badminton_score_trackerApp.swift
//  badminton score tracker (iOS)
//
//  Entry point for the iPhone companion app (ROADMAP Phase 6, #41).
//  Starts CloudKit sync and injects the shared AppStore so the phone reads
//  the same history/roster/settings the Watch writes (shared CloudKit
//  container `iCloud.ritsuma.badminton-score-tracker`). The Watch remains
//  the richest scoring device; the phone also has its own live-scoring flow.
//

import SwiftUI

@main
struct BadmintonScoreTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Synchronous on the main actor so CKSyncEngine exists before any
        // AppStore save can race a still-nil engine (CloudKit is the only path).
        CloudKitSyncManager.shared.start()
        Task { @MainActor in
            StoreManager.shared.start()
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
