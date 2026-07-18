//
//  InMatchSettingsView.swift
//  badminton score tracker (iOS)
//
//  Lightweight settings reachable from a live match's toolbar (#260) — only
//  the settings already read live by GameView/GameViewModel (Sound Effects,
//  Score Announcement, Court Theme), so changes take effect on the very next
//  point without touching the in-progress BadmintonMatch. Match Format/
//  Timer/Court Change Reminders stay full-Settings-only — they interact with
//  the live match/timer state and need their own design pass. No Crown
//  Scoring row — Digital Crown is Watch-only hardware, same as SettingsView.
//

import SwiftUI
import BadmintonCore

struct InMatchSettingsView: View {
    @AppStorage(AppStorageKeys.enableSounds) private var enableSounds = true
    @AppStorage(AppStorageKeys.announceScore) private var announceScore = true
    @AppStorage(AppStorageKeys.courtTheme) private var courtTheme: CourtTheme = .green
    @EnvironmentObject private var storeManager: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("settings.audio")) {
                    Toggle("settings.sound_effects", isOn: $enableSounds)
                    Toggle("settings.announce_score", isOn: $announceScore)
                }

                Section(header: Text("settings.court_theme")) {
                    NavigationLink {
                        CourtThemePickerView(
                            selection: $courtTheme,
                            hasAllThemes: storeManager.entitlements.hasAllThemes,
                            onLockedSelection: { showPaywall = true }
                        )
                    } label: {
                        HStack {
                            Text("settings.theme")
                            Spacer()
                            Circle()
                                .fill(courtTheme.color)
                                .frame(width: 16, height: 16)
                            Text(NSLocalizedString("theme.\(courtTheme.rawValue.lowercased())", comment: ""))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("game.done") { dismiss() }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
}
