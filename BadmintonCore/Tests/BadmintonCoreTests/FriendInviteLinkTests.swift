//
//  FriendInviteLinkTests.swift
//  BadmintonCoreTests
//
//  Friends v1 (invite-link slice, Roadmap 7d): FriendInviteLink build/parse.
//

import Foundation
import Testing
@testable import BadmintonCore

struct FriendInviteLinkTests {

    // MARK: - Building

    @Test func buildsAnAddFriendURLWithIdAndName() throws {
        let url = try #require(FriendInviteLink.url(participantId: "_abc123", displayName: "Alice"))
        #expect(url.scheme == "badminton")
        #expect(url.host == "addfriend")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        #expect(items.first { $0.name == "id" }?.value == "_abc123")
        #expect(items.first { $0.name == "name" }?.value == "Alice")
    }

    @Test func buildRefusesAnEmptyParticipantId() {
        #expect(FriendInviteLink.url(participantId: "", displayName: "Alice") == nil)
        #expect(FriendInviteLink.url(participantId: "  \n", displayName: "Alice") == nil)
    }

    @Test func buildPercentEncodesAndParseRestoresNonASCIINames() throws {
        let url = try #require(FriendInviteLink.url(participantId: "_abc123", displayName: "凛 & Bob?"))
        let invite = try #require(FriendInviteLink.parse(url))
        #expect(invite.participantId == "_abc123")
        #expect(invite.displayName == "凛 & Bob?")
    }

    @Test func buildTrimsAndCapsTheDisplayName() throws {
        let long = String(repeating: "x", count: 300)
        let url = try #require(FriendInviteLink.url(participantId: "_abc123", displayName: "  \(long)  "))
        let invite = try #require(FriendInviteLink.parse(url))
        #expect(invite.displayName.count == FriendInviteLink.maxDisplayNameLength)
        #expect(invite.displayName == String(repeating: "x", count: FriendInviteLink.maxDisplayNameLength))
    }

    // MARK: - Parsing

    @Test func parseRoundTripsABuiltLink() throws {
        let url = try #require(FriendInviteLink.url(participantId: "_abc123", displayName: "Alice"))
        #expect(FriendInviteLink.parse(url) == FriendInviteLink.Invite(participantId: "_abc123", displayName: "Alice"))
    }

    @Test func parseAcceptsAnIdOnlyLinkWithAnEmptyName() throws {
        let url = try #require(URL(string: "badminton://addfriend?id=_abc123"))
        let invite = try #require(FriendInviteLink.parse(url))
        #expect(invite.participantId == "_abc123")
        #expect(invite.displayName.isEmpty)
    }

    @Test func parseIsCaseInsensitiveOnSchemeAndHost() throws {
        let url = try #require(URL(string: "BADMINTON://AddFriend?id=_abc123&name=Alice"))
        #expect(FriendInviteLink.parse(url)?.participantId == "_abc123")
    }

    @Test func parseCapsAnOverlongNameFromAHandEditedLink() throws {
        let long = String(repeating: "y", count: 300)
        let url = try #require(URL(string: "badminton://addfriend?id=_abc123&name=\(long)"))
        let invite = try #require(FriendInviteLink.parse(url))
        #expect(invite.displayName.count == FriendInviteLink.maxDisplayNameLength)
    }

    @Test func parseRejectsWrongSchemeHostOrMissingId() throws {
        let wrongScheme = try #require(URL(string: "https://addfriend?id=_abc123"))
        let wrongHost = try #require(URL(string: "badminton://newmatch"))
        let missingId = try #require(URL(string: "badminton://addfriend?name=Alice"))
        let emptyId = try #require(URL(string: "badminton://addfriend?id=&name=Alice"))
        #expect(FriendInviteLink.parse(wrongScheme) == nil)
        #expect(FriendInviteLink.parse(wrongHost) == nil)
        #expect(FriendInviteLink.parse(missingId) == nil)
        #expect(FriendInviteLink.parse(emptyId) == nil)
    }
}
