//
//  ClubsView.swift
//  badminton score tracker Watch App
//
//  Roadmap Phase 5d: club list + create. Pure UI over AppStore.saveClubs
//  (Phase 5b) — CKShare zone mechanics (Phase 5c) already handle the
//  CloudKit side of create/rename/delete via AppStore's existing diffing, so
//  this view never talks to CloudKitSyncManager for writes.
//

import SwiftUI
import BadmintonCore

struct ClubsView: View {
    @EnvironmentObject private var appStore: AppStore
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
                            Text(club.name)
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

    private func addClub() {
        let trimmed = newClubName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        appStore.saveClubs(appStore.clubs + [Club(name: trimmed)])
        newClubName = ""
    }
}
