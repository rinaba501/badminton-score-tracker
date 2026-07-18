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

/// One side's tile data, derived once from GameViewModel per render and
/// shared across all 3 GameScreenStyle renderers (Depth/Split/Minimal) so
/// the derivation logic (avatar lookups, serve/winner state) isn't tripled.
struct ScoreSideData {
    let name: String
    let partnerName: String?
    let score: Int
    let isServing: Bool
    let serveRight: Bool
    let isWinner: Bool
    let avatarColor: Color
    let avatarIcon: String?
    let partnerAvatarColor: Color
    let partnerAvatarIcon: String?
    let isMe: Bool
    let partnerIsMe: Bool
    let onTap: () -> Void
}

/// Games-won/timer/undo state, built once by GameView and shared by whichever
/// GameScreenStyle renders it — see ScoreSideData's header comment for why.
struct GameHeaderData {
    let myGames: Int
    let opponentGames: Int
    let canUndo: Bool
    let onUndo: () -> Void
    let isTimeModeEnabled: Bool
    let timerLabel: String
    let timerIsUrgent: Bool
}

struct GameView: View {
    let onExit: () -> Void

    @EnvironmentObject private var appStore: AppStore
    @EnvironmentObject private var storeManager: StoreManager
    @AppStorage(AppStorageKeys.courtTheme) private var courtTheme: CourtTheme = .green
    @AppStorage(AppStorageKeys.gameScreenStyle) private var gameScreenStyle: GameScreenStyle = .depth
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName

    @StateObject private var viewModel = GameViewModel()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Read-site theme gate: a premium theme renders only while entitled
    /// (Pro or theme pack); otherwise fall back to green without writing the
    /// setting back — the entitlement may return (restore, re-purchase).
    private var effectiveTheme: CourtTheme {
        !courtTheme.isPremium || storeManager.entitlements.hasAllThemes ? courtTheme : .green
    }

    // MARK: - Avatar helpers

