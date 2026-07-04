//
//  GameView.swift
//  badminton score tracker Watch App
//
//  The live scoring screen: tap/crown scoring, serve tracking, and the
//  game/match over overlays. All business logic lives in GameViewModel;
//  this file is layout and input binding only.
//

import SwiftUI
import BadmintonCore

// MARK: - Onboarding

struct OnboardingView: View {
    private struct Hint: Identifiable {
        let id = UUID()
        let icon: String
        let key: String
    }

    private let hints: [Hint] = [
        Hint(icon: "hand.tap",                      key: "onboarding.hint_tap"),
        Hint(icon: "digitalcrown.horizontal.press", key: "onboarding.hint_crown_cw"),
        Hint(icon: "digitalcrown.horizontal.press", key: "onboarding.hint_crown_ccw"),
        Hint(icon: "arrow.uturn.backward",          key: "onboarding.hint_undo"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(hints) { hint in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: hint.icon)
                            .font(.system(size: 16))
                            .foregroundColor(.yellow)
                            .frame(width: 22)
                        Text(LocalizedStringKey(hint.key))
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding()
        }
        .navigationTitle(LocalizedStringKey("onboarding.title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Game

struct GameView: View {
    @Binding var currentView: ContentView.AppView
    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppStorageKeys.courtTheme) private var courtTheme: CourtTheme = .green
    @AppStorage(AppStorageKeys.enableCrownScoring) private var enableCrownScoring = true

    @StateObject private var viewModel = GameViewModel()
    @State private var crownValue: Double = 0
    @State private var lastCrownScore: Double = 0
    private let crownThreshold: Double = 1.0
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Avatar helpers (presentation — reads published appStore.roster)

    private func avatarColor(for name: String) -> Color {
        appStore.roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        appStore.roster.first(where: { $0.name == name })?.iconName
    }

    // MARK: - Crown input

    private func onCrownChanged(_ newValue: Double) {
        guard enableCrownScoring,
              viewModel.match.gameWinner == nil,
              viewModel.match.matchWinner == nil else { return }
        let delta = newValue - lastCrownScore
        if delta >= crownThreshold {
            lastCrownScore = newValue
            viewModel.tap(.me)
        } else if delta <= -crownThreshold {
            lastCrownScore = newValue
            viewModel.tap(.opponent)
        }
    }

    // MARK: - Display helpers

    private var timerLabel: String {
        let m = Int(viewModel.timeRemaining) / 60
        let s = Int(viewModel.timeRemaining) % 60
        return String(format: "%d:%02d", m, s)
    }

    private var timerAccessibilityLabel: String {
        String(format: NSLocalizedString("a11y.timer_remaining", comment: ""), timerLabel)
    }

    private var gamePointBannerText: String {
        viewModel.match.isMatchPoint
            ? NSLocalizedString("game.match_point", comment: "")
            : NSLocalizedString("game.game_point", comment: "")
    }

    private var gamesScoreText: String {
        let raw = "\(viewModel.match.myGamesWon) - \(viewModel.match.opponentGamesWon)"
        return String(format: NSLocalizedString("game.games_score", comment: ""), raw)
    }

    private func winsMatchText(_ side: Side) -> String {
        String(format: NSLocalizedString("game.wins_match", comment: ""), viewModel.teamDisplayName(for: side))
    }

    private func winsGameText(_ side: Side) -> String {
        String(format: NSLocalizedString("game.wins_game", comment: ""), viewModel.teamDisplayName(for: side))
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var timerBadge: some View {
        if viewModel.isTimeModeEnabled {
            HStack {
                Image(systemName: "timer")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(timerLabel)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(viewModel.timeRemaining <= 30 && viewModel.timeRemaining > 0 ? .red : .white)
                    .accessibilityLabel(Text(timerAccessibilityLabel))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.4))
            .cornerRadius(8)
        }
    }

    private var serveKnown: Bool {
        viewModel.match.myScore > 0 || viewModel.match.opponentScore > 0
    }

    private var gamesHeader: some View {
        GamesWonHeader(
            myName: viewModel.effectiveMyName,
            opponentName: viewModel.effectiveOpponentName,
            myGames: viewModel.match.myGamesWon,
            opponentGames: viewModel.match.opponentGamesWon,
            canUndo: !viewModel.undoStack.isEmpty &&
                viewModel.match.gameWinner == nil &&
                viewModel.match.matchWinner == nil &&
                viewModel.timeModeWinner == nil,
            onUndo: viewModel.undo
        )
    }

    private var opponentTile: some View {
        ScoreView(
            name: Player.displayName(for: viewModel.effectiveOpponentName),
            partnerName: viewModel.partnerName(for: .opponent).map(Player.displayName(for:)),
            score: viewModel.match.opponentScore,
            isServing: serveKnown && viewModel.match.servingSide == .opponent,
            serveRight: viewModel.match.serveFromRightCourt,
            activePartnerIsSecondary: viewModel.match.currentPartnerIndex(for: .opponent) == 1,
            isWinner: viewModel.match.gameWinner == .opponent,
            avatarColor: avatarColor(for: viewModel.effectiveOpponentName),
            avatarIcon: avatarIcon(for: viewModel.effectiveOpponentName),
            onTap: { viewModel.tap(.opponent) }
        )
    }

    private var myTile: some View {
        ScoreView(
            name: Player.displayName(for: viewModel.effectiveMyName),
            partnerName: viewModel.partnerName(for: .me).map(Player.displayName(for:)),
            score: viewModel.match.myScore,
            isServing: serveKnown && viewModel.match.servingSide == .me,
            serveRight: viewModel.match.serveFromRightCourt,
            activePartnerIsSecondary: viewModel.match.currentPartnerIndex(for: .me) == 1,
            isWinner: viewModel.match.gameWinner == .me,
            avatarColor: avatarColor(for: viewModel.effectiveMyName),
            avatarIcon: avatarIcon(for: viewModel.effectiveMyName),
            onTap: { viewModel.tap(.me) }
        )
    }

    private var scoreboard: some View {
        VStack(spacing: 6) {
            timerBadge
            gamesHeader
            opponentTile
            myTile
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder
    private var pointBanners: some View {
        if viewModel.match.matchWinner == nil && viewModel.timeModeWinner == nil && viewModel.match.isGamePoint {
            bannerOverlay(gamePointBannerText)
                .allowsHitTesting(false)
        }

        if viewModel.suddenDeath && viewModel.timeModeWinner == nil {
            bannerOverlay(NSLocalizedString("game.sudden_death", comment: ""))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var resultOverlay: some View {
        if viewModel.match.isTied {
            MatchOverOverlay(
                title: NSLocalizedString("game.tie", comment: ""),
                games: gamesScoreText,
                actionTitle: NSLocalizedString("game.rematch", comment: ""),
                action: viewModel.newMatch,
                isMatchOver: true,
                completedGames: viewModel.match.completedGames
            )
        } else if let winner = viewModel.match.matchWinner ?? viewModel.timeModeWinner {
            MatchOverOverlay(
                title: winsMatchText(winner),
                games: gamesScoreText,
                actionTitle: NSLocalizedString("game.rematch", comment: ""),
                action: viewModel.newMatch,
                isMatchOver: true,
                completedGames: viewModel.match.completedGames
            )
        } else if let gameWinner = viewModel.match.gameWinner {
            MatchOverOverlay(
                title: winsGameText(gameWinner),
                games: gamesScoreText,
                actionTitle: NSLocalizedString("game.next_game", comment: ""),
                action: viewModel.startNextGame
            )
        }
    }

    var body: some View {
        ZStack {
            courtTheme.color
                .ignoresSafeArea()

            scoreboard
            pointBanners
            resultOverlay
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("game.menu") {
                    let matchInProgress = viewModel.match.matchWinner == nil &&
                        viewModel.timeModeWinner == nil &&
                        (viewModel.match.myScore > 0 || viewModel.match.opponentScore > 0 ||
                         !viewModel.match.completedGames.isEmpty)
                    if matchInProgress {
                        viewModel.showDiscardAlert = true
                    } else {
                        currentView = .menu
                    }
                }
            }
        }
        .alert(NSLocalizedString("game.discard_title", comment: ""), isPresented: $viewModel.showDiscardAlert) {
            Button(NSLocalizedString("game.discard_confirm", comment: ""), role: .destructive) {
                Task { await viewModel.discard() }
                currentView = .menu
            }
            Button(NSLocalizedString("game.discard_cancel", comment: ""), role: .cancel) {}
        } message: {
            Text("game.discard_message")
        }
        .focusable()
        .digitalCrownRotation($crownValue, from: -1000, through: 1000, sensitivity: .low, isContinuous: true)
        .onChange(of: crownValue, perform: onCrownChanged)
        .onReceive(ticker) { _ in viewModel.tickTimer() }
        .onAppear {
            viewModel.onAppear()
            crownValue = 0
            lastCrownScore = 0
        }
    }

    private func bannerOverlay(_ text: String) -> some View {
        VStack {
            Text(text)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Color.red.opacity(0.85))
                .cornerRadius(8)
                .transition(.scale.combined(with: .opacity))
            Spacer()
        }
        .padding(.top, 2)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: text)
    }
}

// MARK: - Sub-structs (unchanged)

struct GamesWonHeader: View {
    let myName: String
    let opponentName: String
    let myGames: Int
    let opponentGames: Int
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text("game.games")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
                .accessibilityHidden(true)
            Spacer()
            Text("\(opponentGames) – \(myGames)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.games_won", comment: ""), opponentGames, myGames)))
            if canUndo {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("a11y.undo")
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }
        }
        .padding(.horizontal, 6)
    }
}

