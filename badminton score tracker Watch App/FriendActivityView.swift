//
//  FriendActivityView.swift
//  badminton score tracker Watch App
//
//  Read-only view of friends' shared personal roster/history — populated
//  exclusively from AppStore.friendActivity, never AppStore.history/.roster
//  (see that property's doc comment: this is someone else's data and must
//  never be mixed into the viewer's own caches/stats). Reuses HistoryView's
//  MatchHistoryRow verbatim since it only depends on a MatchRecord.
//

import SwiftUI
import BadmintonCore

struct FriendActivityView: View {
    @EnvironmentObject private var appStore: AppStore

    private var snapshots: [FriendHistorySnapshot] {
        appStore.friendActivity.values.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        List {
            if snapshots.isEmpty {
                Text("friends.activity_empty")
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(snapshots) { snapshot in
                    NavigationLink(snapshot.displayName) {
                        FriendActivityDetailView(snapshot: snapshot)
                    }
                }
            }
        }
        .navigationTitle("friends.activity_title")
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
                    .foregroundColor(.secondary)
                    .font(.caption)
            } else {
                ForEach(sortedHistory) { record in
                    MatchHistoryRow(record: record)
                }
            }
        }
        .navigationTitle(snapshot.displayName)
    }
}
