//
//  badminton_score_trackerApp.swift
//  badminton score tracker (iOS)
//
//  Entry point for the iPhone companion app (ROADMAP Phase 6, #41).
//  Starts iCloud KV sync and injects the shared AppStore, so the phone reads
//  the same history/roster/settings the Watch writes (shared KV bucket via a
//  byte-identical ubiquity-kvstore-identifier). The Watch remains the scoring
//  device; the phone also has its own live-scoring flow (PR6).
//

import SwiftUI

@main
struct BadmintonScoreTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        Task {
            // CloudSyncManager always runs (scalar settings sync via the KV
            // store). When the CloudKit flag is on it also drives history +
            // roster through CloudKitSyncManager; while off (default), the KV
            // store keeps handling those too — behavior is unchanged.
            await CloudSyncManager.shared.start()
            if CloudKitSyncManager.isEnabled {
                await CloudKitSyncManager.shared.start()
            }
        }
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
