//
//  ContentView.swift
//  badminton score tracker Watch App
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//
//  Root view and state-driven navigation. Each screen lives in its own
//  file (MenuView, PreMatchView, GameView, SettingsView, HistoryView,
//  StatsView, PlayerEditView); this file only owns the top-level routing.
//

import SwiftUI

struct ContentView: View {
    @State private var currentView: AppView = .menu
    @AppStorage("playerRoster") private var rosterData: Data = Data()
    @AppStorage("matchHistory") private var matchHistoryData: Data = Data()

    enum AppView {
        case menu, preMatch, game, settings, history, stats
    }

    var body: some View {
        NavigationView {
            switch currentView {
            case .menu:
                MenuView(currentView: $currentView)
            case .preMatch:
                PreMatchView(currentView: $currentView)
            case .game:
                GameView(currentView: $currentView)
            case .settings:
                SettingsView(currentView: $currentView)
            case .history:
                HistoryView(currentView: $currentView)
            case .stats:
                StatsView(currentView: $currentView)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .startNewMatch)) { _ in
            currentView = .preMatch
        }
        .onChange(of: rosterData) { CloudSyncManager.shared.pushToCloud() }
        .onChange(of: matchHistoryData) { CloudSyncManager.shared.pushToCloud() }
    }
}

#Preview {
    ContentView()
}
