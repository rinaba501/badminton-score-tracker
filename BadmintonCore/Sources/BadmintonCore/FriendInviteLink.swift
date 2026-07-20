//
//  FriendInviteLink.swift
//  BadmintonCore
//
//  Friends v1 (invite-link slice, Roadmap 7d): builds and parses the
//  out-of-band invite link two people exchange to find each other —
//  `badminton://addfriend?id=<participantId>&name=<displayName>` — alongside
//  the existing `badminton://newmatch` scheme. Pure URL formatting/parsing so
//  it is unit-testable on macOS; neither side touches the network. The app
//  targets own what happens around it: generation embeds the sender's own
//  resolved participantId (an `auth.uid()` string, same identity as
//  FriendProfile), and consumption always goes through a confirmation sheet
//  before `sendFriendRequest` is ever called — parsing a link must never
//  trigger a network write by itself.
//
//  The embedded display name is a convenience snapshot so the confirmation
//  sheet can render "Add <name>?" without a profile fetch; it is untrusted
//  free text from whoever composed the URL, so parsing trims it and caps it
//  at `maxDisplayNameLength` (the same public-UGC caution FriendProfile's
//  doc comment flags). The participantId is opaque — no format validation
//  beyond non-emptiness is possible or attempted; a bogus id simply produces
//  a friend request nobody ever fetches.
//

import Foundation

public enum FriendInviteLink {

    public static let scheme = "badminton"
    public static let host = "addfriend"

    /// Cap applied to the display name on both build and parse — links are
    /// UGC that can be edited in transit, so the parser cannot rely on the
    /// builder having enforced it.
    public static let maxDisplayNameLength = 50

    /// A successfully parsed invite link, ready for the confirmation sheet.
    public struct Invite: Equatable {
        public let participantId: String
        /// Trimmed, length-capped; may be empty (the UI falls back to a
        /// generic label).
        public let displayName: String

        public init(participantId: String, displayName: String) {
            self.participantId = participantId
            self.displayName = displayName
        }
    }

    /// Builds `badminton://addfriend?id=<participantId>&name=<displayName>`.
    /// Returns nil only when the participantId is empty after trimming —
    /// there is nothing meaningful to invite with.
    public static func url(participantId: String, displayName: String) -> URL? {
        let id = participantId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "name", value: sanitizedDisplayName(displayName))
        ]
        return components.url
    }

    /// Parses an incoming URL. Returns nil unless the scheme and host match
    /// and a non-empty `id` query item is present; a missing/empty `name`
    /// still parses (with an empty displayName) so an id-only link works.
    public static func parse(_ url: URL) -> Invite? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        let queryItems = components.queryItems ?? []
        let id = queryItems.first { $0.name == "id" }?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty else { return nil }

        let name = queryItems.first { $0.name == "name" }?.value ?? ""
        return Invite(participantId: id, displayName: sanitizedDisplayName(name))
    }

    /// Trim + length-cap shared by build and parse.
    private static func sanitizedDisplayName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxDisplayNameLength))
    }
}
