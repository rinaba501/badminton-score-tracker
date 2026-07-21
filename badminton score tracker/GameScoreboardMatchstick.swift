//
//  GameScoreboardMatchstick.swift
//  badminton score tracker (iOS)
//
//  "Matchstick" GameScreenStyle: a skeuomorphic nod to the physical LED
//  scoreboards bolted to gym walls. Score digits render in DSEG7 Classic
//  Bold (SIL OFL licensed, see Fonts/DSEG-LICENSE.txt at repo root and
//  UIAppFonts in Info.plist) — a real 7-segment display font, so the
//  "unlit ghost segment" look (a faint "8" behind a bright theme-colored
//  glowing digit) actually reads as dim housing segments behind a lit LED
//  number, not two unrelated numeral shapes stacked. Each of the two digit
//  positions renders as its own fixed slot (ledDigit) rather than as one
//  string, since a system font's space glyph isn't guaranteed — and DSEG7's
//  measurably isn't — as wide as a digit glyph, which would misalign a
//  single-digit score against the two-slot ghost. Serve is a dedicated lamp
//  per side rather than a color field, and games-won render as a row of
//  lamp dots instead of plain text.
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

    private let ledFont = Font.custom("DSEG7Classic-Bold", size: 72)

    private func ledDigitSlot(_ digit: Character?) -> some View {
        ZStack {
            Text("8")
                .foregroundStyle(.white.opacity(0.09))
            if let digit {
                Text(String(digit))
                    .foregroundStyle(glowColor)
                    .shadow(color: glowColor.opacity(0.9), radius: 3)
                    .shadow(color: glowColor.opacity(0.4), radius: 9)
            }
        }
        .font(ledFont)
    }

    private func ledDigit(_ score: Int) -> some View {
        let clamped = min(max(score, 0), 99)
        let digits = Array(String(clamped))
        let tens: Character? = digits.count > 1 ? digits[0] : nil
        let ones = digits.last!
        return HStack(spacing: 2) {
            ledDigitSlot(tens)
            ledDigitSlot(ones)
        }
    }

    private func serveLampGlow(lit: Bool, opacity: Double) -> Color {
        lit ? glowColor.opacity(opacity) : .clear
    }

    private func serveLamp(lit: Bool) -> some View {
        let capsule: some View = Text("game.split_serve")
            .font(.system(size: 10, weight: .heavy))
            .tracking(1.4)
            .foregroundStyle(lit ? Color.black : Color.white.opacity(0.25))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(lit ? AnyShapeStyle(glowColor) : AnyShapeStyle(Color.white.opacity(0.06)))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(lit ? 0.65 : 0), lineWidth: 1))
        return capsule
            .shadow(color: serveLampGlow(lit: lit, opacity: 0.95), radius: 4)
            .shadow(color: serveLampGlow(lit: lit, opacity: 0.55), radius: 11)
    }

    /// Total games a full-length match can reach for the selected best-of
    /// format (e.g. best-of-3 → 3, best-of-1 → 1) — how many lamp dots
    /// should render, not a fixed minimum.
    private var maxGameSlots: Int { header.gamesToWin * 2 - 1 }

    private func gameLamps(_ games: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(0..<maxGameSlots, id: \.self) { i in
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
