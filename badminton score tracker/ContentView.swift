//
//  ContentView.swift
//  badminton score tracker (iOS)
//
//  Root browse menu. iOS uses NavigationStack-based navigation (per ROADMAP
//  Phase 6) — the Watch stays the scoring device; the phone browses History
//  and Stats (Roster / Share arrive in follow-up PRs). All screens read the
//  shared AppStore, which the app entry keeps in sync via iCloud KV.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
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
                } footer: {
                    Text("ios.watch_scoring_hint")
                }
            }
            .navigationTitle(Text("ios.title"))
        }
    }
}
