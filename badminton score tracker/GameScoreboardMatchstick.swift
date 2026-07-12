//
//  GameScoreboardMatchstick.swift
//  badminton score tracker (iOS)
//
//  "Matchstick" GameScreenStyle: a skeuomorphic nod to the physical LED
//  scoreboards bolted to gym walls. True 7-segment glyph paths aren't worth
//  the complexity here, so the "unlit ghost segment" look is approximated by
//  drawing each digit twice — a faint full-opacity white duplicate behind a
//  bright theme-colored glowing digit in front, mimicking the dim housing
//  segments visible behind a lit LED number. Serve is a dedicated lamp per
//  side rather than a color field, and games-won render as a row of lamp
//  dots instead of plain text.
//

import SwiftUI

struct MatchstickScoreboard: View {
    let top: ScoreSideData
    let bottom: ScoreSideData
    let header: GameHeaderData
    let theme: CourtTheme

    private let housing = Color(red: 0.07, green: 0.07, blue: 0.08)
    private let bezel = Color(white: 0.2)

    private var glowColor: Color { theme.color.blended(toward: .white, by: 0.25) }

    private func ledDigit(_ score: Int) -> some View {
        ZStack {
            Text("88")
                .foregroundStyle(.white.opacity(0.05))
            Text("\(score)")
                .foregroundStyle(glowColor)
                .shadow(color: glowColor.opacity(0.8), radius: 10)
                .shadow(color: glowColor.opacity(0.5), radius: 20)
        }
        .font(.system(size: 72, weight: .heavy, design: .monospaced))
        .monospacedDigit()
    }

    private func serveLamp(lit: Bool) -> some View {
        Text("game.split_serve")
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.4)
            .foregroundStyle(lit ? Color.black : Color.white.opacity(0.25))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(lit ? AnyShapeStyle(glowColor) : AnyShapeStyle(Color.white.opacity(0.06)))
            .clipShape(Capsule())
            .shadow(color: lit ? glowColor.opacity(0.7) : .clear, radius: 6)
    }

    private func gameLamps(_ games: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<max(games, 3), id: \.self) { i in
                Circle()
                    .fill(i < games ? glowColor : Color.white.opacity(0.08))
                    .frame(width: 7, height: 7)
                    .shadow(color: i < games ? glowColor.opacity(0.7) : .clear, radius: 4)
            }
        }
    }

    private func namePlate(_ data: ScoreSideData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(data.name)
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let partnerName = data.partnerName {
                Text(partnerName)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
            }
            serveLamp(lit: data.isServing)
        }
    }

    private func panel(_ data: ScoreSideData, games: Int) -> some View {
        HStack(spacing: 16) {
            namePlate(data)
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                ledDigit(data.score)
                gameLamps(games)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(housing)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(bezel, lineWidth: 2))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.black.opacity(0.6), lineWidth: 1).padding(2))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { data.onTap() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(data.name), \(data.score)"))
        .accessibilityAddTraits(.isButton)
    }

    private var marquee: some View {
        HStack(spacing: 12) {
            Text("game.games")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.35))
            if header.isTimeModeEnabled {
                HStack(spacing: 5) {
                    Image(systemName: "timer").font(.caption2)
                    Text(header.timerLabel).font(.system(.footnote, design: .monospaced).weight(.bold))
                }
                .foregroundStyle(header.timerIsUrgent ? .red : glowColor)
            }
            if header.canUndo {
                Button(action: header.onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("a11y.undo")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(housing)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(bezel, lineWidth: 1.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    var body: some View {
        VStack(spacing: 12) {
            marquee
            panel(top, games: header.opponentGames)
            panel(bottom, games: header.myGames)
        }
        .padding(14)
        .background(Color(red: 0.03, green: 0.03, blue: 0.035).ignoresSafeArea())
    }
}