    private func avatarColor(for name: String) -> Color {
        if let player = appStore.roster.first(where: { $0.name == name }) { return player.avatarColor }
        return Player.isGuestName(name) ? Player.guestAvatarColor(for: name) : .gray
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

    /// Every GameScreenStyle pairs `header.myGames` with whichever tile it
    /// draws in the bottom/left baseline slot, and `header.opponentGames`
    /// with the top/right slot (confirmed across all 8 style files) — so
    /// feeding these two the count for `bottomSide`/`topSide` (rather than
    /// always `.me`/`.opponent`) keeps the tally in sync with the tiles
    /// after a court change swaps which identity renders in which slot.
    private func gamesWon(by side: Side) -> Int {
        side == .me ? viewModel.match.myGamesWon : viewModel.match.opponentGamesWon
    }

    /// Shared games/timer/undo state, built once and consumed by whichever
    /// GameScreenStyle is active — Depth renders it via timerBadge/
    /// gamesHeader below, Split/Minimal build their own layout from the same
    /// data so none of the three re-derive it from viewModel separately.
    private var headerData: GameHeaderData {
        GameHeaderData(
            myGames: gamesWon(by: bottomSide),
            opponentGames: gamesWon(by: topSide),
            canUndo: !viewModel.undoStack.isEmpty &&
                viewModel.match.gameWinner == nil &&
                viewModel.match.matchWinner == nil &&
                viewModel.timeModeWinner == nil,
            onUndo: viewModel.undo,
            isTimeModeEnabled: viewModel.isTimeModeEnabled,
            timerLabel: timerLabel,
            timerIsUrgent: viewModel.timeRemaining <= 30 && viewModel.timeRemaining > 0
        )
    }

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
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        }
    }

    private var gamesHeader: some View {
        GamesWonHeader(
            myGames: gamesWon(by: bottomSide),
            opponentGames: gamesWon(by: topSide),
            canUndo: !viewModel.undoStack.isEmpty &&
                viewModel.match.gameWinner == nil &&
                viewModel.match.matchWinner == nil &&
                viewModel.timeModeWinner == nil,
            onUndo: viewModel.undo
        )
    }

    private func sideData(for side: Side) -> ScoreSideData {
        let name = side == .me ? viewModel.effectiveMyName : viewModel.effectiveOpponentName
        return ScoreSideData(
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
            isMe: name == myName,
            partnerIsMe: viewModel.partnerName(for: side) == myName,
            onTap: { viewModel.tap(side) }
        )
    }

    private func tile(for side: Side) -> some View {
        ScoreView(data: sideData(for: side), theme: effectiveTheme)
    }

    /// Which side renders first (top / left) vs second (bottom / right) —
    /// swapped by `viewModel.courtSidesSwapped` at real badminton end-change
    /// moments (see GameViewModel.triggerCourtChange). A display-only
    /// ordering; never affects Side.me/.opponent scoring identity.
    private var topSide: Side { viewModel.courtSidesSwapped ? .me : .opponent }
    private var bottomSide: Side { viewModel.courtSidesSwapped ? .opponent : .me }

    private var scoreboard: some View {
        VStack(spacing: 10) {
            timerBadge
            gamesHeader
            tile(for: topSide)
            tile(for: bottomSide)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// Layered court-light gradient (radial highlight top, radial shadow
    /// bottom, vertical wash) derived from the active theme color so all 5
    /// themes get the same treatment instead of one hardcoded green gradient.
    private var depthBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    effectiveTheme.color.blended(toward: .white, by: 0.2),
                    effectiveTheme.color,
                    effectiveTheme.color.blended(toward: .black, by: 0.3)
                ],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(colors: [.white.opacity(0.22), .clear], center: .top, startRadius: 0, endRadius: 420)
            RadialGradient(colors: [.black.opacity(0.4), .clear], center: .bottom, startRadius: 0, endRadius: 480)
        }
        .ignoresSafeArea()
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
                             isMatchOver: true, completedGames: viewModel.match.completedGames,
                             doneTitle: NSLocalizedString("game.done", comment: ""), onDone: onExit)
        } else if let winner = viewModel.match.matchWinner ?? viewModel.timeModeWinner {
            MatchOverOverlay(title: winsMatchText(winner), games: gamesScoreText,
                             actionTitle: NSLocalizedString("game.rematch", comment: ""), action: viewModel.newMatch,
                             isMatchOver: true, completedGames: viewModel.match.completedGames,
                             doneTitle: NSLocalizedString("game.done", comment: ""), onDone: onExit)
        } else if let gameWinner = viewModel.match.gameWinner {
            MatchOverOverlay(title: winsGameText(gameWinner), games: gamesScoreText,
                             actionTitle: NSLocalizedString("game.next_game", comment: ""), action: viewModel.startNextGame)
        }
    }

    @ViewBuilder
    private var styledContent: some View {
        switch gameScreenStyle {
        case .depth:
            depthBackground
            scoreboard
        case .split:
            SplitScoreboard(
                top: sideData(for: topSide), bottom: sideData(for: bottomSide),
                header: headerData, theme: effectiveTheme
            )
        case .minimal:
            MinimalScoreboard(
                top: sideData(for: topSide), bottom: sideData(for: bottomSide),
                header: headerData, theme: effectiveTheme
            )
        case .blackbird:
            BlackbirdScoreboard(
                top: sideData(for: topSide), bottom: sideData(for: bottomSide),
                header: headerData, theme: effectiveTheme
            )
        case .matchstick:
            MatchstickScoreboard(
                top: sideData(for: topSide), bottom: sideData(for: bottomSide),
                header: headerData, theme: effectiveTheme
            )
        case .birdsEye:
            BirdsEyeScoreboard(
                top: sideData(for: topSide), bottom: sideData(for: bottomSide),
                header: headerData, theme: effectiveTheme
            )
        case .tug:
            TugScoreboard(
                top: sideData(for: topSide), bottom: sideData(for: bottomSide),
                header: headerData, theme: effectiveTheme
            )
        case .scoreboard:
            ClassicScoreboard(
                left: sideData(for: bottomSide), right: sideData(for: topSide),
                header: headerData, theme: effectiveTheme
            )
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                styledContent
                pointBanners
                resultOverlay
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // "End" while play is live (tapping asks to discard),
                    // "Done" once there's nothing left to lose — the old
                    // static "Menu" label promised navigation but delivered
                    // a destructive alert (#235).
                    Button(NSLocalizedString(matchInProgress ? "game.end" : "game.done", comment: "")) {
                        if matchInProgress { viewModel.showDiscardAlert = true } else { onExit() }
                    }
                    // Minimal's near-white background makes a plain white
                    // tint invisible — everything else keeps the original.
                    .tint(gameScreenStyle == .minimal ? Color.black.opacity(0.7) : Color.white)
                }
            }
            .alert(NSLocalizedString("game.discard_title", comment: ""), isPresented: $viewModel.showDiscardAlert) {
                Button(NSLocalizedString("game.discard_confirm", comment: ""), role: .destructive) { onExit() }
                Button(NSLocalizedString("game.discard_cancel", comment: ""), role: .cancel) {}
            } message: {
                Text("game.discard_message")
            }
            .alert(NSLocalizedString("game.court_change_title", comment: ""), isPresented: $viewModel.showCourtChangeAlert) {
                Button(NSLocalizedString("game.court_change_ok", comment: "")) {}
            } message: {
                Text("game.court_change_message")
            }
            .onReceive(ticker) { _ in viewModel.tickTimer() }
            .onAppear {
                viewModel.onAppear()
                // Scoreboard is the one landscape style; every other screen
                // stays portrait (see AppDelegate.orientationLock).
                if gameScreenStyle.isLandscape {
                    AppDelegate.setOrientation(.landscape)
                }
            }
            // Unconditional: cheap when already portrait, and guarantees the
            // rest of the app never inherits a stuck landscape lock.
            .onDisappear { AppDelegate.setOrientation(.portrait) }
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

