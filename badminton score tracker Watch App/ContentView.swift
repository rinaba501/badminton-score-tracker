//
//  ContentView.swift
//  badminton score tracker Watch App
//
//  Created by Inaba, Ritsuma | Ritsuma | TDD on 2025/05/07.
//
//  Root view and state-driven navigation. Each screen lives in its own
//  file (MenuView, PreMatchView, GameView, SettingsView, HistoryView,
//  StatsView, PlayerEditView); this file only owns the top-level routing.
//  Also owns the first-launch "what should we call you?" prompt (shown once,
//  skippable — see AppStorageKeys.didPromptForName), so a new user's name
//  doesn't sit at the "Me" placeholder by the time Friends/Clubs are ever
//  touched. FriendsView/ClubDetailView carry a lighter backstop nudge for
//  anyone who skips this.
//

import SwiftUI
import BadmintonCore
import CloudSyncSpike

struct ContentView: View {
    @State private var currentView: AppView = .menu
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.didPromptForName) private var didPromptForName = false
    @AppStorage(AppStorageKeys.supabaseAccountLinked) private var supabaseAccountLinked = false
    @State private var showNamePrompt = false
    @State private var pendingName = ""

    enum AppView {
        case menu, preMatch, game, settings, history, stats
    }

    private var needsName: Bool {
        myName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || myName == Player.defaultMyName
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
        .onAppear {
            if !didPromptForName && needsName {
                pendingName = ""
                showNamePrompt = true
            }
        }
        .sheet(isPresented: $showNamePrompt) {
            welcomeNamePrompt
        }
    }

    private var welcomeNamePrompt: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("onboarding.welcome_name_message")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                TextField("friends.display_name_placeholder", text: $pendingName)
                Button("playeredit.save") { saveWelcomeName() }
                    .disabled(pendingName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("onboarding.skip") {
                    didPromptForName = true
                    showNamePrompt = false
                }
            }
            .padding()
            .navigationTitle(Text("onboarding.welcome_name_title"))
        }
    }

    private func saveWelcomeName() {
        let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        myName = trimmed
        didPromptForName = true
        showNamePrompt = false
        AppStore.shared.enqueueSettingsChange()
        Task { @MainActor in
            if supabaseAccountLinked {
                await SupabaseSyncManager.shared.upsertMyProfile(displayName: Player.displayName(for: myName))
                return
            }
            try? await CloudKitSyncManager.shared.ensureMyProfileExists(displayName: Player.displayName(for: myName))
        }
    }
}

#Preview {
    ContentView()
}
