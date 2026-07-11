//
//  SettingsView.swift
//  badminton score tracker (iOS)
//
//  Match format, audio, court theme, and timer — the iOS mirror of the
//  Watch's SettingsView, minus what's already reachable from ContentView's
//  own menu (Roster/Clubs/Friends) and Crown Scoring (Digital Crown is
//  Watch-only hardware, so there's nothing to toggle here). Sync is
//  always-on CloudKit with no toggle.
//

import SwiftUI
import BadmintonCore

struct SettingsView: View {
    @AppStorage(AppStorageKeys.gameMode) private var gameMode: GameMode = .singles
    @AppStorage(AppStorageKeys.pointsToWin) private var pointsToWin: Int = 21
    @AppStorage(AppStorageKeys.gamesInMatch) private var gamesInMatch: Int = 3
    @AppStorage(AppStorageKeys.courtTheme) private var courtTheme: CourtTheme = .green
    @AppStorage(AppStorageKeys.announceScore) private var announceScore = true
    @AppStorage(AppStorageKeys.enableSounds) private var enableSounds = true
    @AppStorage(AppStorageKeys.timeModeEnabled) private var timeModeEnabled = false
    @AppStorage(AppStorageKeys.timeLimitMinutes) private var timeLimitMinutes = 10
    @EnvironmentObject private var storeManager: StoreManager
    @State private var showPaywall = false
    /// Where the theme picker snaps back to when a premium theme is tapped
    /// without the entitlement (tracks the last free selection; the paywall
    /// opens instead).
    @State private var lastFreeTheme: CourtTheme = .green

    var body: some View {
        List {
            if !storeManager.entitlements.isPro {
                Section {
                    Button(action: { showPaywall = true }) {
                        Label("paywall.title", systemImage: "crown.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }

            Section(header: Text("settings.game_mode")) {
                Picker("settings.mode", selection: $gameMode) {
                    Text("settings.singles").tag(GameMode.singles)
                    Text("settings.doubles").tag(GameMode.doubles)
                }
            }

            Section(header: Text("settings.audio")) {
                Toggle("settings.sound_effects", isOn: $enableSounds)
                Toggle("settings.announce_score", isOn: $announceScore)
            }

            Section(header: Text("settings.court_theme")) {
                Picker("settings.theme", selection: $courtTheme) {
                    ForEach(CourtTheme.allCases, id: \.self) { theme in
                        HStack {
                            Circle()
                                .fill(theme.color)
                                .frame(width: 12, height: 12)
                            Text(LocalizedStringKey("theme.\(theme.rawValue.lowercased())"))
                            if theme.isPremium && !storeManager.entitlements.hasAllThemes {
                                Spacer()
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(Text("paywall.locked"))
                            }
                        }
                        .tag(theme)
                    }
                }
                // Picking a locked theme opens the paywall instead of
                // sticking: snap back to the last free selection.
                .onChange(of: courtTheme) { newTheme in
                    if newTheme.isPremium && !storeManager.entitlements.hasAllThemes {
                        courtTheme = lastFreeTheme
                        showPaywall = true
                    } else if !newTheme.isPremium {
                        lastFreeTheme = newTheme
                    }
                }
            }

            Section(header: Text("settings.match_format")) {
                Picker("settings.points_to_win", selection: $pointsToWin) {
                    Text("settings.pts_11").tag(11)
                    Text("settings.pts_15").tag(15)
                    Text("settings.pts_21").tag(21)
                }
                Picker("settings.games_in_match", selection: $gamesInMatch) {
                    Text("settings.games_1").tag(1)
                    Text("settings.games_3").tag(3)
                    Text("settings.games_5").tag(5)
                }
            }
            .onChange(of: pointsToWin) { _ in
                CloudKitSyncManager.shared.enqueueSettingsChange()
            }
            .onChange(of: gamesInMatch) { _ in
                CloudKitSyncManager.shared.enqueueSettingsChange()
            }

            Section(header: Text("settings.timer")) {
                Toggle("settings.timer_enable", isOn: $timeModeEnabled)
                if timeModeEnabled {
                    VStack(spacing: 6) {
                        Text(String(format: NSLocalizedString("settings.minutes", comment: ""), timeLimitMinutes))
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                        HStack(spacing: 8) {
                            ForEach([(-5, "-5"), (-1, "-1"), (1, "+1"), (5, "+5")], id: \.0) { delta, label in
                                Button(label) { timeLimitMinutes = min(99, max(1, timeLimitMinutes + delta)) }
                                    .font(.callout)
                                    .foregroundStyle(delta < 0 ? .red : .green)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .onAppear {
            if !courtTheme.isPremium { lastFreeTheme = courtTheme }
        }
    }
}
