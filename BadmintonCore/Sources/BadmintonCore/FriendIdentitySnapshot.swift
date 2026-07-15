//
//  FriendIdentitySnapshot.swift
//  BadmintonCore
//
//  A friend's shared profile identity fields, mirrored into the same
//  "FriendsHistory" CKShare zone FriendHistorySnapshot uses (see
//  CloudKitSyncManager's ensureFriendsHistoryShareExists/
//  syncFriendsHistoryParticipants) — one record per participant, not one
//  per field or per toggle. Every field but displayName is independently
//  nil-able: SettingsSnapshot's shareAvatarWithFriends/shareGenderWithFriends/
//  shareBirthdayWithFriends/shareIntroductionWithFriends each gate whether
//  the owner populates that one field before mirroring, since a CKShare
//  grants zone-wide read access equally to every participant (there's no
//  per-friend content). displayName always mirrors (whenever any other
//  field is shared) since the snapshot needs a name to attach fields to —
//  it is NOT a visibility toggle: an accepted FriendRequest already carries
//  a snapshotted displayName, so a friend already knows your name regardless
//  of anything in this file.
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