struct ScoreView: View {
    let name: String
    var partnerName: String?
    let score: Int
    let isServing: Bool
    let serveRight: Bool
    var activePartnerIsSecondary: Bool = false
    let isWinner: Bool
    let avatarColor: Color
    var avatarIcon: String? = nil
    let onTap: () -> Void

    @State private var scorePulse = false
    @State private var winnerGlow = false

    private var isDoubles: Bool { partnerName != nil }

    /// Combined team name for accessibility/announcements — "Alice" for
    /// singles, "Alice & Bob" (localized) for doubles.
    private var teamName: String {
        guard let partnerName else { return name }
        return String(format: NSLocalizedString("game.team_names_format", comment: ""), name, partnerName)
    }

    private var accessibilityDescription: String {
        let base = String(format: NSLocalizedString("a11y.score_tile", comment: ""), teamName, score)
        guard isServing else { return base }
        let court = NSLocalizedString(serveRight ? "game.right_court" : "game.left_court", comment: "")
        return String(format: NSLocalizedString("a11y.score_tile_serving_suffix", comment: ""), base, court)
    }

    private var backgroundFill: Color {
        isWinner ? Color.yellow.opacity(winnerGlow ? 0.35 : 0.15) : Color.black.opacity(0.25)
    }

    private var borderColor: Color {
        isWinner ? Color.yellow : (isServing ? Color.yellow.opacity(0.8) : Color.white.opacity(0.5))
    }

