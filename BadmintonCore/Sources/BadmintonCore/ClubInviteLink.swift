//
//  ClubInviteLink.swift
//  BadmintonCore
//
//  Builds and parses the out-of-band link used to join a club —
//  `badminton://joinclub?id=<inviteId>&name=<clubName>` — mirroring
//  FriendInviteLink.swift's exact shape and rationale (pure URL
//  formatting/parsing, unit-testable on macOS, neither side touches the
//  network). Works on watchOS too, since it's just a URL, unlike a
//  UIKit-only system share sheet tied to one view controller.
//
//  `inviteId` identifies a row in the `club_invites` table (its own `id`,
//  not the club's id) — redeeming it goes through the `redeem_club_invite`
//  SECURITY DEFINER RPC, which validates expiry/max_uses server-side before
//  inserting the caller into `club_members`. Consumption always goes
//  through a confirmation view before that RPC is ever called — parsing a
//  link must never trigger a network write by itself, same rule
//  FriendInviteLink's own header comment states.
//
//  The embedded club name is a convenience snapshot for the confirmation
//  view, not a trust boundary: it is untrusted free text from whoever
//  composed the URL, so parsing trims it and caps it at
//  `maxClubNameLength`, the same public-UGC caution FriendInviteLink uses
//  for its display name.
//

import Foundation

public enum ClubInviteLink {

    public static let scheme = "badminton"
    public static let host = "joinclub"

    /// Cap applied to the club name on both build and parse — links are UGC
    /// that can be edited in transit, so the parser cannot rely on the
    /// builder having enforced it.
    public static let maxClubNameLength = 50

    /// A successfully parsed invite link, ready for the confirmation view.
    public struct Invite: Equatable {
        public let inviteId: String
        /// Trimmed, length-capped; may be empty (the UI falls back to a
        /// generic label).
        public let clubName: String

        public init(inviteId: String, clubName: String) {
            self.inviteId = inviteId
            self.clubName = clubName
        }
    }

    /// Builds `badminton://joinclub?id=<inviteId>&name=<clubName>`. Returns
    /// nil only when the inviteId is empty after trimming — there is
    /// nothing meaningful to join with.
    public static func url(inviteId: String, clubName: String) -> URL? {
        let id = inviteId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "name", value: sanitizedClubName(clubName))
        ]
        return components.url
    }

    /// Parses an incoming URL. Returns nil unless the scheme and host match
    /// and a non-empty `id` query item is present; a missing/empty `name`
    /// still parses (with an empty clubName) so an id-only link works.
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
        return Invite(inviteId: id, clubName: sanitizedClubName(name))
    }

    /// Trim + length-cap shared by build and parse.
    private static func sanitizedClubName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(trimmed.prefix(maxClubNameLength))
    }
}
