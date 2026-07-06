//
//  badminton_score_trackerApp.swift
//  badminton score tracker Watch App
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//

import SwiftUI

@main
struct badminton_score_tracker_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) var appDelegate

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
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(AppStore.shared)
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
