//
//  FriendActivityView.swift
//  badminton score tracker (iOS)
//
//  Read-only view of friends' shared profile data — identity (avatar/gender/
//  birthday/introduction), stats, and match history — populated exclusively
//  from AppStore.friendIdentities/friendStats/friendActivity, never
//  AppStore.roster/.history (see those caches' doc comments: this is someone
//  else's data and must never be mixed into the viewer's own caches/stats).
//  Each of the three per-friend caches is filled independently (per-field
//  friend-visibility toggles in FriendsView), so the friend list below is the
//  union of all three keys — a friend who's shared only stats still shows up
//  with just a Stats section. Reuses HistoryView's MatchHistoryRow verbatim.
//  iOS restyle counterpart of the Watch's FriendActivityView (push-based
//  NavigationStack instead of a sheet, otherwise identical).
//

import SwiftUI
import BadmintonCore

struct FriendActivityView: View {
    @EnvironmentObject private var store: AppStore

    private var participantIds: [String] {
        Set(store.friendActivity.keys)
            .union(store.friendIdentities.keys)
            .union(store.friendStats.keys)
            .sorted { displayName(for: $0) < displayName(for: $1) }
    }

    private func displayName(for participantId: String) -> String {
        store.friendIdentities[participantId]?.displayName
            ?? store.friendActivity[participantId]?.displayName
            ?? store.friendStats[participantId]?.displayName
            ?? store.friends.first(where: { $0.participantId == participantId })?.displayName
            ?? participantId
    }

    var body: some View {
        List {
            if participantIds.isEmpty {
                Text("friends.activity_empty")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(participantIds, id: \.self) { participantId in
                    NavigationLink(displayName(for: participantId)) {
                        FriendProfileDetailView(
                            participantId: participantId,
                            displayName: displayName(for: participantId),
                            identity: store.friendIdentities[participantId],
                            stats: store.friendStats[participantId],
                            activity: store.friendActivity[participantId]
                        )
                    }
                }
            }
        }
        .navigationTitle("friends.activity_title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FriendProfileDetailView: View {
    let participantId: String
    let displayName: String
    let identity: FriendIdentitySnapshot?
    let stats: FriendStatsSnapshot?
    let activity: FriendHistorySnapshot?

    private var avatarColor: Color {
        guard let colorIndex = identity?.colorIndex else { return .gray }
        return Player.avatarColors[colorIndex % Player.avatarColors.count]
    }

    private var sortedHistory: [MatchRecord] {
        (activity?.history ?? []).sorted { $0.date > $1.date }
    }

    private var genderText: String? {
        switch identity?.gender {
        case "male": NSLocalizedString("profile.gender_male", comment: "")
        case "female": NSLocalizedString("profile.gender_female", comment: "")
        case "nonbinary": NSLocalizedString("profile.gender_nonbinary", comment: "")
        case let other?: other
        case nil: nil
        }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    AvatarView(name: displayName, color: avatarColor, size: 44, iconName: identity?.iconName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName).font(.headline)
                        if let genderText {
                            Text(genderText).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let introduction = identity?.introduction, !introduction.isEmpty {
                    Text(introduction).font(.callout)
                }
            }

            if let stats {
                Section("friends.profile_stats_section") {
                    LabeledContent("stats.matches", value: "\(stats.gamesPlayed)")
                    LabeledContent("stats.win_rate", value: String(format: "%.0f%%", stats.winRate))
                    ForEach(stats.headToHead.sorted(by: { $0.key < $1.key }), id: \.key) { opponent, record in
                        LabeledContent(opponent, value: "\(record.wins)-\(record.losses)")
                    }
                }
            }

            if activity != nil {
                Section("friends.profile_history_section") {
                    if sortedHistory.isEmpty {
                        Text("friends.activity_no_matches")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(sortedHistory) { record in
                            MatchHistoryRow(record: record)
                        }
                    }
                }
            }

            if stats == nil && activity == nil && identity == nil {
                Text("friends.profile_nothing_shared")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .navigationTitle(displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
