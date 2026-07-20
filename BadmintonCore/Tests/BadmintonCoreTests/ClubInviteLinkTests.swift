//
//  ClubInviteLinkTests.swift
//  BadmintonCoreTests
//
//  Roadmap Phase 9d-2: ClubInviteLink build/parse.
//

import Foundation
import Testing
@testable import BadmintonCore

struct ClubInviteLinkTests {

    // MARK: - Building

    @Test func buildsAJoinClubURLWithIdAndName() throws {
        let url = try #require(ClubInviteLink.url(inviteId: "abc-123", clubName: "Sunday Smashers"))
        #expect(url.scheme == "badminton")
        #expect(url.host == "joinclub")

        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = components.queryItems ?? []
        #expect(items.first { $0.name == "id" }?.value == "abc-123")
        #expect(items.first { $0.name == "name" }?.value == "Sunday Smashers")
    }

    @Test func buildRefusesAnEmptyInviteId() {
        #expect(ClubInviteLink.url(inviteId: "", clubName: "Sunday Smashers") == nil)
        #expect(ClubInviteLink.url(inviteId: "  \n", clubName: "Sunday Smashers") == nil)
    }

    @Test func buildPercentEncodesAndParseRestoresNonASCIINames() throws {
        let url = try #require(ClubInviteLink.url(inviteId: "abc-123", clubName: "凛 & Bob's Club?"))
        let invite = try #require(ClubInviteLink.parse(url))
        #expect(invite.inviteId == "abc-123")
        #expect(invite.clubName == "凛 & Bob's Club?")
    }

    @Test func buildTrimsAndCapsTheClubName() throws {
        let long = String(repeating: "x", count: 300)
        let url = try #require(ClubInviteLink.url(inviteId: "abc-123", clubName: "  \(long)  "))
        let invite = try #require(ClubInviteLink.parse(url))
        #expect(invite.clubName.count == ClubInviteLink.maxClubNameLength)
        #expect(invite.clubName == String(repeating: "x", count: ClubInviteLink.maxClubNameLength))
    }

    // MARK: - Parsing

    @Test func parseRoundTripsABuiltLink() throws {
        let url = try #require(ClubInviteLink.url(inviteId: "abc-123", clubName: "Sunday Smashers"))
        #expect(ClubInviteLink.parse(url) == ClubInviteLink.Invite(inviteId: "abc-123", clubName: "Sunday Smashers"))
    }

    @Test func parseAcceptsAnIdOnlyLinkWithAnEmptyName() throws {
        let url = try #require(URL(string: "badminton://joinclub?id=abc-123"))
        let invite = try #require(ClubInviteLink.parse(url))
        #expect(invite.inviteId == "abc-123")
        #expect(invite.clubName.isEmpty)
    }

    @Test func parseIsCaseInsensitiveOnSchemeAndHost() throws {
        let url = try #require(URL(string: "BADMINTON://JoinClub?id=abc-123&name=Sunday"))
        #expect(ClubInviteLink.parse(url)?.inviteId == "abc-123")
    }

    @Test func parseCapsAnOverlongNameFromAHandEditedLink() throws {
        let long = String(repeating: "y", count: 300)
        let url = try #require(URL(string: "badminton://joinclub?id=abc-123&name=\(long)"))
        let invite = try #require(ClubInviteLink.parse(url))
        #expect(invite.clubName.count == ClubInviteLink.maxClubNameLength)
    }

    @Test func parseRejectsWrongSchemeHostOrMissingId() throws {
        let wrongScheme = try #require(URL(string: "https://joinclub?id=abc-123"))
        let wrongHost = try #require(URL(string: "badminton://newmatch"))
        let missingId = try #require(URL(string: "badminton://joinclub?name=Sunday"))
        let emptyId = try #require(URL(string: "badminton://joinclub?id=&name=Sunday"))
        #expect(ClubInviteLink.parse(wrongScheme) == nil)
        #expect(ClubInviteLink.parse(wrongHost) == nil)
        #expect(ClubInviteLink.parse(missingId) == nil)
        #expect(ClubInviteLink.parse(emptyId) == nil)
    }
}
