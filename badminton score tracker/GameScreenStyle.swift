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
    case depth   = "Depth"
    case split   = "Split"
    case minimal = "Minimal"

    var labelKey: LocalizedStringKey {
        switch self {
        case .depth:   "ios.game_screen_style_depth"
        case .split:   "ios.game_screen_style_split"
        case .minimal: "ios.game_screen_style_minimal"
        }
    }
}
