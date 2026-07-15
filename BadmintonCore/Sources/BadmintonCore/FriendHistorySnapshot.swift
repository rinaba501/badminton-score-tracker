//
//  FriendHistorySnapshot.swift
//  BadmintonCore
//
//  A friend's shared personal roster + match history, as mirrored into their
//  own "FriendsHistory" CKShare zone (see CloudKitSyncManager's
//  ensureFriendsHistoryShareExists/syncFriendsHistoryParticipants). Unlike
//  Club data, this is deliberately kept in a separate local cache
//  (AppStore.friendActivity) rather than merged into the viewer's own
//  roster/history — it is read-only, someone else's data, and must never be
//  mistaken for or mixed into the viewer's own stats. One snapshot per
//  friend, keyed by their participantId (the same CKShare-participant /
//  CKContainer.userRecordID identity space FriendProfile/ChallengeRecord
//  already use).
//

import Foundation

public struct FriendHistorySnapshot: Identifiable, Codable, Equatable {
    public var id: String { participantId }
    public let participantId: String
    public var displayName: String
    public var roster: [Player]
    public var history: [MatchRecord]

    public init(
        participantId: String,
        displayName: String,
        roster: [Player] = [],
        history: [MatchRecord] = []
    ) {
        self.participantId = participantId
        self.displayName = displayName
        self.roster = roster
        self.history = history
    }
}
