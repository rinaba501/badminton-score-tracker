//
//  ContentView.swift
//  badminton score tracker (iOS)
//
//  Root menu. iOS uses NavigationStack-based navigation (per ROADMAP Phase 6).
//  A match can be scored on the phone (New Match → modal scoring flow) or on
//  the Apple Watch; both write to the same iCloud-synced history. History,
//  Stats, and Roster read the shared AppStore.
//

import SwiftUI

struct ContentView: View {
    @State private var showScoring = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        showScoring = true
                    } label: {
                        Label("ios.new_match", systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }

                Section {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Label("history.title", systemImage: "list.bullet.rectangle")
                    }
                    NavigationLink {
                        StatsView()
                    } label: {
                        Label("stats.title", systemImage: "chart.bar.xaxis")
                    }
                    NavigationLink {
                        RosterView()
                    } label: {
                        Label("settings.players", systemImage: "person.2")
                    }
                }
            }
            .navigationTitle(Text("ios.title"))
            .fullScreenCover(isPresented: $showScoring) {
                NewMatchFlow(onClose: { showScoring = false })
                    .environmentObject(AppStore.shared)
            }
        }
    }
}
