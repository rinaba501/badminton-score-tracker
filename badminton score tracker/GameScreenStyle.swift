//
//  GameScreenStyle.swift
//  badminton score tracker (iOS)
//
//  Selectable visual style for the live-match GameView. iOS-only — the Watch
//  has its own separate GameView (Digital Crown scoring), unaffected by this
//  setting. Free for everyone, unlike some CourtTheme options — no isPremium
//  gating here.
//

import SwiftUI
import UIKit

extension Color {
    /// Manual RGB blend toward another color — `Color.mix(with:by:)` needs
    /// iOS 18, but this app targets iOS 17. Used to derive light theme-tinted
    /// accents (serve dot, winner glow) from the 5 saturated CourtTheme
    /// colors without hardcoding a per-theme light variant.
    func blended(toward other: Color, by amount: Double) -> Color {
        let t = CGFloat(max(0, min(1, amount)))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t)
        )
    }
}

enum GameScreenStyle: String, Codable, CaseIterable {
    case depth      = "Depth"
    case split      = "Split"
    case minimal    = "Minimal"
    case blackbird  = "Blackbird"
    case ledBoard   = "LEDBoard"
    case birdsEye   = "BirdsEye"
    case tug        = "Tug"
    case scoreboard = "Scoreboard"

    var labelKey: LocalizedStringKey {
        switch self {
        case .depth:      "ios.game_screen_style_depth"
        case .split:      "ios.game_screen_style_split"
        case .minimal:    "ios.game_screen_style_minimal"
        case .blackbird:  "ios.game_screen_style_blackbird"
        case .ledBoard:   "ios.game_screen_style_ledboard"
        case .birdsEye:   "ios.game_screen_style_birdseye"
        case .tug:        "ios.game_screen_style_tug"
        case .scoreboard: "ios.game_screen_style_scoreboard"
        }
    }

    /// Scoreboard is the one landscape-native style: GameView flips the
    /// app-wide orientation lock (AppDelegate.setOrientation) to landscape
    /// while it's on screen and back to portrait on exit — every other
    /// screen in the app stays portrait-only.
    var isLandscape: Bool {
        self == .scoreboard
    }
}

// MARK: - Picker (#239)

// SwiftUI's default List/Form Picker renders as a UIMenu on iOS, which only
// supports plain text + a single systemImage per row — any custom label view
// (like a color swatch or thumbnail) silently gets discarded. A pushed
// NavigationLink screen with fully custom rows is the only way to actually
// show a preview per option.
struct GameScreenStylePickerView: View {
    @Binding var selection: GameScreenStyle
    let courtTheme: CourtTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(GameScreenStyle.allCases, id: \.self) { style in
            Button {
                selection = style
                dismiss()
            } label: {
                HStack(spacing: 14) {
                    GameScreenStyleThumbnail(style: style, accentColor: courtTheme.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(style.labelKey)
                            .foregroundStyle(.primary)
                        if style.isLandscape {
                            Label("ios.game_screen_style_landscape_hint", systemImage: "rectangle.landscape.rotate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if style == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(Text("ios.game_screen_style"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Small static mockup conveying each style's visual identity (core
/// colors/shapes only, not a live scoreboard — see #239).
struct GameScreenStyleThumbnail: View {
    let style: GameScreenStyle
    let accentColor: Color

    private static let size = CGSize(width: 60, height: 42)

    var body: some View {
        ZStack {
            content
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch style {
        case .depth: depthContent
        case .split: splitContent
        case .minimal: minimalContent
        case .blackbird: blackbirdContent
        case .ledBoard:   ledBoardContent
        case .birdsEye: birdsEyeContent
        case .tug: tugContent
        case .scoreboard: scoreboardContent
        }
    }

    private var depthContent: some View {
        ZStack {
            LinearGradient(colors: [accentColor, accentColor.opacity(0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 4) {
                Capsule().fill(.white.opacity(0.55)).frame(width: 18, height: 4)
                Rectangle().fill(.white.opacity(0.35)).frame(height: 1)
            }
            .padding(6)
        }
    }

    private var splitContent: some View {
        ZStack {
            Color(.systemGray5)
            DiagonalHalfShape().fill(accentColor)
        }
    }

    private var minimalContent: some View {
        VStack(spacing: 0) {
            Rectangle().fill(accentColor.opacity(0.18))
            Rectangle().fill(Color.secondary.opacity(0.4)).frame(height: 1)
            Rectangle().fill(Color(.systemGray6))
        }
    }

    private var blackbirdContent: some View {
        ZStack {
            Color.black
            Rectangle().fill(.white).frame(height: 3)
            HStack {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.white.opacity(0.6))
                    .rotationEffect(.degrees(90))
                Spacer()
            }
            .padding(.horizontal, 8)
        }
    }

    private var ledBoardContent: some View {
        ZStack {
            Color.black
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(0.08))
                .frame(width: 20, height: 24)
            RoundedRectangle(cornerRadius: 3)
                .fill(accentColor)
                .frame(width: 14, height: 18)
                .shadow(color: accentColor, radius: 4)
        }
    }

    private var birdsEyeContent: some View {
        ZStack {
            accentColor.opacity(0.25)
            Rectangle().fill(.white).frame(height: 2)
            Circle().fill(.white).frame(width: 6, height: 6).offset(x: 10)
        }
    }

    private var tugContent: some View {
        HStack(spacing: 0) {
            accentColor
                .frame(width: Self.size.width * 0.62)
            Color(.systemGray5)
        }
    }

    /// Two flip cards with hinge seams over a theme-colored base rail —
    /// miniature of ClassicScoreboard's manual courtside flip scoreboard.
    private var scoreboardContent: some View {
        ZStack {
            Color(white: 0.12)
            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    ForEach(0..<2, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(white: 0.03))
                            .overlay(Rectangle().fill(.white.opacity(0.35)).frame(height: 1))
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.4), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 9)
                .padding(.top, 7)
                Capsule().fill(accentColor).frame(height: 4).padding(.horizontal, 6)
                    .padding(.bottom, 5)
            }
        }
    }
}

/// A simple diagonal-cut rectangle, standing in for `SplitScoreboard`'s
/// private `DiagonalSplit` shape in the style thumbnail — approximate is
/// enough for a static preview (see #239).
private struct DiagonalHalfShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.65, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX * 0.35, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
