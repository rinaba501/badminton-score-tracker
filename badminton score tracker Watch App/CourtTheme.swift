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

/// The Court Theme picker Section, shared by SettingsView's full settings
/// list and InMatchSettingsView's compact in-match sheet (#260). Picking a
/// locked theme snaps back to the last free selection and opens the paywall
/// instead of sticking.
struct CourtThemeSection: View {
    @Binding var courtTheme: CourtTheme
    @Binding var lastFreeTheme: CourtTheme
    @Binding var showPaywall: Bool
    @EnvironmentObject private var storeManager: StoreManager

    var body: some View {
        Section(header: Text("settings.court_theme")) {
            Picker("settings.theme", selection: $courtTheme) {
                ForEach(CourtTheme.allCases, id: \.self) { theme in
                    HStack {
                        Circle()
                            .fill(theme.color)
                            .frame(width: 12, height: 12)
                        Text(NSLocalizedString("theme.\(theme.rawValue.lowercased())", comment: ""))
                        if theme.isPremium && !storeManager.entitlements.hasAllThemes {
                            Spacer()
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .accessibilityLabel(Text("paywall.locked"))
                        }
                    }
                    .tag(theme)
                }
            }
            // Picking a locked theme opens the paywall instead of
            // sticking: snap back to the last free selection.
            .onChange(of: courtTheme) { newTheme in
                if newTheme.isPremium && !storeManager.entitlements.hasAllThemes {
                    courtTheme = lastFreeTheme
                    showPaywall = true
                } else if !newTheme.isPremium {
                    lastFreeTheme = newTheme
                }
            }
        }
    }
}
