//
//  InMatchSettingsView.swift
//  badminton score tracker Watch App
//
//  Lightweight settings reachable from a live match's toolbar (#260) — only
//  the settings already read live by GameView/GameViewModel (Crown Scoring,
//  Sound Effects, Score Announcement, Court Theme), so changes take effect
//  on the very next point without touching the in-progress BadmintonMatch.
//  Match Format/Timer/Court Change Reminders stay full-Settings-only — they
//  interact with the live match/timer state and need their own design pass.
//

import SwiftUI
import BadmintonCore

struct InMatchSettingsView: View {
    @AppStorage(AppStorageKeys.enableCrownScoring) private var enableCrownScoring = true
    @AppStorage(AppStorageKeys.enableSounds) private var enableSounds = true
    @AppStorage(AppStorageKeys.announceScore) private var announceScore = true
    @AppStorage(AppStorageKeys.courtTheme) private var courtTheme: CourtTheme = .green
    @State private var showPaywall = false
    @State private var lastFreeTheme: CourtTheme = .green

    var body: some View {
        // Wrapped in its own NavigationStack so the title renders inside the
        // sheet (the root NavigationView doesn't extend into sheets) — same
        // convention as PaywallView. No explicit dismiss control: watchOS
        // adds the sheet's close button automatically.
        NavigationStack {
            List {
                Section(header: Text("settings.crown")) {
                    Toggle("settings.crown_scoring", isOn: $enableCrownScoring)
                }

                Section(header: Text("settings.audio")) {
                    Toggle("settings.sound_effects", isOn: $enableSounds)
                    Toggle("settings.announce_score", isOn: $announceScore)
                }

                CourtThemeSection(courtTheme: $courtTheme, lastFreeTheme: $lastFreeTheme, showPaywall: $showPaywall)
            }
            .navigationTitle("settings.title")
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }
}
