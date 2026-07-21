//
//  FriendIdentitySnapshot.swift
//  BadmintonCore
//
//  A friend's shared profile identity fields, mirrored one row per
//  participant into the `friend_identity_snapshots` table (RLS: readable by
//  any accepted friend, writable by the owner only). gender/birthday/
//  introduction are independently nil-able: SettingsSnapshot's
//  shareGenderWithFriends/shareBirthdayWithFriends/shareIntroductionWithFriends
//  each gate whether the owner populates that one field before mirroring —
//  a dedicated snapshot table (rather than RLS on the owner's real profile
//  row) is what makes per-field visibility possible at all, since RLS can
//  only grant/deny a whole row. displayName and colorIndex/iconName (the
//  avatar) always mirror unconditionally, same as each other — an accepted
//  FriendRequest already carries a snapshotted displayName so there's no way
//  to hide the name anyway, and avatar isn't sensitive data (Roadmap issue
//  #272 removed its toggle). This record itself is always pushed
//  (AppStore.refreshMyIdentitySnapshot()) since avatar+name alone are always
//  shareable — there's no "share nothing" state anymore.
//
//  Deliberately kept in its own local cache (AppStore.friendIdentities)
//  rather than merged into the viewer's own roster — read-only, someone
//  else's data, same convention as FriendHistorySnapshot/AppStore.friendActivity.
//

import Foundation

public struct FriendIdentitySnapshot: Identifiable, Codable, Equatable {
    public var id: String { participantId }
    public let participantId: String
    public var displayName: String
    public var colorIndex: Int?
    public var iconName: String?
    public var gender: String?
    public var birthday: Date?
    public var introduction: String?

    public init(
        participantId: String,
        displayName: String,
        colorIndex: Int? = nil,
        iconName: String? = nil,
        gender: String? = nil,
        birthday: Date? = nil,
        introduction: String? = nil
    ) {
        self.participantId = participantId
        self.displayName = displayName
        self.colorIndex = colorIndex
        self.iconName = iconName
        self.gender = gender
        self.birthday = birthday
        self.introduction = introduction
    }
}
