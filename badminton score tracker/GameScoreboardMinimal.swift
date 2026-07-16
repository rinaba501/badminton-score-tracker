//
//  GameScoreboardMinimal.swift
//  badminton score tracker (iOS)
//
//  "Minimal & Calm" GameScreenStyle: flat rows separated by a hairline
//  divider instead of tile shadows, huge light-weight scores, one restrained
//  accent color. Unlike the static mockup this was designed from (which used
//  a flat off-white background regardless of theme, with only the accent
//  color reflecting Court Theme), the background here is a subtle top-down
//  wash of the active theme color — still calm, but visibly theme-tinted.
//

import SwiftUI

struct MinimalScoreboard: View {
    let top: ScoreSideData
    let bottom: ScoreSideData
    let header: GameHeaderData
    let theme: CourtTheme

    private let ink = Color(white: 0.11)
    private let inkSecondary = Color(white: 0.55)
    private let inkTertiary = Color(white: 0.7)
    private let hairline = Color(white: 0.91)

    private var background: some View {
        ZStack {
            Color(white: 0.984)
            LinearGradient(colors: [theme.color.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Spacer()
            if header.isTimeModeEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "timer").font(.caption)
                    Text(header.timerLabel).font(.system(.subheadline, design: .monospaced).weight(.medium))
                }
                .foregroundStyle(header.timerIsUrgent ? .red : inkSecondary)
            }
            Spacer()
        }
    }

    private var gamesRow: some View {
        HStack(spacing: 10) {
            Text("game.games").font(.system(size: 11, weight: .semibold)).tracking(1.4).foregroundStyle(inkTertiary)
            Text("\(header.opponentGames) – \(header.myGames)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
            if header.canUndo {
                Button(action: header.onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(inkSecondary)
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(hairline, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("a11y.undo")
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func row(_ data: ScoreSideData, showDivider: Bool, isLeader: Bool) -> some View {
        HStack(spacing: 13) {
            Circle()
                .fill(Color(white: 0.94))
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(data.name.prefix(1)).uppercased())
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color(white: 0.42))
                )
            VStack(alignment: .leading, spacing: 6) {
                Text(data.name)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let partnerName = data.partnerName {
                    Text(partnerName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                if data.isServing {
                    HStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Circle().fill(theme.color).frame(width: 6, height: 6)
                            Text("game.split_serve").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.color)
                        }
                        Text("· " + NSLocalizedString(data.serveRight ? "game.right_court" : "game.left_court", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(inkTertiary)
                    }
                }
                if data.isWinner {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                        Text("game.won_last_game").font(.system(size: 10, weight: .bold)).tracking(0.3)
                    }
                    .foregroundStyle(theme.color)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .overlay(Capsule().stroke(theme.color.opacity(0.35), lineWidth: 1))
                }
            }
            Spacer()
            Text("\(data.score)")
                .font(.system(size: 150, weight: isLeader ? .medium : .light, design: .default))
                .foregroundStyle(ink)
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { data.onTap() }
        .overlay(alignment: .top) {
            if showDivider { Rectangle().fill(hairline).frame(height: 1) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(data.name), \(data.score)"))
        .accessibilityAddTraits(.isButton)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar.padding(.top, 6)
            gamesRow.padding(.top, 18).padding(.bottom, 22)
            row(top, showDivider: false, isLeader: top.score > bottom.score)
            row(bottom, showDivider: true, isLeader: bottom.score > top.score)
            Text("game.tap_hint")
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(inkSecondary)
                .padding(.top, 18)
        }
        .padding(.horizontal, 22)
        .padding(.top, 50)
        .padding(.bottom, 30)
        .background(background)
    }
}