    private var borderWidth: CGFloat {
        isWinner ? 2.5 : (isServing ? 2 : 1.5)
    }

    @ViewBuilder
    private func nameRow(_ label: String, isActive: Bool) -> some View {
        HStack(spacing: 4) {
            if isActive && isServing {
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundColor(.yellow)
            }
            Text(label)
                .font(.caption2)
                .fontWeight(isActive ? .medium : .regular)
                .foregroundColor(isActive ? .white : .white.opacity(0.6))
                .lineLimit(1)
        }
    }

    private var tileContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    AvatarView(name: name, color: isWinner ? .yellow : avatarColor, size: 20, iconName: avatarIcon)
                    VStack(alignment: .leading, spacing: 1) {
                        nameRow(name, isActive: !isDoubles || !activePartnerIsSecondary)
                        if let partnerName {
                            nameRow(partnerName, isActive: activePartnerIsSecondary)
                        }
                    }
                }
                if isServing {
                    Text(serveRight ? "game.right_court" : "game.left_court")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow.opacity(0.9))
                }
            }
            Spacer()
            Text("\(score)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .scaleEffect(scorePulse ? 1.35 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.4), value: scorePulse)
        }
    }

    var body: some View {
        tileContent
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(backgroundFill)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: winnerGlow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .scaleEffect(isWinner ? 1.06 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isWinner)
            .contentShape(Rectangle())
            .onTapGesture {
                scorePulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scorePulse = false }
                onTap()
            }
            .onChange(of: isWinner) { won in
                winnerGlow = won
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint("a11y.score_hint")
            .accessibilityAddTraits(.isButton)
    }
}

struct MatchOverOverlay: View {
    let title: String
    let games: String
    let actionTitle: String
    let action: () -> Void
    var isMatchOver: Bool = false
    var completedGames: [GameScore] = []

    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 8) {
            if isMatchOver {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.yellow)
                    .scaleEffect(shimmer ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: shimmer)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text(games)
                .font(.caption)
                .foregroundColor(.white.opacity(0.85))
            if isMatchOver && !completedGames.isEmpty {
                Text(completedGames.map { "\($0.my)-\($0.opponent)" }.joined(separator: "  "))
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.black.opacity(0.85))
        .cornerRadius(14)
        .padding(.horizontal, 8)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.7).combined(with: .opacity),
            removal: .opacity
        ))
        .onAppear { shimmer = true }
    }
}