/// Depth-style tile: gradient/glass surface with theme-tinted accents,
/// replacing the flat black-opacity fill + hardcoded yellow the original
/// design used.
struct ScoreView: View {
    let data: ScoreSideData
    let theme: CourtTheme

    @State private var scorePulse = false
    @State private var winnerGlow = false

    private var name: String { data.name }
    private var partnerName: String? { data.partnerName }
    private var score: Int { data.score }
    private var isServing: Bool { data.isServing }
    private var serveRight: Bool { data.serveRight }
    private var isWinner: Bool { data.isWinner }
    private var isMe: Bool { data.isMe }
    private var partnerIsMe: Bool { data.partnerIsMe }

    /// A light, low-saturation tint of the active theme color, used for the
    /// "won last game" glow instead of hardcoded yellow — mirrors mockup A's
    /// "every accent derived from the theme hue" intent. NOT used for the
    /// serve signal: on a theme-tinted glass tile the tint is nearly
    /// indistinguishable from the idle white border, so serving is signaled
    /// in solid white instead (#219).
    private var themeTint: Color {
        theme.color.blended(toward: .white, by: 0.55)
    }

    /// Dark tone of the theme hue — legible on the white serve-court chip
    /// for every CourtTheme (black theme blends to plain black).
    private var courtChipTextColor: Color {
        theme.color.blended(toward: .black, by: 0.5)
    }

    /// Same "me" marker ClubDetailView uses — a tile's name isn't always
    /// literally the current user (near/far side can be reassigned to any
    /// roster player in PreMatchView), so this only lights up when it
    /// actually matches the local myName identity.
    private var youBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
            .accessibilityLabel("clubs.you")
    }

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

    private var tileGradient: LinearGradient {
        LinearGradient(
            colors: isWinner
                ? [themeTint.opacity(winnerGlow ? 0.4 : 0.2), themeTint.opacity(winnerGlow ? 0.18 : 0.08)]
                : [.white.opacity(0.16), .white.opacity(0.05), .black.opacity(0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
    }

    private var borderColor: Color {
        isWinner ? themeTint : (isServing ? Color.white : Color.white.opacity(0.35))
    }

    private var borderWidth: CGFloat {
        isWinner ? 3 : (isServing ? 3 : 1.5)
    }

    private func nameRow(_ label: String, showDot: Bool, isMeLabel: Bool = false) -> some View {
        HStack(spacing: 6) {
            if showDot {
                Image(systemName: "circle.fill").font(.system(size: 10)).foregroundStyle(.white)
            }
            Text(label)
                .font(.title3.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if isMeLabel {
                youBadge
            }
        }
    }

    private func avatarNameRow(_ label: String, color: Color, icon: String?, isMeLabel: Bool) -> some View {
        HStack(spacing: 6) {
            AvatarView(name: label, color: color, size: 26, iconName: icon)
            nameRow(label, showDot: false, isMeLabel: isMeLabel)
        }
    }

    @ViewBuilder
    private var leadingContent: some View {
        if let partnerName {
            VStack(alignment: .leading, spacing: 4) {
                avatarNameRow(name, color: isWinner ? themeTint : data.avatarColor, icon: data.avatarIcon, isMeLabel: isMe)
                avatarNameRow(partnerName, color: isWinner ? themeTint : data.partnerAvatarColor, icon: data.partnerAvatarIcon, isMeLabel: partnerIsMe)
            }
        } else {
            HStack(spacing: 8) {
                AvatarView(name: name, color: isWinner ? themeTint : data.avatarColor, size: 34, iconName: data.avatarIcon)
                nameRow(name, showDot: isServing, isMeLabel: isMe)
            }
        }
    }

    private var tileContent: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                leadingContent
                if isServing {
                    Text(serveRight ? "game.right_court" : "game.left_court")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(courtChipTextColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.92)))
                }
            }
            Spacer()
            Text("\(score)")
                .font(.system(size: 76, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .scaleEffect(scorePulse ? 1.25 : 1.0)
                .animation(.spring(response: 0.2, dampingFraction: 0.4), value: scorePulse)
        }
    }

    var body: some View {
        tileContent
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThinMaterial)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(tileGradient)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: winnerGlow)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20).stroke(borderColor, lineWidth: borderWidth)
            )
            .shadow(color: isServing ? .white.opacity(0.45) : .black.opacity(0.25),
                    radius: 16, y: isServing ? 0 : 8)
            .scaleEffect(isWinner ? 1.03 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isWinner)
            .contentShape(Rectangle())
            .onTapGesture {
                scorePulse = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { scorePulse = false }
                data.onTap()
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
    // Explicit exit for the match-over state; when set it becomes the
    // primary button and demotes `action` (Rematch) to secondary (#235).
    var doneTitle: String?
    var onDone: (() -> Void)?

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
            if let doneTitle, let onDone {
                Button(doneTitle, action: onDone)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
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
