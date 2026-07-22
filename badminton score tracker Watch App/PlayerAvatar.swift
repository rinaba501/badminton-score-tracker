//
//  PlayerAvatar.swift
//  badminton score tracker Watch App
//
//  SwiftUI presentation of the Player model (which lives in BadmintonCore):
//  avatar colors, the avatar image / SF Symbol catalogs, and AvatarView.
//

import SwiftUI
import BadmintonCore

extension Player {
    static let avatarColors: [Color] = [
        .blue, .green, .orange, .purple, .pink, .red,
        .cyan, .mint, .teal, .indigo, .yellow, .brown
    ]

    /// Fixed, colorblind-safe color per guest bird token, index-aligned with
    /// `Player.guestTokens` — deliberately skips red/green (the classic
    /// confusable pair) rather than reusing `avatarColors`' hash-by-index
    /// scheme, so a guest's color stays predictable across a session instead
    /// of depending on `colorIndex` (guests have no roster `Player` row).
    static let guestAvatarColors: [Color] = [
        .blue, .orange, .purple, .yellow, .teal, .brown
    ]

    /// Color for a guest picker button/avatar, keyed by guest token —
    /// index-matched into `guestAvatarColors` via `Player.guestTokens`.
    /// `.gray` for anything not in the current pool (legacy near/far tokens).
    static func guestAvatarColor(for token: String) -> Color {
        guard let idx = Player.guestTokens.firstIndex(of: token) else { return .gray }
        return guestAvatarColors[idx]
    }

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

    /// Monetization: the free subset of `avatarImageNames`/`sportIcons`;
    /// everything else needs Pro or the avatar pack (Entitlements.hasAllAvatars).
    /// Gated only in the editor's picker grids — AvatarView renders whatever a
    /// player already has, so existing rosters never visually regress (e.g.
    /// after a refund).
    static let freeAvatarImageNames: [String] = [
        "avatar_shuttlecock_happy", "avatar_shuttlecock_cute",
        "avatar_racket_happy", "avatar_blue_cap", "avatar_red_cap",
        "avatar_purple_girl", "avatar_messy_bun",
        "avatar_cap_shuttlecock", "avatar_racket_cool",
        "avatar_shuttlecock_angry", "avatar_net"
    ]

    static let freeSportIcons: [String] = [
        "star.fill", "bolt.fill", "flame.fill", "heart.fill",
        "crown.fill", "sun.max.fill", "leaf.fill"
    ]

    /// True for a catalog image/icon outside the free subsets (nil — the
    /// initials avatar — is always free).
    static func isPremiumAvatar(_ iconName: String?) -> Bool {
        guard let iconName else { return false }
        return !freeAvatarImageNames.contains(iconName) && !freeSportIcons.contains(iconName)
            && (avatarImageNames.contains(iconName) || sportIcons.contains(iconName))
    }

    var avatarColor: Color { Self.avatarColors[colorIndex % Self.avatarColors.count] }

    /// Default color + icon for a newly-added player who hasn't picked one —
    /// randomized (not roster.count-indexed) so reopening the add-player sheet
    /// without saving shows a visibly different suggestion each time, instead of
    /// the same combination until an actual player is added. Icon is always from
    /// the free catalog so non-Pro users never get a locked default.
    static func randomDefaultAppearance() -> (colorIndex: Int, iconName: String) {
        (Int.random(in: 0..<avatarColors.count), freeAvatarImageNames.randomElement()!)
    }
}

struct AvatarView: View {
    let name: String
    let color: Color
    var size: CGFloat = 28
    var iconName: String?

    private var initials: String {
        let result = Player.initials(for: name)
        return result.isEmpty ? "?" : result
    }

    /// Guests are sentinel identities with no roster row, so they'd otherwise
    /// fall through to initials derived from their *localized* label ("Guest
    /// Falcon" → "GF", and something different in every other locale). A fixed
    /// glyph keeps them locale-independent; the per-token guest color
    /// (`Player.guestAvatarColor(for:)`) is what tells two guests apart.
    private var resolvedIconName: String? {
        if iconName == nil && Player.isGuestName(name) { return "bird.fill" }
        return iconName
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
            if let icon = resolvedIconName {
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
