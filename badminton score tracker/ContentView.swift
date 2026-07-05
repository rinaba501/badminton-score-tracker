//
//  ContentView.swift
//  badminton score tracker (iOS)
//
//  Root view. iOS uses NavigationStack-based navigation (per ROADMAP Phase 6),
//  not the Watch's state-driven AppView enum. PR1 ships a placeholder root;
//  History / Stats / Roster destinations arrive in the follow-up PRs.
//

import SwiftUI

struct ContentView: View {
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
            }
            .navigationTitle(Text("ios.title"))
        }
    }
}

#Preview {
    ContentView()
}
