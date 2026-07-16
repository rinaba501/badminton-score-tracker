//
//  StatsView.swift
//  badminton score tracker (iOS)
//
//  Per-player aggregate stats and head-to-head breakdowns, dashboard-style:
//  a win-rate ring with the W–L record, a grid of stat cards, and avatar'd
//  head-to-head rows. All math lives in BadmintonCore.StatsCalculator (shared
//  with the Watch); this screen binds it to the selected player.
//
//  When viewing your own personal stats (selectedClubId == nil && activePlayer
//  == myName — the only case shareStatsWithFriends actually applies to), the
//  header carries an inline icon-only "share with friends" toggle plus a
//  confirmation toast, same pattern as ProfileView's identity-field toggles.
//  toggleStatsSharing here is a deliberate duplicate of
//  FriendSharingSettingsView's.
//

import SwiftUI
import BadmintonCore

struct StatsView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var storeManager: StoreManager
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.shareStatsWithFriends) private var shareStatsWithFriends = false

    @State private var selectedPlayer: String = ""
    @State private var selectedClubId: UUID?
    @State private var showPaywall = false
    @State private var toastMessage: String?

    private var history: [MatchRecord] { store.history.filter { $0.clubId == selectedClubId } }
    private var roster: [Player] { store.roster.filter { $0.clubId == selectedClubId } }

    private var allPlayers: [String] {
        StatsCalculator.allPlayers(history: history, hoisting: myName)
    }

    private var activePlayer: String {
        selectedPlayer.isEmpty ? myName : selectedPlayer
    }

    private var playerHistory: [MatchRecord] {
        StatsCalculator.playerHistory(history, player: activePlayer)
    }

    private var opponents: [String] {
        StatsCalculator.opponents(of: activePlayer, playerHistory: playerHistory)
    }

    private var totalMatches: Int { playerHistory.count }
    private var wins: Int { StatsCalculator.wins(player: activePlayer, playerHistory: playerHistory) }
    private var losses: Int { totalMatches - wins }
    private var winRate: Double { StatsCalculator.winRate(player: activePlayer, playerHistory: playerHistory) }
    private var avgPointsScored: Double { StatsCalculator.avgPointsScored(player: activePlayer, playerHistory: playerHistory) }
    private var avgMatchDuration: TimeInterval { StatsCalculator.avgMatchDuration(playerHistory: playerHistory) }
    private var longestStreak: Int { StatsCalculator.longestStreak(player: activePlayer, playerHistory: playerHistory) }

    private func rosterPlayer(_ name: String) -> Player? {
        roster.first(where: { $0.name == name })
    }

    var body: some View {
        Group {
            if history.isEmpty {
                VStack {
                    Spacer()
                    Text("stats.no_matches").foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                statsList
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
        .navigationTitle("stats.title")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if storeManager.entitlements.showsAds {
                AdBannerView()
            }
        }
        .onAppear {
            if selectedPlayer.isEmpty { selectedPlayer = myName }
        }
        .toolbar {
            if !store.clubs.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { clubFilterMenu }
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    @ViewBuilder private var clubFilterMenu: some View {
        Menu {
            Button {
                selectedClubId = nil
            } label: {
                if selectedClubId == nil {
                    Label("clubs.filter_personal", systemImage: "checkmark")
                } else {
                    Text("clubs.filter_personal")
                }
            }
            Divider()
            ForEach(store.clubs) { club in
                Button {
                    selectedClubId = club.id
                } label: {
                    if selectedClubId == club.id {
                        Label(club.name, systemImage: "checkmark")
                    } else {
                        Text(club.name)
                    }
                }
            }
        } label: {
            Image(systemName: selectedClubId == nil ? "person.3" : "person.3.fill")
        }
        .accessibilityLabel(Text("clubs.filter_label"))
    }

    private var statsList: some View {
        List {
            if allPlayers.count > 1 {
                Section {
                    Picker("stats.player", selection: $selectedPlayer) {
                        ForEach(allPlayers, id: \.self) { name in
                            if name == myName {
                                Label(Player.displayName(for: name), systemImage: "person.fill").tag(name)
                            } else {
                                Text(Player.displayName(for: name)).tag(name)
                            }
                        }
                    }
                }
            }

            Section {
                header
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section {
                statGrid
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if !opponents.isEmpty {
                Section(header: Text("stats.head_to_head")) {
                    if storeManager.entitlements.hasAdvancedStats {
                        ForEach(opponents, id: \.self) { opp in
                            headToHeadRow(opp)
                        }
                    } else {
                        lockedProRow
                    }
                }
            }
        }
    }

    /// Stand-ins for Pro-gated stats: tapping opens the paywall. Solid tint
    /// background (not plain colored text) keeps this legible against any
    /// CourtTheme accent, including lighter ones.
    private var lockedProRow: some View {
        Button(action: { showPaywall = true }) {
            HStack {
                Label("stats.unlock_pro", systemImage: "lock.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
    }

    private func lockedStatCard(labelKey: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Text(verbatim: "12")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .redacted(reason: .placeholder)
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(Color.accentColor, in: Circle())
                    .offset(x: 22, y: -14)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("paywall.locked"))
            Text(labelKey)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { showPaywall = true }
    }

    // MARK: - Header (ring + record)

    private var header: some View {
        HStack(spacing: 20) {
            winRateRing
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "\(wins)W – \(losses)L")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                HStack(spacing: 4) {
                    Text("stats.matches")
                    Text(verbatim: "\(totalMatches)").monospacedDigit()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if isViewingOwnPersonalStats {
                shareStatsToggle
            }
        }
        .padding(.vertical, 4)
    }

    // shareStatsWithFriends gates YOUR OWN precomputed stats snapshot, so the
    // inline toggle only makes sense while looking at your own personal
    // (non-club) numbers — showing it against a club scope or another
    // player's stats would suggest it controls something it doesn't.
    private var isViewingOwnPersonalStats: Bool {
        selectedClubId == nil && activePlayer == myName
    }

    private var shareStatsToggle: some View {
        Toggle(isOn: $shareStatsWithFriends) {
            Label("friends.share_stats_toggle", systemImage: shareStatsWithFriends ? "person.2.fill" : "person.2")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .onChange(of: shareStatsWithFriends) { _, isOn in
            toggleStatsSharing(isOn)
            showToast(isOn ? "profile.share_toast_on" : "profile.share_toast_off")
        }
    }

    private var winRateRing: some View {
        ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0.001, winRate / 100))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(verbatim: String(format: "%.0f%%", winRate))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("stats.win_rate")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 92, height: 92)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("stats.win_rate"))
        .accessibilityValue(Text(verbatim: String(format: "%.0f%%", winRate)))
    }

    // MARK: - Stat cards

    // Always exactly 4 cells (2x2) so nothing orphans onto its own row;
    // avg duration renders as a separate full-width card below instead of
    // competing for a 5th grid slot.
    private var statGrid: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                statCard(value: "\(wins)", labelKey: "stats.wins")
                statCard(value: "\(losses)", labelKey: "stats.losses")
                statCard(value: String(format: "%.1f", avgPointsScored), labelKey: "stats.avg_points")
                if storeManager.entitlements.hasAdvancedStats {
                    statCard(value: "\(longestStreak)", labelKey: "stats.best_streak")
                } else {
                    lockedStatCard(labelKey: "stats.best_streak")
                }
            }
            if avgMatchDuration > 0 {
                statCard(value: StatsCalculator.durationString(avgMatchDuration), labelKey: "stats.avg_duration")
            }
        }
    }

    private func statCard(value: String, labelKey: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(labelKey)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Head-to-head

    private func headToHeadRow(_ opponent: String) -> some View {
        let record = StatsCalculator.headToHead(player: activePlayer, opponent: opponent, history: history, roster: roster)
        let player = rosterPlayer(opponent)
        return HStack(spacing: 10) {
            AvatarView(name: Player.displayName(for: opponent),
                       color: player?.avatarColor ?? .gray,
                       size: 28,
                       iconName: player?.iconName)
            Text(Player.displayName(for: opponent))
            Spacer()
            Text(verbatim: "\(record.wins)W – \(record.losses)L")
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(record.wins >= record.losses ? Color.accentColor : Color.secondary)
        }
    }

    // MARK: - Sharing

    private func toggleStatsSharing(_ isOn: Bool) {
        CloudKitSyncManager.shared.enqueueSettingsChange()
        Task { @MainActor in
            let manager = CloudKitSyncManager.shared
            if isOn {
                await manager.syncFriendsHistoryParticipants()
                manager.enqueueFriendStatsChange()
            } else {
                manager.removeFriendStatsRecord()
                if !store.isSharingAnyProfileData {
                    await manager.revokeFriendsHistoryAccess()
                }
            }
        }
    }

    // Icon-only toggle has no room for a text label, so a toast teaches what
    // just happened at the moment it happens — same pattern as ProfileView.
    private func showToast(_ messageKey: String) {
        let message = NSLocalizedString(messageKey, comment: "")
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }
}
