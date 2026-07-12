//
//  GameScoreboardTug.swift
//  badminton score tracker (iOS)
//
//  "Tug" GameScreenStyle: the only motion-first style in the lineup — the
//  boundary between the two zones isn't fixed, it drags toward whoever's
//  ahead on points, so relative standing reads before the digits do. Score
//  changes spring-bounce in. Respects Reduce Motion: the divider pins to the
//  midpoint and the bounce is dropped in favor of a gentle fade.
//

import SwiftUI

struct TugScoreboard: View {
    let top: ScoreSideData
    let bottom: ScoreSideData
    let header: GameHeaderData
    let theme: CourtTheme

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fraction of vertical space the top zone occupies, dragged toward the
    /// leader and clamped so neither zone collapses.
    private var topFraction: CGFloat {
        guard !reduceMotion else { return 0.5 }
        let diff = CGFloat(top.score - bottom.score)
        let pull = max(-0.16, min(0.16, diff * 0.012))
        return 0.5 - pull
    }

    private func numeral(_ data: ScoreSideData, isLeader: Bool) -> some View {
        Text("\(data.score)")
            .font(.system(size: isLeader ? 118 : 92, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .monospacedDigit()
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.35, dampingFraction: 0.55), value: data.score)
            .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
    }

    private func serveUnderline(_ data: ScoreSideData) -> some View {
        Capsule()
            .fill(theme.color.blended(toward: .white, by: 0.3))
            .frame(width: data.isServing ? 34 : 0, height: 4)
            .opacity(data.isServing ? 1 : 0)
    }

    private func nameRow(_ data: ScoreSideData) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(data.name)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if data.isMe {
                    Image(systemName: "checkmark.seal.fill").font(.caption2)
                        .accessibilityLabel("clubs.you")
                }
                if let partnerName = data.partnerName {
                    Text("/ \(partnerName)")
                        .font(.system(size: 13, weight: .semibold))
                        .opacity(0.7)
                        .lineLimit(1)
                }
            }
            serveUnderline(data)
        }
        .foregroundStyle(.white)
    }

    private func zone(_ data: ScoreSideData, isTop: Bool, isLeader: Bool) -> some View {
        VStack(spacing: 10) {
            if !isTop { Spacer(minLength: 4) }
            nameRow(data)
            numeral(data, isLeader: isLeader)
            if isTop { Spacer(minLength: 4) }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: isLeader
                    ? [theme.color, theme.color.blended(toward: .black, by: 0.25)]
                    : [theme.color.blended(toward: .black, by: 0.45), theme.color.blended(toward: .black, by: 0.6)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .contentShape(Rectangle())
        .onTapGesture { data.onTap() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(data.name), \(data.score)"))
        .accessibilityAddTraits(.isButton)
    }

    private var centerBadge: some View {
        HStack(spacing: 10) {
            Text("\(header.opponentGames)–\(header.myGames)")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
            if header.isTimeModeEnabled {
                Text(header.timerLabel).font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(header.timerIsUrgent ? .red : .white)
            }
            if header.canUndo {
                Button(action: header.onUndo) {
                    Image(systemName: "arrow.uturn.backward").font(.caption.weight(.bold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("a11y.undo")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.5), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
    }

    var body: some View {
        // geo.size is already safe-area-constrained (no ignoresSafeArea on
        // this GeometryReader), so the zone heights derived from it line up
        // exactly with the space SwiftUI actually lays the VStack out in —
        // calling ignoresSafeArea() on content sized from a *smaller*
        // reading left a gap/misalignment at the screen edges and let the
        // top zone's name row sit under the toolbar.
        GeometryReader { geo in
            VStack(spacing: 0) {
                zone(top, isTop: true, isLeader: top.score >= bottom.score)
                    .frame(height: geo.size.height * topFraction)
                zone(bottom, isTop: false, isLeader: bottom.score > top.score)
                    .frame(height: geo.size.height * (1 - topFraction))
            }
            .animation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.75), value: topFraction)
            .overlay(centerBadge)
        }
    }
}
