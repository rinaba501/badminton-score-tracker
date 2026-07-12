//
//  CourtTheme.swift
//  badminton score tracker Watch App
//
//  Selectable court background colors for the game screen.
//

import SwiftUI

enum CourtTheme: String, Codable, CaseIterable {
    case green  = "Green"
    case blue   = "Blue"
    case red    = "Red"
    case purple = "Purple"
    case black  = "Black"

    /// Monetization: green/blue/purple are free; red/black need Pro or the
    /// theme pack (Entitlements.hasAllThemes). Gated at the picker
    /// (SettingsView) and at the read site (GameView falls back to .green
    /// when unentitled — e.g. after a refund — without ever writing the
    /// setting back).
    var isPremium: Bool {
        switch self {
        case .green, .blue, .purple: return false
        case .red, .black: return true
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
