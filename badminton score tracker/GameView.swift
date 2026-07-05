//
//  GameView.swift
//  badminton score tracker (iOS)
//
//  The live scoring screen for iPhone: two big tap tiles, serve tracking, and
//  the game/match-over overlays. All business logic lives in GameViewModel;
//  this file is layout + input only. iOS restyle of the Watch's GameView, with
//  the watchOS-only bits removed: no Digital Crown scoring (tap only) and no
//  HealthKit workout logging. Presented modally by NewMatchFlow; `onExit`
//  dismisses the flow.
//

import SwiftUI
import BadmintonCore

struct GameView: View {
    let onExit: () -> Void

    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppStorageKeys.courtTheme) private var courtTheme: CourtTheme = .green

    @StateObject private var viewModel = GameViewModel()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Avatar helpers

    private func avatarColor(for name: String) -> Color {
        appStore.roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        appStore.roster.first(where: { $0.name == name })?.iconName
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

    private var serveKnown: Bool {
        viewModel.match.myScore > 0 || viewModel.match.opponentScore > 0
    }

    private var matchInProgress: Bool {
        viewModel.match.matchWinner == nil && viewModel.timeModeWinner == nil &&
            (viewModel.match.myScore > 0 || viewModel.match.opponentScore > 0 ||
             !viewModel.match.completedGames.isEmpty)
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var timerBadge: some View {
        if viewModel.isTimeModeEnabled {
            HStack {
                Image(systemName: "timer").font(.footnote).accessibilityHidden(true)
                Text(timerLabel)
                    .font(.system(size: 17, weight: .bold, design: .monospaced))
                    .foregroundStyle(viewModel.timeRemaining <= 30 && viewModel.timeRemaining > 0 ? Color.red : Color.white)
                    .accessibilityLabel(Text(timerAccessibilityLabel))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.4))
            .clipShape(Capsule())
        }
    }

    private var gamesHeader: some View {
        GamesWonHeader(
            myGames: viewModel.match.myGamesWon,
            opponentGames: viewModel.match.opponentGamesWon,
            canUndo: !viewModel.undoStack.isEmpty &&
                viewModel.match.gameWinner == nil &&
                viewModel.match.matchWinner == nil &&
                viewModel.timeModeWinner == nil,
            onUndo: viewModel.undo
        )
    }

    private func tile(for side: Side) -> some View {
        let name = side == .me ? viewModel.effectiveMyName : viewModel.effectiveOpponentName
        return ScoreView(
            name: Player.displayName(for: name),
            partnerName: viewModel.partnerName(for: side).map(Player.displayName(for:)),
            score: side == .me ? viewModel.match.myScore : viewModel.match.opponentScore,
            isServing: serveKnown && viewModel.match.servingSide == side,
            serveRight: viewModel.match.serveFromRightCourt,
            isWinner: viewModel.match.gameWinner == side,
            avatarColor: avatarColor(for: name),
            avatarIcon: avatarIcon(for: name),
            partnerAvatarColor: viewModel.partnerName(for: side).map(avatarColor(for:)) ?? .gray,
            partnerAvatarIcon: viewModel.partnerName(for: side).flatMap(avatarIcon(for:)),
            onTap: { viewModel.tap(side) }
        )
    }

    private var scoreboard: some View {
        VStack(spacing: 10) {
            timerBadge
            gamesHeader
            tile(for: .opponent)
            tile(for: .me)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var pointBanners: some View {
        if viewModel.match.matchWinner == nil && viewModel.timeModeWinner == nil && viewModel.match.isGamePoint {
            bannerOverlay(gamePointBannerText).allowsHitTesting(false)
        }
        if viewModel.suddenDeath && viewModel.timeModeWinner == nil {
            bannerOverlay(NSLocalizedString("game.sudden_death", comment: "")).allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var resultOverlay: some View {
        if viewModel.match.isTied {
            MatchOverOverlay(title: NSLocalizedString("game.tie", comment: ""), games: gamesScoreText,
                             actionTitle: NSLocalizedString("game.rematch", comment: ""), action: viewModel.newMatch,
                             isMatchOver: true, completedGames: viewModel.match.completedGames)
        } else if let winner = viewModel.match.matchWinner ?? viewModel.timeModeWinner {
            MatchOverOverlay(title: winsMatchText(winner), games: gamesScoreText,
                             actionTitle: NSLocalizedString("game.rematch", comment: ""), action: viewModel.newMatch,
                             isMatchOver: true, completedGames: viewModel.match.completedGames)
        } else if let gameWinner = viewModel.match.gameWinner {
            MatchOverOverlay(title: winsGameText(gameWinner), games: gamesScoreText,
                             actionTitle: NSLocalizedString("game.next_game", comment: ""), action: viewModel.startNextGame)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                courtTheme.color.ignoresSafeArea()
                scoreboard
                pointBanners
                resultOverlay
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("game.menu") {
                        if matchInProgress { viewModel.showDiscardAlert = true } else { onExit() }
                    }
                    .tint(.white)
                }
            }
            .alert(NSLocalizedString("game.discard_title", comment: ""), isPresented: $viewModel.showDiscardAlert) {
                Button(NSLocalizedString("game.discard_confirm", comment: ""), role: .destructive) { onExit() }
                Button(NSLocalizedString("game.discard_cancel", comment: ""), role: .cancel) {}
            } message: {
                Text("game.discard_message")
            }
            .onReceive(ticker) { _ in viewModel.tickTimer() }
            .onAppear { viewModel.onAppear() }
        }
    }

    private func bannerOverlay(_ text: String) -> some View {
        VStack {
            Text(text)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red.opacity(0.85))
                .clipShape(Capsule())
                .transition(.scale.combined(with: .opacity))
            Spacer()
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: text)
    }
}

// MARK: - Sub-views

struct GamesWonHeader: View {
    let myGames: Int
    let opponentGames: Int
    let canUndo: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("game.games")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
                .accessibilityHidden(true)
            Spacer()
            Text("\(opponentGames) – \(myGames)")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)
                .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.games_won", comment: ""), opponentGames, myGames)))
            if canUndo {
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
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
    let isWinner: Bool
    let avatarColor: Color
    var avatarIcon: String?
    var partnerAvatarColor: Color = .gray
    var partnerAvatarIcon: String?
    let onTap: () -> Void

    @State private var scorePulse = false
    @State private var winnerGlow = false

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
        isWinner ? 3 : (isServing ? 2.5 : 1.5)
    }

    private func nameRow(_ label: String, showDot: Bool) -> some View {
        HStack(spacing: 6) {
            if showDot {
                Image(systemName: "circle.fill").font(.system(size: 10)).foregroundStyle(.yellow)
            }
            Text(label)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private func avatarNameRow(_ label: String, color: Color, icon: String?) -> some View {
        HStack(spacing: 6) {
            AvatarView(name: label, color: color, size: 26, iconName: icon)
            nameRow(label, showDot: false)
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if let partnerName {
            VStack(alignment: .leading, spacing: 4) {
                avatarNameRow(name, color: isWinner ? .yellow : avatarColor, icon: avatarIcon)
                avatarNameRow(partnerName, color: isWinner ? .yellow : partnerAvatarColor, icon: partnerAvatarIcon)
            }
        } else {
            HStack(spacing: 8) {
                AvatarView(name: name, color: isWinner ? .yellow : avatarColor, size: 34, iconName: avatarIcon)
                nameRow(name, showDot: isServing)
            }
        }
    }

    private var tileContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                leadingContent
                if isServing {
                    Text(serveRight ? "game.right_court" : "game.left_court")
                        .font(.caption)
                        .foregroundStyle(.yellow.opacity(0.9))
                }
            }
            Spacer()
            Text("\(score)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .scaleEffect(scorePulse ? 1.25 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.4), value: scorePulse)
        }
    }

    var body: some View {
        tileContent
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(backgroundFill)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: winnerGlow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20).stroke(borderColor, lineWidth: borderWidth)
            )
            .scaleEffect(isWinner ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isWinner)
            .contentShape(Rectangle())
            .onTapGesture {
                scorePulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scorePulse = false }
                onTap()
            }
            .onChange(of: isWinner) { _, won in winnerGlow = won }
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
    var isMatchOver = false
    var completedGames: [GameScore] = []

    @State private var shimmer = false

    var body: some View {
        VStack(spacing: 12) {
            if isMatchOver {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.yellow)
                    .scaleEffect(shimmer ? 1.15 : 1.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: shimmer)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(games)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.85))
            if isMatchOver && !completedGames.isEmpty {
                Text(completedGames.map { "\($0.my)-\($0.opponent)" }.joined(separator: "   "))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding(28)
        .background(Color.black.opacity(0.85))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 24)
        .transition(.asymmetric(
            insertion: .scale(scale: 0.7).combined(with: .opacity),
            removal: .opacity
        ))
        .onAppear { shimmer = true }
    }
}
