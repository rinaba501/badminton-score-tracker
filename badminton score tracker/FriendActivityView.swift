//
//  FriendActivityView.swift
//  badminton score tracker (iOS)
//
//  Read-only view of friends' shared personal roster/history — populated
//  exclusively from AppStore.friendActivity, never AppStore.history/.roster
//  (see that property's doc comment: this is someone else's data and must
//  never be mixed into the viewer's own caches/stats). Reuses HistoryView's
//  MatchHistoryRow verbatim since it only depends on a MatchRecord. iOS
//  restyle counterpart of the Watch's FriendActivityView (push-based
//  NavigationStack instead of a sheet, otherwise identical).
//

import SwiftUI
import BadmintonCore

struct FriendActivityView: View {
    @EnvironmentObject private var store: AppStore

    private var snapshots: [FriendHistorySnapshot] {
        store.friendActivity.values.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        List {
            if snapshots.isEmpty {
                Text("friends.activity_empty")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(snapshots) { snapshot in
                    NavigationLink(snapshot.displayName) {
                        FriendActivityDetailView(snapshot: snapshot)
                    }
                }
            }
        }
        .navigationTitle("friends.activity_title")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct FriendActivityDetailView: View {
    let snapshot: FriendHistorySnapshot

    private var sortedHistory: [MatchRecord] {
        snapshot.history.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
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
        .navigationTitle(snapshot.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
