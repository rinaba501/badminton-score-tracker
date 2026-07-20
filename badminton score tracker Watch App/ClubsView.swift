//
//  ClubsView.swift
//  badminton score tracker Watch App
//
//  Roadmap Phase 5d: club list + create. Pure UI over AppStore.saveClubs —
//  syncing create/rename/delete is already handled by AppStore's existing
//  diffing, so this view never talks to the sync backend directly.
//

import SwiftUI
import BadmintonCore

struct ClubsView: View {
    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppStorageKeys.clubLastViewedActivity) private var lastViewedData = Data()
    @State private var newClubName = ""

    var body: some View {
        List {
            Section {
                if appStore.clubs.isEmpty {
                    Text("clubs.empty")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(appStore.clubs) { club in
                        NavigationLink(destination: ClubDetailView(clubId: club.id)) {
                            HStack(spacing: 6) {
                                Text(club.name)
                                if hasUnreadActivity(club) {
                                    Circle().fill(.blue).frame(width: 8, height: 8)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                TextField("clubs.new_club_placeholder", text: $newClubName)
                Button(action: addClub) {
                    Label("clubs.add", systemImage: "plus")
                }
                .disabled(newClubName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("settings.clubs")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hasUnreadActivity(_ club: Club) -> Bool {
        let matches = appStore.history.filter {
            $0.clubId == club.id && ($0.isConfirmed || !(club.requireMatchConfirmation ?? false))
        }
        // Reactions/comments (#164) count as activity too, so a teammate's
        // 👍 on an old match still lights the dot.
        let reactionDates = appStore.reactions.filter { $0.clubId == club.id }.map(\.createdDate)
        guard let latest = (matches.map(\.date) + reactionDates).max() else { return false }
        let lastViewed = ClubActivityCodec.decode(lastViewedData)[club.id.uuidString]
        return lastViewed == nil || latest > lastViewed!
    }

    private func addClub() {
        let trimmed = newClubName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appStore.saveClubs(appStore.clubs + [Club(name: trimmed)])
        newClubName = ""
    }
}
