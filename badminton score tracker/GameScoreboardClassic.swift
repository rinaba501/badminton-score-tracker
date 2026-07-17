//
//  GameScoreboardClassic.swift
//  badminton score tracker (iOS)
//
//  "Scoreboard" GameScreenStyle: the manual flip-card scoreboard used
//  courtside — cards hanging off binder rings, a hinge seam across each
//  digit, a small games-won card beside the big score card, and the team's
//  name on a plate under its stack. It's also the app's one landscape-native
//  style: GameView flips AppDelegate's orientation lock to landscape while
//  this is on screen (see GameScreenStyle.isLandscape). Home (the "me" team)
//  sits left, visitor right, per the sports convention.
//
//  Same layout contract as Blackbird: each half is one full-bleed tap target
//  (a `tapLayer` under an `allowsHitTesting(false)` visual layer) that
//  flashes on tap; the center column carries only the clock and undo. Each
//  point swings the score card down off its top hinge like a hand flipping
//  the next card over — skipped under Reduce Motion, where the digit just
//  crossfades. Serve is a lamp on the serving side's name plate: brightness
//  + position, never color alone.
//

import SwiftUI

/// One flip card: digit face, hinge seam across the middle, binder rings on
/// the top edge. Sized by the parent — the same component draws the big
/// score card and the small games card.
private struct FlipCard: View {
    let value: Int
    let digitSize: CGFloat
    let ringSize: CGFloat
    let glow: Color?

    private var face: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(white: 0.07))
            .overlay(
                // Hinge seam: the shadow line where the two half-cards meet.
                VStack(spacing: 0) {
                    Rectangle().fill(Color.black.opacity(0.55)).frame(height: 2)
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(glow ?? Color.white.opacity(0.14), lineWidth: glow == nil ? 1 : 3)
            )
            .shadow(color: glow?.opacity(0.7) ?? .black.opacity(0.5), radius: glow == nil ? 6 : 14, y: 3)
    }

    private var rings: some View {
        HStack(spacing: ringSize * 1.6) {
            ForEach(0..<2, id: \.self) { _ in
                Circle()
                    .stroke(Color(white: 0.55), lineWidth: ringSize * 0.28)
                    .frame(width: ringSize, height: ringSize)
            }
        }
        .offset(y: -ringSize * 0.45)
    }

    var body: some View {
        Text("\(value)")
            .font(.system(size: digitSize, weight: .heavy))
            .monospacedDigit()
            .minimumScaleFactor(0.4)
            .foregroundStyle(.white)
            .contentTransition(.numericText())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(face)
            .overlay(alignment: .top) { rings }
    }
}

/// One team's half: the big score card (flips on every point), the small
/// games card beside it, and the name plate underneath.
private struct ScoreboardPanel: View {
    let data: ScoreSideData
    let games: Int
    let theme: CourtTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var flash = false
    @State private var flipAngle: Double = 0

    private var winnerGlow: Color? {
        data.isWinner ? theme.color.blended(toward: .white, by: 0.4) : nil
    }

    /// Lit while serving, dim otherwise — never absent, so the off state is
    /// learnable by contrast (same rule as Blackbird's marker).
    private var serveLamp: some View {
        Circle()
            .fill(data.isServing ? Color.white : Color.white.opacity(0.18))
            .frame(width: 8, height: 8)
            .shadow(color: data.isServing ? .white.opacity(0.9) : .clear, radius: 4)
    }

    private func youBadge() -> some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.75))
    }

    private func personName(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 15, weight: .heavy))
            .tracking(1)
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var namePlate: some View {
        HStack(spacing: 6) {
            serveLamp
            personName(data.name)
            if data.isMe { youBadge() }
            if let partnerName = data.partnerName {
                personName("/ \(partnerName)")
                if data.partnerIsMe { youBadge() }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(theme.color.blended(toward: .black, by: 0.25)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.15), lineWidth: 1))
    }

    private var scoreCard: some View {
        FlipCard(value: data.score, digitSize: 130, ringSize: 12, glow: winnerGlow)
            .rotation3DEffect(
                .degrees(flipAngle),
                axis: (x: 1, y: 0, z: 0),
                anchor: .top,
                perspective: 0.35
            )
            .onChange(of: data.score) { _, _ in
                guard !reduceMotion else { return }
                var instant = Transaction()
                instant.disablesAnimations = true
                withTransaction(instant) { flipAngle = -80 }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) { flipAngle = 0 }
            }
    }

    /// Small side card for games won — real manual boards keep a separate
    /// mini card stack for sets next to the points cards.
    private var gamesCard: some View {
        VStack(spacing: 4) {
            FlipCard(value: games, digitSize: 34, ringSize: 5, glow: nil)
                .frame(width: 56, height: 62)
            Text("game.games")
                .font(.system(size: 9, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private var accessibilityText: String {
        let team = data.partnerName.map { "\(data.name) / \($0)" } ?? data.name
        let base = String(format: NSLocalizedString("a11y.score_tile", comment: ""), team, data.score)
        guard data.isServing else { return base }
        let court = NSLocalizedString(data.serveRight ? "game.right_court" : "game.left_court", comment: "")
        return String(format: NSLocalizedString("a11y.score_tile_serving_suffix", comment: ""), base, court)
    }

    private var tapLayer: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture {
                flash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { flash = false }
                data.onTap()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint("a11y.score_hint")
            .accessibilityAddTraits(.isButton)
    }

    private var visualLayer: some View {
        VStack(spacing: 12) {
            HStack(alignment: .bottom, spacing: 10) {
                scoreCard
                gamesCard
            }
            namePlate
        }
        .padding(.top, 22)
        .padding(.bottom, 14)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    var body: some View {
        ZStack {
            tapLayer
            visualLayer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            Color.white
                .opacity(flash ? 0.07 : 0)
                .allowsHitTesting(false)
                .animation(.easeOut(duration: 0.25), value: flash)
        }
    }
}

struct ClassicScoreboard: View {
    /// Home side (the near/"me" team) — left, per the sports convention.
    let left: ScoreSideData
    /// Visitor side (the opponent team) — right.
    let right: ScoreSideData
    let header: GameHeaderData
    let theme: CourtTheme

    @ViewBuilder
    private var clock: some View {
        if header.isTimeModeEnabled {
            VStack(spacing: 2) {
                Image(systemName: "timer")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                Text(header.timerLabel)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(header.timerIsUrgent ? .red : .white)
            }
        }
    }

    @ViewBuilder
    private var undoButton: some View {
        if header.canUndo {
            Button(action: header.onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(10)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("a11y.undo")
            .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
    }

    /// The stand the two card stacks share — a theme-colored crossbar, like
    /// the base rail of a tabletop flip scoreboard.
    private var baseRail: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(theme.color.blended(toward: .black, by: 0.35))
            .frame(height: 6)
            .padding(.horizontal, 24)
    }

    private var centerColumn: some View {
        VStack(spacing: 22) {
            clock
            undoButton
        }
        .frame(width: 84)
    }

    var body: some View {
        ZStack {
            Color(white: 0.11).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    ScoreboardPanel(data: left, games: header.myGames, theme: theme)
                    centerColumn
                    ScoreboardPanel(data: right, games: header.opponentGames, theme: theme)
                }
                baseRail
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)
        }
    }
}
