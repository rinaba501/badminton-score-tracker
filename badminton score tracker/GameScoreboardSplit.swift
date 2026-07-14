//
//  GameScoreboardSplit.swift
//  badminton score tracker (iOS)
//
//  "Bold Split-Screen" GameScreenStyle: two full-bleed zones divided by a
//  diagonal seam, each a giant tap target. The currently-serving side's zone
//  gets the full theme-color gradient field; the other gets a neutral dark
//  field — the color itself broadcasts who's serving, instead of a small
//  dot. Simplified from the mockup: true CSS skew on the name strips isn't
//  native to SwiftUI, approximated with a slight rotation instead.
//

import SwiftUI

/// Clips a rectangle to one side of a line rotated `angle` degrees through
/// its vertical center — `topSide: true` keeps everything above the line.
private struct DiagonalSplit: Shape {
    var topSide: Bool
    var angle: Double = -6.2

    func path(in rect: CGRect) -> Path {
        let rise = rect.width * CGFloat(tan(angle * .pi / 180))
        let midY = rect.height * 0.505
        var path = Path()
        if topSide {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: midY - rise / 2))
            path.addLine(to: CGPoint(x: rect.minX, y: midY + rise / 2))
        } else {
            path.move(to: CGPoint(x: rect.minX, y: midY + rise / 2))
            path.addLine(to: CGPoint(x: rect.maxX, y: midY - rise / 2))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}

/// A wall-clock-driven 0...1 pulse, independent of view-identity churn —
/// score updates redraw `SplitScoreboard` frequently enough that a one-shot
/// `withAnimation` + `.repeatForever` on `@State` was unreliable in practice.
private func blinkPhase(at date: Date, period: Double = 0.85) -> Double {
    let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
    return (sin(t * 2 * .pi) + 1) / 2
}

struct SplitScoreboard: View {
    let top: ScoreSideData
    let bottom: ScoreSideData
    let header: GameHeaderData
    let theme: CourtTheme

    private var fields: some View {
        ZStack {
            Color(white: 0.05)
            LinearGradient(
                colors: top.isServing
                    ? [theme.color.blended(toward: .white, by: 0.15), theme.color, theme.color.blended(toward: .black, by: 0.25)]
                    : [Color(white: 0.09), Color(white: 0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(DiagonalSplit(topSide: true))
            LinearGradient(
                colors: bottom.isServing
                    ? [theme.color.blended(toward: .white, by: 0.15), theme.color, theme.color.blended(toward: .black, by: 0.25)]
                    : [Color(white: 0.09), Color(white: 0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(DiagonalSplit(topSide: false))
        }
        .ignoresSafeArea()
    }

    private var seam: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.55)], startPoint: .leading, endPoint: .trailing))
            .frame(height: 4)
            .rotationEffect(.degrees(-6.2))
            .shadow(color: .white.opacity(0.5), radius: 10)
    }

    private func chyron(for data: ScoreSideData, tabColor: Color) -> some View {
        HStack(spacing: 0) {
            Text(String(data.name.prefix(1)).uppercased())
                .font(.headline.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(tabColor)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(data.name.uppercased())
                        .font(.subheadline.weight(.heavy))
                        .italic()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let partnerName = data.partnerName {
                        Text("/ \(partnerName.uppercased())")
                            .font(.subheadline.weight(.heavy))
                            .italic()
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                if data.isServing {
                    TimelineView(.animation) { context in
                        let pulse = blinkPhase(at: context.date)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                                .shadow(color: .red.opacity(0.3 + pulse * 0.65), radius: 1 + pulse * 5)
                                .opacity(0.35 + pulse * 0.65)
                            Text("game.split_serve")
                                .font(.caption2.weight(.heavy))
                        }
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(theme.color, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.white)
                    }
                    .fixedSize()
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(.white.opacity(0.14))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .rotationEffect(.degrees(-4))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        .shadow(color: theme.color.opacity(data.isServing ? 0.55 : 0), radius: 12)
    }

    /// Renders the score as a distinct blurred, offset "ghost" layer behind
    /// the crisp digits — a real cast shadow rather than a stacked `.shadow()`
    /// modifier (which just darkens the same silhouette in place and reads
    /// flat at this size) — so the number reads as floating off the field.
    private func floatingScore(_ score: Int, isServing: Bool) -> some View {
        let font = Font.system(size: 150, weight: .heavy, design: .rounded)
        return ZStack {
            Text("\(score)")
                .font(font)
                .foregroundStyle(.black.opacity(0.55))
                .blur(radius: 12)
                .offset(x: 7, y: 12)
            Text("\(score)")
                .font(font)
                .foregroundStyle(theme.color.opacity(isServing ? 0.65 : 0))
                .blur(radius: 22)
            Text("\(score)")
                .font(font)
                .foregroundStyle(.white)
        }
        .monospacedDigit()
        .contentTransition(.numericText())
        .animation(.spring(response: 0.32, dampingFraction: 0.55), value: score)
    }

    private func zone(_ data: ScoreSideData, alignment: Alignment) -> some View {
        VStack {
            if alignment == .topTrailing {
                HStack { chyron(for: data, tabColor: Color(white: 0.15)); Spacer() }
                Spacer()
            }
            HStack {
                if alignment == .bottomLeading { Spacer() }
                floatingScore(data.score, isServing: data.isServing)
                if alignment == .topTrailing { Spacer() }
            }
            if alignment == .bottomLeading {
                Spacer()
                HStack { Spacer(); chyron(for: data, tabColor: theme.color) }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { data.onTap() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(data.name), \(data.score)"))
        .accessibilityAddTraits(.isButton)
    }

    private var centerBoard: some View {
        HStack(spacing: 0) {
            VStack(spacing: 1) {
                Text("game.games").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(.white.opacity(0.5))
                Text("\(header.opponentGames)–\(header.myGames)")
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .foregroundStyle(theme.color.blended(toward: .white, by: 0.4))
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            if header.isTimeModeEnabled {
                Divider().frame(height: 26).overlay(.white.opacity(0.14))
                VStack(spacing: 1) {
                    Text("game.timer_label").font(.system(size: 9, weight: .heavy)).tracking(1.2).foregroundStyle(.white.opacity(0.5))
                    Text(header.timerLabel)
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .foregroundStyle(header.timerIsUrgent ? .red : .white)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
            if header.canUndo {
                Divider().frame(height: 26).overlay(.white.opacity(0.14))
                Button(action: header.onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("a11y.undo")
            }
        }
        .background(Color(white: 0.06))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.22), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        .rotationEffect(.degrees(-6.2))
    }

    var body: some View {
        ZStack {
            fields
            seam
            // Equal-height tap zones — a reasonable approximation of the
            // diagonal boundary rather than a pixel-exact match, since the
            // diagonal itself only shifts the visual line by a few points.
            VStack(spacing: 0) {
                zone(top, alignment: .topTrailing)
                zone(bottom, alignment: .bottomLeading)
            }
            centerBoard
        }
    }
}
