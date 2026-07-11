//
//  ContentView.swift
//  badminton score tracker (iOS)
//
//  Root menu, dashboard-style: a quick-stats strip (live from the iCloud-synced
//  history), a prominent New Match button (modal scoring flow), and
//  Settings-style icon rows into History / Stats / Players. iOS uses
//  NavigationStack-based navigation (per ROADMAP Phase 6).
//

import SwiftUI
import BadmintonCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var storeManager: StoreManager
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @State private var showScoring = false
    @State private var pendingFriendInvite: PendingFriendInvite?

    /// Identifiable wrapper so a parsed `badminton://addfriend` link can
    /// drive `.sheet(item:)` — a fresh id per link open means re-tapping the
    /// same invite re-presents the sheet (Roadmap 7d).
    private struct PendingFriendInvite: Identifiable {
        let id = UUID()
        let invite: FriendInviteLink.Invite
    }

    private var myHistory: [MatchRecord] {
        StatsCalculator.playerHistory(store.history, player: myName)
    }

    private var myWinRate: Double {
        StatsCalculator.winRate(player: myName, playerHistory: myHistory)
    }

    /// Same cached-`UserDefaults` lookup `AppStore.friends` uses — the menu
    /// row's badge doesn't need an async `resolveMyParticipantId()` round
    /// trip, just whatever id was already resolved by an earlier visit.
    private var pendingFriendRequestCount: Int {
        guard let myId = UserDefaults.standard.string(forKey: AppStorageKeys.myParticipantId) else { return 0 }
        return store.friendRequests.filter { $0.status == .pending && $0.toParticipantId == myId }.count
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.history.isEmpty {
                    Section {
                        statsStrip
                            .listRowInsets(EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16))
                    }
                }

                Section {
                    newMatchButton
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        menuRow("history.title", systemImage: "list.bullet.rectangle.fill", color: .blue)
                    }
                    NavigationLink {
                        StatsView()
                    } label: {
                        menuRow("stats.title", systemImage: "chart.bar.xaxis", color: .orange)
                    }
                    NavigationLink {
                        RosterView()
                    } label: {
                        menuRow("settings.players", systemImage: "person.2.fill", color: .purple)
                    }
                    NavigationLink {
                        ClubsView()
                    } label: {
                        menuRow("settings.clubs", systemImage: "person.3.fill", color: .teal)
                    }
                    NavigationLink {
                        FriendsView()
                    } label: {
                        friendsMenuRow
                    }
                    NavigationLink {
                        SettingsView()
                    } label: {
                        menuRow("settings.title", systemImage: "gearshape.fill", color: .gray)
                    }
                }
            }
            .navigationTitle(Text("ios.title"))
            .onOpenURL { url in
                guard let invite = FriendInviteLink.parse(url) else { return }
                pendingFriendInvite = PendingFriendInvite(invite: invite)
            }
            .sheet(item: $pendingFriendInvite) { pending in
                FriendInviteView(invite: pending.invite) {
                    pendingFriendInvite = nil
                }
            }
            .fullScreenCover(isPresented: $showScoring) {
                NewMatchFlow(onClose: { showScoring = false })
                    .environmentObject(AppStore.shared)
                    .environmentObject(StoreManager.shared)
            }
            .safeAreaInset(edge: .bottom) {
                if storeManager.entitlements.showsAds {
                    AdBannerView()
                }
            }
        }
    }

    // MARK: - Pieces

    private var statsStrip: some View {
        HStack(spacing: 0) {
            statBlock(value: "\(store.history.count)", labelKey: "stats.matches")
            divider
            statBlock(value: String(format: "%.0f%%", myWinRate), labelKey: "stats.win_rate")
            divider
            statBlock(value: "\(store.roster.count)", labelKey: "settings.players")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 34)
    }

    private func statBlock(value: String, labelKey: LocalizedStringKey) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            Text(labelKey)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var newMatchButton: some View {
        Button {
            showScoring = true
        } label: {
            Label("ios.new_match", systemImage: "plus.circle.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private var friendsMenuRow: some View {
        HStack {
            menuRow("settings.friends", systemImage: "person.2.circle.fill", color: .pink)
            if pendingFriendRequestCount > 0 {
                Spacer()
                Text("\(pendingFriendRequestCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
            }
        }
    }

    private func menuRow(_ titleKey: LocalizedStringKey, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 7)
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .accessibilityHidden(true)
            Text(titleKey)
        }
    }
}
