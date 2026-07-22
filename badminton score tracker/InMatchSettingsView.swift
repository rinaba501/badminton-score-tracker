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
//  #279 adds a Correct Score section, the one place here that DOES touch the
//  in-progress match — see CorrectScoreSection below.
//

import SwiftUI
import BadmintonCore

struct InMatchSettingsView: View {
    @ObservedObject var viewModel: GameViewModel
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

                CorrectScoreSection(viewModel: viewModel)
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

/// #279: two Steppers that jump the live match's current-game score directly,
/// for a correction bigger or further back than `undo()`'s one-step-at-a-time
/// reach. Each Stepper tap is its own `GameViewModel.correctScore` call (so
/// each is independently undo-able, same granularity as a real point tap);
/// an out-of-range or game/match-ending value is silently rejected by
/// `BadmintonMatch.canSetScore`, so the Stepper just doesn't visually move.
/// Hidden once the game/match is already decided — Next Game/Match Over is
/// the path from there, not a score correction.
private struct CorrectScoreSection: View {
    @ObservedObject var viewModel: GameViewModel

    private var myScoreBinding: Binding<Int> {
        Binding(
            get: { viewModel.match.myScore },
            set: { viewModel.correctScore(myScore: $0, opponentScore: viewModel.match.opponentScore) }
        )
    }

    private var opponentScoreBinding: Binding<Int> {
        Binding(
            get: { viewModel.match.opponentScore },
            set: { viewModel.correctScore(myScore: viewModel.match.myScore, opponentScore: $0) }
        )
    }

    var body: some View {
        if viewModel.match.gameWinner == nil, viewModel.match.matchWinner == nil {
            Section(header: Text("inmatch.correct_score"), footer: Text("inmatch.correct_score_footer")) {
                Stepper(value: myScoreBinding, in: 0...viewModel.match.pointCap) {
                    scoreRow(name: viewModel.teamDisplayName(for: .me), score: viewModel.match.myScore)
                }
                Stepper(value: opponentScoreBinding, in: 0...viewModel.match.pointCap) {
                    scoreRow(name: viewModel.teamDisplayName(for: .opponent), score: viewModel.match.opponentScore)
                }
            }
        }
    }

    private func scoreRow(name: String, score: Int) -> some View {
        HStack {
            Text(name)
                .lineLimit(1)
            Spacer()
            Text("\(score)")
                .foregroundStyle(.secondary)
        }
    }
}
