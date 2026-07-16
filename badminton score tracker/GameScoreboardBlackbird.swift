//
//  GameScoreboardBlackbird.swift
//  badminton score tracker (iOS)
//
//  "Blackbird" GameScreenStyle: a broadcast-style scorebar on a pure black
//  field, modeled on TV badminton coverage graphics. Serve is a shape
//  (triangle), not a color, so the style stays legible for color-blind users;
//  Court Theme only shows up as a thin edge-light along the bar.
//
//  Layout contract — the screen is two equal halves meeting at the exact
//  vertical midpoint, and the scorebar is just what you see where they meet:
//  each half anchors its own score row to the seam, so the divider between the
//  rows IS the tap boundary. Every pixel above it scores top, every pixel below
//  scores bottom, the rows included. That matters because affordance sets aim:
//  an earlier version floated the bar over two separate tap zones, which both
//  swallowed taps in the middle of the screen (the bar was a sibling layer with
//  no gesture) and invited people to aim at the row instead of using the half.
//  Hence the split here between a full-half `tapLayer` that catches everything
//  and a `visualLayer` marked `allowsHitTesting(false)` — the bar is a graphic
//  that happens to be live, never a target of its own. Tapping flashes the
//  whole half, which is what teaches the target size on the first tap.
//

import SwiftUI

/// One half of the Blackbird screen. Owns its score row (anchored to the seam
/// shared with the other half) and, on the top half only, the timer/undo
/// chrome floating above the bar.
private struct BlackbirdHalf: View {
    let data: ScoreSideData
    let games: Int
    let theme: CourtTheme
    let isTop: Bool
    /// Non-nil on the top half only — there's one status strip per screen, and
    /// it hangs above the bar, which is the top half's bottom edge.
    let chrome: GameHeaderData?

    @State private var flash = false

    // MARK: - Bar pieces

    /// Bright when serving, dim otherwise — never hidden. A marker with no
    /// visible "off" state gives nothing to compare against, so there's no way
    /// to learn what the lit one means (cf. Matchstick's unlit lamp).
    private var serveMarker: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(data.isServing
                ? theme.color.blended(toward: .white, by: 0.35)
                : Color.white.opacity(0.16))
            .shadow(color: data.isServing ? theme.color.opacity(0.8) : .clear, radius: 5)
            .frame(width: 20)
    }

    private func youBadge() -> some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.7))
    }

    private func personName(_ label: String) -> some View {
        Text(label.uppercased())
            .font(.system(size: 17, weight: .heavy))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var nameRow: some View {
        HStack(spacing: 6) {
            serveMarker
            personName(data.name)
            if data.isMe { youBadge() }
            if let partnerName = data.partnerName {
                personName("/ \(partnerName)")
                if data.partnerIsMe { youBadge() }
            }
        }
    }

    private var gamesPips: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(games, 1), id: \.self) { i in
                Circle()
                    .fill(i < games ? Color.white.opacity(0.85) : Color.white.opacity(0.15))
                    .frame(width: 5, height: 5)
            }
        }
    }

    /// Outer corners only: the two halves' rows butt together at the seam, so
    /// rounding there would carve a notch out of the middle of the bar.
    private var barShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: isTop ? 4 : 0,
            bottomLeadingRadius: isTop ? 0 : 4,
            bottomTrailingRadius: isTop ? 0 : 4,
            topTrailingRadius: isTop ? 4 : 0
        )
    }

    /// The seam divider isn't drawn as its own hairline — it's where the two
    /// halves' bar outlines meet, which keeps the visible line and the tap
    /// boundary the same thing by construction.
    private var barBackground: some View {
        barShape
            .fill(Color(white: 0.07))
            .overlay(alignment: .leading) {
                Rectangle().fill(theme.color).frame(width: 3).opacity(0.9)
            }
            .clipShape(barShape)
            .overlay(barShape.stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private var scoreRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                nameRow
                gamesPips
            }
            Spacer()
            Text("\(data.score)")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(barBackground)
        .padding(.horizontal, 14)
    }

    /// The strip must collapse to nothing when it has nothing to show —
    /// an empty-but-present HStack would still push the score row off the seam.
    private var hasChrome: Bool {
        guard let chrome else { return false }
        return chrome.isTimeModeEnabled || chrome.canUndo
    }

    @ViewBuilder
    private var statusStrip: some View {
        if let chrome, hasChrome {
            HStack(spacing: 14) {
                if chrome.isTimeModeEnabled {
                    HStack(spacing: 5) {
                        Image(systemName: "timer").font(.caption2)
                        Text(chrome.timerLabel).font(.system(.footnote, design: .monospaced).weight(.bold))
                    }
                    .foregroundStyle(chrome.timerIsUrgent ? .red : .white.opacity(0.75))
                }
                if chrome.canUndo {
                    Button(action: chrome.onUndo) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("a11y.undo")
                }
            }
            .padding(.bottom, 6)
        }
    }

    // MARK: - Layers

    private var tapLayer: some View {
        Color.black
            .contentShape(Rectangle())
            .onTapGesture {
                flash = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { flash = false }
                data.onTap()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(data.name), \(data.score)"))
            .accessibilityAddTraits(.isButton)
    }

    /// Everything drawn on the half. Hit-testing is off so taps land on the
    /// `tapLayer` underneath — except the status strip, whose Undo button is a
    /// real target (and stays its own VoiceOver element, since the tap layer
    /// below it is the thing marked `children: .ignore`, not this).
    private var visualLayer: some View {
        VStack(spacing: 0) {
            statusStrip
            scoreRow
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    var body: some View {
        ZStack(alignment: isTop ? .bottom : .top) {
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

struct BlackbirdScoreboard: View {
    let top: ScoreSideData
    let bottom: ScoreSideData
    let header: GameHeaderData
    let theme: CourtTheme

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                BlackbirdHalf(data: top, games: header.opponentGames, theme: theme, isTop: true, chrome: header)
                BlackbirdHalf(data: bottom, games: header.myGames, theme: theme, isTop: false, chrome: nil)
            }
            .ignoresSafeArea()
        }
    }
}
