//
//  badminton_score_trackerApp.swift
//  badminton score tracker Watch App
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//

import SwiftUI

@main
struct badminton_score_tracker_Watch_AppApp: App {
    init() {
        Task { await CloudSyncManager.shared.start() }
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
