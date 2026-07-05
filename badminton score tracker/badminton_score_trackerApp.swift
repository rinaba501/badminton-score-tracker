//
//  badminton_score_trackerApp.swift
//  badminton score tracker (iOS)
//
//  Entry point for the iPhone companion app (ROADMAP Phase 6, #41).
//  PR1 shell: no sync, no data — the iOS CloudSyncManager/AppStore layer
//  lands separately (see the phased plan in the PR/ROADMAP). The Watch
//  remains the scoring device.
//

import SwiftUI

@main
struct BadmintonScoreTrackerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
