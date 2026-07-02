//
//  Player.swift
//  badminton score tracker Watch App
//
//  The roster player model and the avatar view that renders it.
//

import SwiftUI

// MARK: - Player Model

struct Player: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var colorIndex: Int
    var iconName: String?

    init(id: UUID = UUID(), name: String, colorIndex: Int = 0, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.iconName = iconName
    }

    static let avatarColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .red,
        .cyan, .mint, .teal, .indigo, .yellow, .brown
    ]

    static let avatarImageNames: [String] = [
        "avatar_shuttlecock_happy", "avatar_shuttlecock_cute",
        "avatar_shuttlecock_angry",
        "avatar_blonde_girl", "avatar_purple_girl",
        "avatar_messy_bun", "avatar_blue_cap",
        "avatar_cap_shuttlecock", "avatar_headdress",
        "avatar_racket_happy", "avatar_racket_cool",
        "avatar_racket_mustache", "avatar_net",
        "avatar_red_cap", "avatar_viking"
    ]

    static let sportIcons: [String] = [
        "star.fill", "bolt.fill", "flame.fill", "crown.fill",
        "heart.fill", "moon.fill", "sun.max.fill", "snowflake",
        "pawprint.fill", "leaf.fill", "figure.run", "sportscourt.fill"
    ]

    var avatarColor: Color { Self.avatarColors[colorIndex % Self.avatarColors.count] }

    var initials: String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first(where: { $0.isLetter }).map(String.init) }.joined().uppercased()
    }
}

struct AvatarView: View {
    let name: String
    let color: Color
    var size: CGFloat = 28
    var iconName: String? = nil

    private var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let result = words.compactMap { $0.first(where: { $0.isLetter }).map(String.init) }.joined().uppercased()
        return result.isEmpty ? "?" : result
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
            if let icon = iconName {
                if Player.avatarImageNames.contains(icon) {
                    Image(icon)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.48, weight: .medium))
                        .foregroundColor(.white)
                }
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        // Decorative: every AvatarView is shown next to the player's name,
        // so hide it from VoiceOver to avoid a redundant element.
        .accessibilityHidden(true)
    }
}

// MARK: - Sentinel display names

// Guests and the default local-player name are display text, not stored
// player identity (guests are never added to the roster; "me" is just a
// starting value the user can rename). Centralizing them here — instead of
// each screen hardcoding its own English literal — is what lets them be
// localized: every screen that offers or recognizes these labels reads the
// same, current-locale value, so a screen never displays one language's
// version while another screen's identity check expects a different one.
extension Player {
    static var defaultMyName: String { NSLocalizedString("settings.me", comment: "") }
    static var guestNearLabel: String { NSLocalizedString("prematch.guest_near", comment: "") }
    static var guestFarLabel: String { NSLocalizedString("prematch.guest_far", comment: "") }

    /// True for either guest sentinel label offered during player selection.
    /// Guests are intentionally never persisted to the roster.
    static func isGuestName(_ name: String) -> Bool {
        name == guestNearLabel || name == guestFarLabel
    }
}
