//
//  CourtTheme.swift
//  badminton score tracker (iOS)
//
//  Selectable court background colors for the game screen. Per-target copy of
//  the Watch's enum (same raw values / colors); courtTheme is a synced scalar,
//  so the phone and Watch agree on the chosen theme.
//

import SwiftUI

enum CourtTheme: String, Codable, CaseIterable {
    case green  = "Green"
    case blue   = "Blue"
    case red    = "Red"
    case purple = "Purple"
    case black  = "Black"

    /// Monetization: green/blue are free; the rest need Pro or the theme pack
    /// (Entitlements.hasAllThemes). The theme is only picked on the Watch —
    /// on iOS this gates the read site (GameView falls back to .green when
    /// unentitled, e.g. after a refund, without writing the setting back).
    var isPremium: Bool {
        switch self {
        case .green, .blue: return false
        case .red, .purple, .black: return true
        }
    }

    var color: Color {
        switch self {
        case .green:  return Color(red: 0.2, green: 0.6, blue: 0.2)
        case .blue:   return Color(red: 0.1, green: 0.4, blue: 0.8)
        case .red:    return Color(red: 0.75, green: 0.15, blue: 0.15)
        case .purple: return Color(red: 0.45, green: 0.2, blue: 0.7)
        case .black:  return Color(red: 0.1, green: 0.1, blue: 0.1)
        }
    }
}
