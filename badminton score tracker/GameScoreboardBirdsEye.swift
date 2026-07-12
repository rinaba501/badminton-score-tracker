//
//  GameScoreboardBirdsEye.swift
//  badminton score tracker (iOS)
//
//  "Birds-Eye" GameScreenStyle: the background is a simplified top-down
//  badminton court — the net line doubles as the divider between the two tap
//  halves. The serve marker sits in the correct service court (right box on
//  an even score, left on odd, matching real singles/doubles serving rules)
//  rather than being a decorative dot, so the layout communicates the rule
//  itself instead of just tracking who's serving. Games-won render as
//  baseline tally marks.
//

import SwiftUI

struct BirdsEyeScoreboard: View {
    let top: ScoreSideData
    let bottom: ScoreSideData
    let header: GameHeaderData
    let theme: CourtTheme

    private let line = Color.white.opacity(0.55)

    /// Simplified court markings for one half: outer boundary, a short-service
    /// line, and a center line splitting the two service courts.
    private func courtLines(flip: Bool) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                path.addRect(CGRect(x: w * 0.06, y: 0, width: w * 0.88, height: h))
                let shortServiceY = flip ? h * 0.78 : h * 0.22
                path.move(to: CGPoint(x: w * 0.06, y: shortServiceY))
                path.addLine(to: CGPoint(x: w * 0.94, y: shortServiceY))
                path.move(to: CGPoint(x: w * 0.5, y: shortServiceY))
                path.addLine(to: CGPoint(x: w * 0.5, y: flip ? h : 0))
            }
            .stroke(line, lineWidth: 1.5)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [theme.color.blended(toward: .black, by: 0.35), theme.color.blended(toward: .black, by: 0.55)],
                startPoint: .top, endPoint: .bottom
            )
            VStack(spacing: 0) {
                courtLines(flip: false)
                courtLines(flip: true)
            }
            Rectangle().fill(Color.white.opacity(0.85)).frame(height: 2)
        }
        .ignoresSafeArea()
    }

    private func serveMarker(_ data: ScoreSideData, flip: Bool) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.4), radius: 3)
            .opacity(data.isServing ? 1 : 0)
            .frame(maxWidth: .infinity, alignment: data.serveRight != flip ? .trailing : .leading)
            .padding(.horizontal, 28)
    }

    private func gameTally(_ games: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<max(games, 1), id: \.self) { i in
                Rectangle()
                    .fill(i < games ? Color.white.opacity(0.9) : Color.white.opacity(0.2))
                    .frame(width: 3, height: 14)
                    .rotationEffect(.degrees(-12))
            }
        }
    }

    private func nameLabel(_ data: ScoreSideData) -> some View {
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
                Text("· \(partnerName)")
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if data.partnerIsMe {
                    Image(systemName: "checkmark.seal.fill").font(.caption2)
                        .accessibilityLabel("clubs.you")
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func zone(_ data: ScoreSideData, flip: Bool) -> some View {
        VStack(spacing: 6) {
            if flip {
                Spacer()
                Text("\(data.score)")
                    .font(.system(size: 100, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                HStack {
                    nameLabel(data)
                    Spacer()
                    gameTally(header.myGames)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            } else {
                HStack {
                    gameTally(header.opponentGames)
                    Spacer()
                    nameLabel(data)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                Text("\(data.score)")
                    .font(.system(size: 100, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .monospacedDigit()
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: flip ? .top : .bottom) { serveMarker(data, flip: flip) }
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
        .background(.black.opacity(0.45), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                zone(top, flip: false)
                zone(bottom, flip: true)
            }
            centerBadge
        }
    }
}
