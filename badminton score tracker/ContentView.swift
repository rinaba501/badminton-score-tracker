//
//  ContentView.swift
//  badminton score tracker (iOS)
//
//  Root view. iOS uses NavigationStack-based navigation (per ROADMAP Phase 6),
//  not the Watch's state-driven AppView enum. The synced-counts line below is
//  a TEMPORARY proof that iCloud KV sync works end-to-end — it makes the PR2
//  two-device test observable and is replaced by the real History / Stats /
//  Roster screens in the follow-up PRs.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "figure.badminton")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("ios.placeholder_message")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Text("ios.synced_summary \(store.history.count) \(store.roster.count)")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .navigationTitle(Text("ios.title"))
        }
    }
}
