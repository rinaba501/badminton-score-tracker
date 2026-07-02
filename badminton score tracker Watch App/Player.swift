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
    enum SortOrder: String, CaseIterable, Codable {
        case created
        case name
        case nameDescending
        case mostPlayed
        case recentlyUsed
    }

    static var defaultMyName: String { NSLocalizedString("settings.me", comment: "") }
    static var guestNearLabel: String { NSLocalizedString("prematch.guest_near", comment: "") }
    static var guestFarLabel: String { NSLocalizedString("prematch.guest_far", comment: "") }

    /// True for either guest sentinel label offered during player selection.
    /// Guests are intentionally never persisted to the roster.
    static func isGuestName(_ name: String) -> Bool {
        name == guestNearLabel || name == guestFarLabel
    }

    /// Returns whether a name should be persisted as a saved roster player.
    /// The current user is represented by the default/local name and should
    /// remain a selector choice, not a duplicate saved player entry.
    static func shouldBeStoredAsSavedPlayer(_ name: String, currentUserName: String? = nil) -> Bool {
        guard !name.isEmpty, !isGuestName(name) else { return false }
        let currentName = currentUserName ?? defaultMyName
        return name != currentName
    }

    static func sortedPlayers(_ players: [Player], order: SortOrder, history: [MatchRecord] = []) -> [Player] {
        switch order {
        case .created:
            return players
        case .name:
            return players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .nameDescending:
            return players.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending }
        case .mostPlayed:
            let counts = usageCounts(for: players, history: history)
            return players.sorted {
                let lhsCount = counts[$0.id] ?? 0
                let rhsCount = counts[$1.id] ?? 0
                if lhsCount != rhsCount { return lhsCount > rhsCount }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .recentlyUsed:
            let lastUsed = lastUsedDates(for: players, history: history)
            return players.sorted {
                let lhsDate = lastUsed[$0.id] ?? .distantPast
                let rhsDate = lastUsed[$1.id] ?? .distantPast
                if lhsDate != rhsDate { return lhsDate > rhsDate }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        }
    }

    private static func usageCounts(for players: [Player], history: [MatchRecord]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for player in players {
            counts[player.id] = 0
        }
        for record in history {
            for player in players where recordReferences(player, in: record) {
                counts[player.id, default: 0] += 1
            }
        }
        return counts
    }

    private static func lastUsedDates(for players: [Player], history: [MatchRecord]) -> [UUID: Date] {
        var dates: [UUID: Date] = [:]
        for player in players {
            dates[player.id] = .distantPast
        }
        for record in history {
            for player in players where recordReferences(player, in: record) {
                dates[player.id] = max(dates[player.id, default: .distantPast], record.date)
            }
        }
        return dates
    }

    private static func recordReferences(_ player: Player, in record: MatchRecord) -> Bool {
        if let myId = record.myPlayerId, myId == player.id { return true }
        if let oppId = record.opponentPlayerId, oppId == player.id { return true }
        return record.myName == player.name || record.opponentName == player.name
    }
}
