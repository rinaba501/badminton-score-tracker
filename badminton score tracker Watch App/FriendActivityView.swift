//
//  FriendActivityView.swift
//  badminton score tracker Watch App
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
//  iOS restyle counterpart is FriendActivityView.swift on that target.
//

import SwiftUI
import BadmintonCore

struct FriendActivityView: View {
    @EnvironmentObject private var appStore: AppStore

    private var participantIds: [String] {
        Set(appStore.friendActivity.keys)
            .union(appStore.friendIdentities.keys)
            .union(appStore.friendStats.keys)
            .sorted { displayName(for: $0) < displayName(for: $1) }
    }

    private func displayName(for participantId: String) -> String {
        appStore.friendIdentities[participantId]?.displayName
            ?? appStore.friendActivity[participantId]?.displayName
            ?? appStore.friendStats[participantId]?.displayName
            ?? appStore.friends.first(where: { $0.participantId == participantId })?.displayName
            ?? participantId
    }

    // Avatar always mirrors unconditionally now (Roadmap issue #272), same
    // fallback-to-gray-until-synced rationale as FriendsView's.
    private func avatarColor(for participantId: String) -> Color {
        guard let colorIndex = appStore.friendIdentities[participantId]?.colorIndex else { return .gray }
        return Player.avatarColors[colorIndex % Player.avatarColors.count]
    }

    var body: some View {
        List {
            if participantIds.isEmpty {
                Text("friends.activity_empty")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(participantIds, id: \.self) { participantId in
                    NavigationLink {
                        FriendProfileDetailView(
                            participantId: participantId,
                            displayName: displayName(for: participantId),
                            identity: appStore.friendIdentities[participantId],
                            stats: appStore.friendStats[participantId],
                            activity: appStore.friendActivity[participantId]
                        )
                    } label: {
                        HStack(spacing: 8) {
                            AvatarView(
                                name: displayName(for: participantId),
                                color: avatarColor(for: participantId),
                                size: 24,
                                iconName: appStore.friendIdentities[participantId]?.iconName
                            )
                            Text(displayName(for: participantId))
                        }
                    }
                }
            }
        }
        .navigationTitle("friends.activity_title")
    }
}

/// Shared with HistoryView's MatchHistoryRow (not private) so a friend's name
/// in any match history list — this device's own History or a friend's
/// shared Activity history — can link straight to their profile.
struct FriendProfileDetailView: View {
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
                HStack(spacing: 8) {
                    AvatarView(name: displayName, color: avatarColor, size: 32, iconName: identity?.iconName)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName).font(.headline)
                        if let genderText {
                            Text(genderText).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                if let introduction = identity?.introduction, !introduction.isEmpty {
                    Text(introduction).font(.caption)
                }
            }

            if let stats {
                Section(header: Text("friends.profile_stats_section")) {
                    HStack {
                        Text("stats.matches")
                        Spacer()
                        Text("\(stats.gamesPlayed)")
                    }
                    HStack {
                        Text("stats.win_rate")
                        Spacer()
                        Text(String(format: "%.0f%%", stats.winRate))
                    }
                    ForEach(stats.headToHead.sorted(by: { $0.key < $1.key }), id: \.key) { opponent, record in
                        HStack {
                            Text(opponent)
                            Spacer()
                            Text("\(record.wins)-\(record.losses)")
                        }
                    }
                }
            }

            if activity != nil {
                Section(header: Text("friends.profile_history_section")) {
                    if sortedHistory.isEmpty {
                        Text("friends.activity_no_matches")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(sortedHistory) { record in
                            MatchHistoryRow(record: record)
                        }
                    }
                }
            }

            if stats == nil && activity == nil && identity == nil {
                Text("friends.profile_nothing_shared")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
        .navigationTitle(displayName)
    }
}
