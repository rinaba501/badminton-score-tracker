//
//  ContentView.swift
//  badminton score tracker (iOS)
//
//  Root menu, dashboard-style: a quick-stats strip (live from the iCloud-synced
//  history) whose three cells navigate to History/Stats/Players, a prominent
//  New Match button (modal scoring flow), Settings-style icon rows into
//  Profile / History / Stats / Players, and — when at least one match
//  exists — a trailing "last match" card (MatchHistoryRow, reused verbatim
//  from HistoryView.swift) so the screen doesn't end in empty space below
//  the menu. iOS uses NavigationStack-based navigation (per ROADMAP Phase 6). Also owns the
//  first-launch "what should we call you?" prompt (shown once, skippable —
//  see AppStorageKeys.didPromptForName), so a new user's name doesn't sit at
//  the "Me" placeholder by the time Friends/Clubs are ever touched.
//  FriendsView/ClubDetailView carry a lighter backstop nudge for anyone who
//  skips this.
//

import SwiftUI
import BadmintonCore

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var storeManager: StoreManager
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.didPromptForName) private var didPromptForName = false
    @State private var showScoring = false
    @State private var showNamePrompt = false
    @State private var pendingName = ""
    @State private var pendingFriendInvite: PendingFriendInvite?
    @State private var stripDestination: StripDestination?

    /// Three co-located `NavigationLink`s sharing one `List` row (the stats
    /// strip's HStack) mis-route taps — SwiftUI resolves the wrong sibling's
    /// destination (tapping cell N pushes cell N+1's view). Driving the push
    /// through a single `.navigationDestination(item:)` instead sidesteps it.
    private enum StripDestination: Identifiable {
        case history, stats, roster

        var id: Self { self }
    }

    /// Identifiable wrapper so a parsed `badminton://addfriend` link can
    /// drive `.sheet(item:)` — a fresh id per link open means re-tapping the
    /// same invite re-presents the sheet (Roadmap 7d).
    private struct PendingFriendInvite: Identifiable {
        let id = UUID()
        let invite: FriendInviteLink.Invite
    }

    private var needsName: Bool {
        myName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || myName == Player.defaultMyName
    }

    private var myHistory: [MatchRecord] {
        StatsCalculator.playerHistory(store.history, player: myName)
    }

    private var myWinRate: Double {
        StatsCalculator.winRate(player: myName, playerHistory: myHistory)
    }

    private var latestMatch: MatchRecord? {
        store.history.max(by: { $0.date < $1.date })
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
                        ProfileView()
                    } label: {
                        profileMenuRow
                    }
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

                if let latestMatch {
                    Section(header: Text("ios.latest_match_header")) {
                        NavigationLink {
                            HistoryView()
                        } label: {
                            MatchHistoryRow(record: latestMatch)
                        }
                    }
                }
            }
            .navigationTitle(Text("ios.title"))
            .navigationDestination(item: $stripDestination) { destination in
                switch destination {
                case .history: HistoryView()
                case .stats: StatsView()
                case .roster: RosterView()
                }
            }
            .onAppear {
                if !didPromptForName && needsName {
                    pendingName = ""
                    showNamePrompt = true
                }
            }
            .onOpenURL { url in
                guard let invite = FriendInviteLink.parse(url) else { return }
                pendingFriendInvite = PendingFriendInvite(invite: invite)
            }
            .sheet(item: $pendingFriendInvite) { pending in
                FriendInviteView(invite: pending.invite) {
                    pendingFriendInvite = nil
                }
            }
            .sheet(isPresented: $showNamePrompt) {
                welcomeNamePrompt
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

    // Each cell is a real tap target (not just card-styled text) so the
    // strip's tappable appearance matches its behavior. Pushes go through
    // stripDestination/.navigationDestination(item:) rather than a
    // NavigationLink per cell — see StripDestination's doc comment.
    private var statsStrip: some View {
        HStack(spacing: 0) {
            Button {
                stripDestination = .history
            } label: {
                statBlock(value: "\(store.history.count)", labelKey: "stats.matches")
            }
            .buttonStyle(.plain)
            divider
            Button {
                stripDestination = .stats
            } label: {
                statBlock(value: String(format: "%.0f%%", myWinRate), labelKey: "stats.win_rate")
            }
            .buttonStyle(.plain)
            divider
            Button {
                stripDestination = .roster
            } label: {
                statBlock(value: "\(store.roster.count)", labelKey: "settings.players")
            }
            .buttonStyle(.plain)
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

    // "You" as an avatar, not a generic icon tile — mirrors the identity
    // treatment ClubDetailView/PreMatchView give roster names, so this row
    // reads as "this is me" rather than another settings destination.
    private var profileMenuRow: some View {
        let me = store.roster.first(where: { $0.name == myName })
        return HStack(spacing: 12) {
            AvatarView(name: myName, color: me?.avatarColor ?? .gray, size: 30, iconName: me?.iconName)
            Text("ios.profile")
        }
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

    private var welcomeNamePrompt: some View {
        NavigationStack {
            Form {
                Section {
                    Text("onboarding.welcome_name_message")
                        .foregroundStyle(.secondary)
                    TextField("friends.display_name_placeholder", text: $pendingName)
                }
            }
            .navigationTitle(Text("onboarding.welcome_name_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("onboarding.skip") {
                        didPromptForName = true
                        showNamePrompt = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("playeredit.save") { saveWelcomeName() }
                        .disabled(pendingName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func saveWelcomeName() {
        let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        myName = trimmed
        didPromptForName = true
        showNamePrompt = false
        AppStore.shared.enqueueSettingsChange()
        Task { @MainActor in
            try? await CloudKitSyncManager.shared.ensureMyProfileExists(displayName: Player.displayName(for: myName))
        }
    }
}
