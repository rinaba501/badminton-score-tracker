//
//  FriendIdentitySnapshot.swift
//  BadmintonCore
//
//  A friend's shared profile identity fields, mirrored one row per
//  participant into the `friend_identity_snapshots` table (RLS: readable by
//  any accepted friend, writable by the owner only). Every field but
//  displayName is independently nil-able: SettingsSnapshot's
//  shareAvatarWithFriends/shareGenderWithFriends/shareBirthdayWithFriends/
//  shareIntroductionWithFriends each gate whether the owner populates that
//  one field before mirroring — a dedicated snapshot table (rather than
//  RLS on the owner's real profile row) is what makes per-field visibility
//  possible at all, since RLS can only grant/deny a whole row. displayName
//  always mirrors (whenever any other field is shared) since the snapshot
//  needs a name to attach fields to — it is NOT a visibility toggle: an
//  accepted FriendRequest already carries a snapshotted displayName, so a
//  friend already knows your name regardless of anything in this file.
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
