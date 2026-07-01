//
//  MenuView.swift
//  badminton score tracker Watch App
//
//  Root menu: entry points to new match, history, stats, and settings.
//

import SwiftUI

struct MenuView: View {
    @Binding var currentView: ContentView.AppView

    var body: some View {
        List {
            Button(action: { currentView = .preMatch }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("menu.new_match")
                }
            }

            Button(action: { currentView = .history }) {
                HStack {
                    Image(systemName: "clock.arrow.circlepath")
                    Text("menu.history")
                }
            }

            Button(action: { currentView = .stats }) {
                HStack {
                    Image(systemName: "chart.bar.fill")
                    Text("menu.stats")
                }
            }

            Button(action: { currentView = .settings }) {
                HStack {
                    Image(systemName: "gear")
                    Text("menu.settings")
                }
            }
        }
        .navigationTitle("menu.title")
    }
}
