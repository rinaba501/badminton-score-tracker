//
//  GameScoreboardBlackbird.swift
//  badminton score tracker (iOS)
//
//  "Blackbird" GameScreenStyle: a broadcast-style lower-third scorebar on a
//  pure black field, modeled on TV badminton coverage graphics. The score
//  itself never sits under a thumb — the two tap zones are the empty black
//  fields above and below the central bar. Serve is a shape (triangle), not
//  a color, so the style stays legible for color-blind users; Court Theme
//  only shows up as a thin edge-light along the bar.
//

import SwiftUI

struct BlackbirdScoreboard: View {
    let top: ScoreSideData
    let bottom: ScoreSideData
    let header: GameHeaderData
    let theme: CourtTheme

    /// Edge-light leans toward whoever's ahead, standing in for "recent
    /// momentum" without a running rally-streak counter in ScoreSideData.
    private var edgeLeansTop: Bool { top.score >= bottom.score }

    private func serveMarker(isServing: Bool) -> some View {
        Image(systemName: "play.fill")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(isServing ? theme.color.blended(toward: .white, by: 0.35) : .clear)
            .frame(width: 16)
    }

    private func nameRow(_ data: ScoreSideData) -> some View {
        HStack(spacing: 6) {
            serveMarker(isServing: data.isServing)
            Text(data.name.uppercased())
                .font(.system(size: 17, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if data.isMe {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
                    .accessibilityLabel("clubs.you")
            }
            if let partnerName = data.partnerName {
                Text("/ \(partnerName.uppercased())")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    private func gamesPips(_ games: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<max(games, 1), id: \.self) { i in
                Circle()
                    .fill(i < games ? Color.white.opacity(0.85) : Color.white.opacity(0.15))
                    .frame(width: 5, height: 5)
            }
        }
    }

    private func scoreRow(_ data: ScoreSideData, games: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                nameRow(data)
                gamesPips(games)
                    .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.games_won", comment: ""), games, games)))
            }
            Spacer()
            Text("\(data.score)")
                .font(.system(size: 46, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var scorebar: some View {
        VStack(spacing: 0) {
            scoreRow(top, games: header.opponentGames)
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            scoreRow(bottom, games: header.myGames)
        }
        .background(Color(white: 0.07))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(theme.color)
                .frame(width: 3)
                .opacity(0.9)
                .offset(y: edgeLeansTop ? -12 : 12)
                .animation(.easeInOut(duration: 0.4), value: edgeLeansTop)
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.6), radius: 20, y: 4)
        .padding(.horizontal, 14)
    }

    private var statusStrip: some View {
        HStack(spacing: 14) {
            Text("game.games")
                .font(.system(size: 10, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.4))
            if header.isTimeModeEnabled {
                HStack(spacing: 5) {
                    Image(systemName: "timer").font(.caption2)
                    Text(header.timerLabel).font(.system(.footnote, design: .monospaced).weight(.bold))
                }
                .foregroundStyle(header.timerIsUrgent ? .red : .white.opacity(0.75))
            }
            if header.canUndo {
                Button(action: header.onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("a11y.undo")
            }
        }
    }

    private func tapZone(_ data: ScoreSideData) -> some View {
        Color.black
            .contentShape(Rectangle())
            .onTapGesture { data.onTap() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(data.name), \(data.score)"))
            .accessibilityAddTraits(.isButton)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                tapZone(top)
                tapZone(bottom)
            }
            .ignoresSafeArea()
            VStack {
                Spacer()
                statusStrip
                scorebar
                Spacer()
            }
        }
    }
}
