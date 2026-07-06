//
//  ClubsView.swift
//  badminton score tracker (iOS)
//
//  Roadmap Phase 5d: club list + create. Pure UI over AppStore.saveClubs
//  (Phase 5b) — CKShare zone mechanics (Phase 5c) already handle the
//  CloudKit side of create/rename/delete via AppStore's existing diffing, so
//  this view never talks to CloudKitSyncManager for writes. iOS restyle of
//  the Watch's ClubsView.
//

import SwiftUI
import BadmintonCore

struct ClubsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newClubName = ""

    var body: some View {
        List {
            Section {
                if store.clubs.isEmpty {
                    Text("clubs.empty")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(store.clubs) { club in
                        NavigationLink {
                            ClubDetailView(clubId: club.id)
                        } label: {
                            Text(club.name)
                        }
                    }
                }
            }

            Section {
                TextField("clubs.new_club_placeholder", text: $newClubName)
                Button {
                    addClub()
                } label: {
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
        store.saveClubs(store.clubs + [Club(name: trimmed)])
        newClubName = ""
    }
}
