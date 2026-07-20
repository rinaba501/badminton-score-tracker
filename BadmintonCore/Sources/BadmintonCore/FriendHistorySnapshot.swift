//
//  FriendHistorySnapshot.swift
//  BadmintonCore
//
//  A friend's shared personal roster + match history — a friend's own
//  players/match_records rows become visible via the friend_can_view_history
//  RLS policy once they've turned on history sharing, and route into this
//  local cache (SupabaseSyncEngine, AppStore.applyRemoteFriendActivity)
//  rather than a duplicated copy. Unlike Club data, this is deliberately
//  kept separate (AppStore.friendActivity) rather than merged into the
//  viewer's own roster/history — it is read-only, someone else's data, and
//  must never be mistaken for or mixed into the viewer's own stats. One
//  snapshot per friend, keyed by their participantId (the same auth.uid()
//  identity space FriendProfile/ChallengeRecord already use).
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
