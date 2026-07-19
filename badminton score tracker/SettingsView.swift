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
    @AppStorage(AppStorageKeys.gameScreenStyle) private var gameScreenStyle: GameScreenStyle = .depth
    @AppStorage(AppStorageKeys.announceScore) private var announceScore = true
    @AppStorage(AppStorageKeys.enableSounds) private var enableSounds = true
    @AppStorage(AppStorageKeys.timeModeEnabled) private var timeModeEnabled = false
    @AppStorage(AppStorageKeys.timeLimitMinutes) private var timeLimitMinutes = 10
    @AppStorage(AppStorageKeys.courtChangeRemindersEnabled) private var courtChangeRemindersEnabled = false
    @EnvironmentObject private var storeManager: StoreManager
    @State private var showPaywall = false

    /// Capsule badge showing the current plan next to the Pro row — the row
    /// stays visible after purchase so the badge can flip from Free to Pro.
    private var planBadge: some View {
        let isPro = storeManager.entitlements.isPro
        return Text(LocalizedStringKey(isPro ? "paywall.plan_pro" : "paywall.plan_free"))
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((isPro ? Color.yellow : Color.secondary).opacity(0.2))
            .foregroundStyle(isPro ? .yellow : .secondary)
            .clipShape(Capsule())
    }

    var body: some View {
        List {
            Section {
                Button(action: { showPaywall = true }) {
                    HStack {
                        Label("paywall.title", systemImage: "crown.fill")
                            .foregroundStyle(.yellow)
                        Spacer()
                        planBadge
                    }
                }
                .accessibilityElement(children: .combine)
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

            Section(header: Text("ios.game_screen_style")) {
                NavigationLink {
                    GameScreenStylePickerView(selection: $gameScreenStyle, courtTheme: courtTheme)
                } label: {
                    HStack {
                        Text("ios.game_screen_style")
                        Spacer()
                        GameScreenStyleThumbnail(style: gameScreenStyle, accentColor: courtTheme.color)
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
                Toggle("settings.court_changes", isOn: $courtChangeRemindersEnabled)
            }
            .onChange(of: pointsToWin) { _ in
                CloudKitSyncManager.shared.enqueueSettingsChange()
            }
            .onChange(of: gamesInMatch) { _ in
                CloudKitSyncManager.shared.enqueueSettingsChange()
            }
            .onChange(of: courtChangeRemindersEnabled) { _ in
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

            Section(header: Text("settings.danger_zone")) {
                NavigationLink {
                    EraseDataView()
                } label: {
                    Label("settings.erase_all_data", systemImage: "trash.fill")
                        .foregroundStyle(.red)
                }
            }

        }
        .navigationTitle("settings.title")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }
}
