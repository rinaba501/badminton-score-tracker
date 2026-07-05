//
//  badminton_score_trackerApp.swift
//  badminton score tracker (iOS)
//
//  Entry point for the iPhone companion app (ROADMAP Phase 6, #41).
//  Starts iCloud KV sync and injects the shared AppStore, so the phone reads
//  the same history/roster/settings the Watch writes (shared KV bucket via a
//  byte-identical ubiquity-kvstore-identifier). The Watch remains the scoring
//  device; the phone's history/stats/roster UI arrives in the follow-up PRs.
//

import SwiftUI

@main
struct BadmintonScoreTrackerApp: App {
    init() {
        Task { await CloudSyncManager.shared.start() }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppStore.shared)
        }
    }
}
