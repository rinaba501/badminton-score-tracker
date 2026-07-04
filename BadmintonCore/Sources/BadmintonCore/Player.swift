//
//  Player.swift
//  BadmintonCore
//
//  The roster player model. Presentation (avatar colors, images, AvatarView)
//  lives in the app target — see PlayerAvatar.swift there.
//

import Foundation

// MARK: - Player Model

public struct Player: Identifiable, Codable, Equatable {
    public let id: UUID
    public var name: String
    public var colorIndex: Int
    public var iconName: String?

    public init(id: UUID = UUID(), name: String, colorIndex: Int = 0, iconName: String? = nil) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.iconName = iconName
    }

    public var initials: String {
        Self.initials(for: name)
    }

    /// Up-to-two-word initials ("Jane Doe" → "JD"). The single home of the
    /// initials rule — avatar rendering in the app delegates here.
    public static func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        return words.compactMap { $0.first(where: { $0.isLetter }).map(String.init) }.joined().uppercased()
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
    public enum SortOrder: String, CaseIterable, Codable {
        case created
        case name
        case nameDescending
        case mostPlayed
        case recentlyUsed
    }

    // These use bare NSLocalizedString on purpose: it resolves against
    // Bundle.main, i.e. the app bundle that owns the Localizable.strings
    // tables (this package carries no string resources). Under `swift test`
    // there is no app bundle, so these return the raw keys — which stay
    // distinct and non-empty, all the identity checks below need.
    public static var defaultMyName: String { NSLocalizedString("settings.me", comment: "") }
    public static var guestNearLabel: String { NSLocalizedString("prematch.guest_near", comment: "") }
    public static var guestFarLabel: String { NSLocalizedString("prematch.guest_far", comment: "") }

    // Locale-independent identity tokens — what's actually stored in
    // matchMyName/matchOpponentName and MatchRecord.myName/opponentName for a
    // guest selection, instead of the localized label. Because these are
    // fixed literals (never run through NSLocalizedString), guest identity no
    // longer depends on which locale was active when the record was saved or
    // is later read. `guestNearLabel`/`guestFarLabel` remain display-only —
    // use `displayName(for:)` to turn a stored value back into display text.
    public static let guestNearToken = "@@guest_near@@"
    public static let guestFarToken = "@@guest_far@@"

    /// True for a guest identity token, or (for records saved before the
    /// tokens existed) either localized guest label under the *current*
    /// locale. Guests are intentionally never persisted to the roster.
    public static func isGuestName(_ name: String) -> Bool {
        name == guestNearToken || name == guestFarToken || name == guestNearLabel || name == guestFarLabel
    }

    /// Maps a stored identity value back to what should be shown to the
    /// user: a guest token resolves to the current locale's guest label;
    /// anything else (a real name, or a legacy pre-token guest label) passes
    /// through unchanged.
    public static func displayName(for storedName: String) -> String {
        switch storedName {
        case guestNearToken: return guestNearLabel
        case guestFarToken: return guestFarLabel
        default: return storedName
        }
    }

    /// Returns whether a name should be persisted as a saved roster player.
    /// The current user is represented by the default/local name and should
    /// remain a selector choice, not a duplicate saved player entry.
    public static func shouldBeStoredAsSavedPlayer(_ name: String, currentUserName: String? = nil) -> Bool {
        guard !name.isEmpty, !isGuestName(name) else { return false }
        let currentName = currentUserName ?? defaultMyName
        return name != currentName
    }

    public static func sortedPlayers(_ players: [Player], order: SortOrder, history: [MatchRecord] = []) -> [Player] {
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
