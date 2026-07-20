//
//  ClubDetailView.swift
//  badminton score tracker (iOS)
//
//  Rename, member list, and per-club roster for a single Club. Member list
//  is read via `SupabaseSyncManager.fetchClubMembers` (`club_members`
//  joined against `profiles`); a self row (myRow, badged rather than
//  labeled "You" — see youBadge) is always shown first so viewing a club
//  never depends on being signed in — see the local-first invariant in
//  ROADMAP.md. The owner-only "Invite" button creates a `club_invites` row
//  and shares a `ClubInviteLink` URL via the system share sheet (works on
//  watchOS too, unlike the old CKShare-based invite this replaced — see
//  the Watch's own ClubDetailView). Deleting/leaving a club never deletes
//  match/player data — it only clears clubId back to personal (nil) on
//  every roster player and match record tagged with it, then removes the
//  club via the existing `AppStore.saveClubs` diffing; a non-owner's
//  "leave" also explicitly calls `leaveClub()` since the owner-only
//  `clubs_delete` RLS means the diffing's implicit delete alone wouldn't
//  remove membership. iOS restyle of the Watch's ClubDetailView. Gets an
//  owner-only swipe-to-kick action on the member list too.
//

import SwiftUI
import BadmintonCore
import CloudSyncSpike

/// A club member resolved from `club_members`/`profiles`, with a stable
/// identity (Roadmap Phase 5 backlog #162) — unlike the display-name-only
/// list this replaced, `id` survives across fetches so a challenge can
/// target a specific participant rather than just a name string.
private struct ClubParticipant: Identifiable, Equatable {
    let id: String
    let name: String
    /// Would cross-reference this member's `auth.uid()` against
    /// `AppStore.friends` the way the two id spaces are already
    /// cross-referenced elsewhere — currently always hardcoded `false`
    /// (see `loadParticipants()`), a known gap, not a CloudKit-cleanup item.
    let isFriend: Bool
}

/// Pending decline/cancel of a ChallengeRecord, awaiting confirmation —
/// `isCancel` distinguishes the two so the dialog message/button read right
/// for whichever side of the challenge tapped it (`respond` itself is the
/// same call either way).
private struct PendingChallengeResponse: Identifiable {
    let challenge: ChallengeRecord
    let isCancel: Bool
    var id: UUID { challenge.id }
}

struct ClubDetailView: View {
    let clubId: UUID

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKeys.clubLastViewedActivity) private var lastViewedData = Data()
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.supabaseAccountLinked) private var supabaseAccountLinked = false

    @State private var name = ""
    @State private var participants: [ClubParticipant] = []
    @State private var myParticipantId: String?
    @State private var myDisplayName: String?
    @State private var loadingParticipants = true
    @State private var showRemoveConfirm = false
    @State private var pendingDeclineMatch: MatchRecord?
    @State private var pendingChallengeResponse: PendingChallengeResponse?
    @State private var editingPlayer: Player?
    @State private var reactionEntry: StatsCalculator.ActivityFeedEntry?
    @State private var clubInviteBox: ClubInviteBox?
    @State private var isPreparingShare = false
    @State private var shareErrorMessage: String?
    @State private var promptingForName = false
    @State private var pendingName = ""
    @State private var hasSeason = false
    @State private var seasonStart = Date()
    @State private var hasSeasonEnd = false
    @State private var seasonEnd = Date()

    private var club: Club? { store.clubs.first { $0.id == clubId } }
    private var isOwned: Bool { club?.ownerRecordName == nil }

    private var clubRoster: [Player] {
        store.roster.filter { $0.clubId == clubId }
    }

    private var requireMatchConfirmation: Bool { club?.requireMatchConfirmation ?? false }
    private var trackStandings: Bool { club?.trackStandings ?? true }

    // Backstop for anyone who skipped the first-launch prompt (ContentView) —
    // passive nudge only, doesn't block viewing/using the club.
    private var needsName: Bool {
        myName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || myName == Player.defaultMyName
    }

    /// Always the local scoring name (myName) — Friends/Clubs no longer have
    /// a separate display name, so this reads like every other name in the
    /// list instead of a generic "You" string. The "clubs.you" key is reused
    /// as the badge's accessibility label instead.
    private var myRowName: String { Player.displayName(for: myName) }

    /// Same avatarColor(for:)/avatarIcon(for:) roster lookup PreMatchView
    /// already uses for its near-side default button — editing "Me" in
    /// RosterView saves a real Player row, so this shows your actual
    /// customized avatar instead of a flat gray placeholder. Falls back to
    /// gray for names with no matching roster entry (real Club/Friends
    /// identities we have no local avatar for).
    private func avatarColor(for name: String) -> Color {
        store.roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        store.roster.first(where: { $0.name == name })?.iconName
    }

    /// Small badge marking a name as "me" — used on the Members row and on
    /// the matching Standings entry (matched by myName, since that's the
    /// exact string every MatchRecord stores as the participant name).
    private var youBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel("clubs.you")
    }

    private var myRow: some View {
        HStack(spacing: 8) {
            AvatarView(name: myRowName, color: avatarColor(for: myName), size: 24, iconName: avatarIcon(for: myName))
            Text(myRowName)
            youBadge
        }
    }

    private var clubMatches: [MatchRecord] {
        store.history.filter { $0.clubId == clubId }
    }

    private var pendingMatches: [MatchRecord] {
        requireMatchConfirmation ? clubMatches.filter { !$0.isConfirmed && $0.isOfficial } : []
    }

    private var standings: [StatsCalculator.StandingsEntry] {
        StatsCalculator.standings(history: clubMatches.filter {
            $0.isOfficial && ($0.isConfirmed || !requireMatchConfirmation) && (club?.isDateInSeason($0.date) ?? true)
        })
    }

    /// Read-only "Season: <start> – <end/present>" label shown in the
    /// Standings footer for both owner and non-owner (#163) — nil when no
    /// season is set, so the footer disappears entirely for the unchanged
    /// all-time default.
    private var seasonLabel: String? {
        guard let start = club?.seasonStartDate else { return nil }
        let startText = start.formatted(date: .abbreviated, time: .omitted)
        guard let end = club?.seasonEndDate else {
            return String(format: NSLocalizedString("clubs.season_open_format", comment: ""), startText)
        }
        let endText = end.formatted(date: .abbreviated, time: .omitted)
        return String(format: NSLocalizedString("clubs.season_range_format", comment: ""), startText, endText)
    }

    private var activityFeed: [StatsCalculator.ActivityFeedEntry] {
        StatsCalculator.activityFeed(history: clubMatches.filter { $0.isConfirmed || !requireMatchConfirmation })
    }

    private var clubChallenges: [ChallengeRecord] {
        store.challenges.filter { $0.clubId == clubId }
    }

    /// Pending + accepted challenges involving me, newest first. Declined
    /// ones are dropped from view entirely — there's no notifications
    /// feature yet (#165), so a quiet drop is fine for this small a feature.
    private var myChallenges: [ChallengeRecord] {
        guard let myParticipantId else { return [] }
        return clubChallenges
            .filter { $0.status != .declined && ($0.fromParticipantId == myParticipantId || $0.toParticipantId == myParticipantId) }
            .sorted { $0.createdDate > $1.createdDate }
    }

    /// Hides the "Challenge" button for a member once a pending challenge
    /// already exists between us (avoids duplicate pings), and while my own
    /// identity is still resolving (can't attribute a challenge to "me" yet).
    private func hasPendingChallenge(with participantId: String) -> Bool {
        guard let myParticipantId else { return true }
        return clubChallenges.contains {
            $0.status == .pending &&
            (($0.fromParticipantId == myParticipantId && $0.toParticipantId == participantId) ||
             ($0.fromParticipantId == participantId && $0.toParticipantId == myParticipantId))
        }
    }

    var body: some View {
        List {
            if let club {
                Section {
                    TextField("clubs.name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { rename(to: name, currentName: club.name) }
                    if isOwned {
                        Toggle("clubs.require_confirmation", isOn: Binding(
                            get: { requireMatchConfirmation },
                            set: { setRequireMatchConfirmation($0) }
                        ))
                        Toggle("clubs.track_standings", isOn: Binding(
                            get: { trackStandings },
                            set: { setTrackStandings($0) }
                        ))
                    }
                } header: {
                    Text("clubs.name")
                } footer: {
                    if isOwned {
                        Text("clubs.require_confirmation_footer")
                        Text("clubs.track_standings_footer")
                    }
                }

                if !pendingMatches.isEmpty {
                    Section {
                        ForEach(pendingMatches) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("\(record.myName) vs \(record.opponentName)")
                                    if record.myName == myName || record.opponentName == myName {
                                        youBadge
                                    }
                                }
                                Text("\(record.myGamesWon)-\(record.opponentGamesWon)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                HStack {
                                    Button("clubs.confirm_match") { confirmMatch(record) }
                                    Button("clubs.decline_match", role: .destructive) { pendingDeclineMatch = record }
                                }
                            }
                        }
                    } header: {
                        Text("clubs.pending_confirmation")
                    }
                }

                if !myChallenges.isEmpty {
                    Section {
                        ForEach(myChallenges) { challenge in
                            challengeRow(challenge)
                        }
                    } header: {
                        Text("clubs.challenges")
                    }
                }

                Section {
                    if activityFeed.isEmpty {
                        ContentUnavailableView("stats.no_matches", systemImage: "clock.arrow.circlepath")
                    } else {
                        ForEach(activityFeed) { entry in
                            activityRow(entry)
                        }
                    }
                } header: {
                    Text("clubs.activity")
                }

                Section {
                    myRow
                    if loadingParticipants {
                        ProgressView()
                    } else {
                        ForEach(participants) { participant in
                            HStack {
                                AvatarView(name: participant.name, color: .gray, size: 24)
                                Text(participant.name)
                                if participant.isFriend {
                                    Image(systemName: "person.2.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .accessibilityLabel("a11y.club_friend_badge")
                                }
                                Spacer()
                                if !hasPendingChallenge(with: participant.id) {
                                    Button("clubs.challenge") { sendChallenge(to: participant) }
                                        .font(.caption)
                                }
                            }
                            .swipeActions {
                                // Owner-only kick — needs to be signed into
                                // Supabase to call it.
                                if isOwned && supabaseAccountLinked {
                                    Button("clubs.remove_member", role: .destructive) {
                                        removeMember(participant)
                                    }
                                }
                            }
                        }
                    }
                    // Needs to be signed into Supabase to create an invite —
                    // same gating as the Watch's own Invite button.
                    if isOwned && supabaseAccountLinked {
                        Button {
                            Task { await prepareInvite(for: club) }
                        } label: {
                            if isPreparingShare {
                                ProgressView()
                            } else {
                                Label("clubs.invite", systemImage: "person.badge.plus")
                            }
                        }
                        .disabled(isPreparingShare)
                    }
                } header: {
                    Text("clubs.members")
                }

                if trackStandings {
                    if isOwned {
                        Section {
                            Toggle("clubs.season_enabled", isOn: Binding(
                                get: { hasSeason },
                                set: { newValue in
                                    hasSeason = newValue
                                    if newValue {
                                        setSeasonDates(start: seasonStart, end: hasSeasonEnd ? seasonEnd : nil)
                                    } else {
                                        hasSeasonEnd = false
                                        setSeasonDates(start: nil, end: nil)
                                    }
                                }
                            ))
                            if hasSeason {
                                DatePicker("clubs.season_start", selection: $seasonStart, displayedComponents: .date)
                                    .onChange(of: seasonStart) { _, newValue in
                                        setSeasonDates(start: newValue, end: hasSeasonEnd ? seasonEnd : nil)
                                    }
                                Toggle("clubs.season_has_end", isOn: Binding(
                                    get: { hasSeasonEnd },
                                    set: { newValue in
                                        hasSeasonEnd = newValue
                                        setSeasonDates(start: seasonStart, end: newValue ? seasonEnd : nil)
                                    }
                                ))
                                if hasSeasonEnd {
                                    DatePicker("clubs.season_end", selection: $seasonEnd, displayedComponents: .date)
                                        .onChange(of: seasonEnd) { _, newValue in
                                            setSeasonDates(start: seasonStart, end: newValue)
                                        }
                                }
                            }
                        } header: {
                            Text("clubs.season")
                        } footer: {
                            Text("clubs.season_footer")
                        }
                    }

                    Section {
                        if standings.isEmpty {
                            ContentUnavailableView("stats.no_matches", systemImage: "trophy")
                        } else {
                            ForEach(standings) { entry in
                                HStack {
                                    AvatarView(name: entry.name, color: avatarColor(for: entry.name), size: 24, iconName: avatarIcon(for: entry.name))
                                    Text(entry.name)
                                    if entry.name == myName {
                                        youBadge
                                    }
                                    Spacer()
                                    Text("\(entry.wins)-\(entry.losses)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } header: {
                        Text("clubs.standings")
                    } footer: {
                        if let seasonLabel {
                            Text(seasonLabel)
                        }
                    }
                }

                Section {
                    if clubRoster.isEmpty {
                        Text("settings.no_players")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(clubRoster) { player in
                            Button {
                                editingPlayer = player
                            } label: {
                                HStack(spacing: 10) {
                                    AvatarView(name: player.name, color: player.avatarColor, size: 30, iconName: player.iconName)
                                    Text(player.name).foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button {
                        let appearance = Player.randomDefaultAppearance()
                        editingPlayer = Player(
                            name: "",
                            colorIndex: appearance.colorIndex,
                            iconName: appearance.iconName,
                            clubId: clubId
                        )
                    } label: {
                        Label("clubs.add_player", systemImage: "plus")
                    }
                } header: {
                    Text("clubs.roster")
                }

                Section {
                    Button(role: .destructive) {
                        showRemoveConfirm = true
                    } label: {
                        Text(isOwned ? "clubs.delete_club" : "clubs.leave_club")
                    }
                }
            }
        }
        .navigationTitle(club?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let club {
                name = club.name
                hasSeason = club.seasonStartDate != nil
                seasonStart = club.seasonStartDate ?? Date()
                hasSeasonEnd = club.seasonEndDate != nil
                seasonEnd = club.seasonEndDate ?? Date()
            }
            loadParticipants()
            markActivityViewed()
            if needsName {
                pendingName = ""
                promptingForName = true
            }
        }
        .sheet(isPresented: $promptingForName) {
            namePrompt
        }
        .confirmationDialog(
            isOwned ? "clubs.delete_confirm" : "clubs.leave_confirm",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button(isOwned ? "clubs.delete_club" : "clubs.leave_club", role: .destructive) {
                removeClub()
            }
        }
        .confirmationDialog(
            "clubs.decline_match_confirm",
            isPresented: Binding(
                get: { pendingDeclineMatch != nil },
                set: { if !$0 { pendingDeclineMatch = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("clubs.decline_match", role: .destructive) {
                if let pendingDeclineMatch { declineMatch(pendingDeclineMatch) }
            }
        }
        .confirmationDialog(
            pendingChallengeResponse?.isCancel == true ? "clubs.cancel_challenge_confirm" : "clubs.decline_challenge_confirm",
            isPresented: Binding(
                get: { pendingChallengeResponse != nil },
                set: { if !$0 { pendingChallengeResponse = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingChallengeResponse {
                Button(pendingChallengeResponse.isCancel ? "clubs.cancel_challenge" : "clubs.decline_challenge", role: .destructive) {
                    respond(to: pendingChallengeResponse.challenge, accept: false)
                }
            }
        }
        .sheet(item: $editingPlayer) { player in
            PlayerEditView(
                initialPlayer: player,
                existingNames: store.roster.filter { $0.id != player.id }.map(\.name),
                clubs: store.clubs,
                onSave: savePlayer
            )
        }
        .sheet(item: $reactionEntry) { entry in
            MatchReactionsView(
                clubId: clubId, entry: entry,
                myParticipantId: myParticipantId, myDisplayName: myDisplayName
            )
        }
        .sheet(item: $clubInviteBox) { box in
            ClubInviteShareSheet(url: box.url)
        }
        .alert("clubs.invite_failed", isPresented: Binding(
            get: { shareErrorMessage != nil },
            set: { if !$0 { shareErrorMessage = nil } }
        )) {
            Button("common.ok") { shareErrorMessage = nil }
        } message: {
            Text(shareErrorMessage ?? "")
        }
    }

    private var namePrompt: some View {
        NavigationStack {
            Form {
                Section {
                    Text("friends.display_name_prompt_message")
                        .foregroundStyle(.secondary)
                    TextField("friends.display_name_placeholder", text: $pendingName)
                }
            }
            .navigationTitle(Text("friends.display_name_prompt_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("history.cancel") { promptingForName = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("playeredit.save") { savePendingName() }
                        .disabled(pendingName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func savePendingName() {
        let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        myName = trimmed
        promptingForName = false
        AppStore.shared.enqueueSettingsChange()
        Task { @MainActor in
            await SupabaseSyncManager.shared.upsertMyProfile(displayName: Player.displayName(for: myName))
        }
    }

    /// One activity-feed row: result + inline emoji reaction chips + a
    /// comment-count button that opens the MatchReactionsView sheet (#164).
    /// The chips are `.borderless` (inside ReactionEmojiButton) so they don't
    /// hijack the List row's tap area.
    @ViewBuilder
    private func activityRow(_ entry: StatsCalculator.ActivityFeedEntry) -> some View {
        let matchReactions = store.reactions.filter { $0.clubId == clubId && $0.matchId == entry.id }
        let commentCount = matchReactions.filter { $0.kind == .comment }.count
        let myDisplayNameForEntry = Player.displayName(for: entry.myName)
        let opponentDisplayNameForEntry = Player.displayName(for: entry.opponentName)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                AvatarView(name: myDisplayNameForEntry, color: avatarColor(for: entry.myName), size: 20, iconName: avatarIcon(for: entry.myName))
                Text(myDisplayNameForEntry)
                if entry.myName == myName { youBadge }
                Text("vs")
                AvatarView(
                    name: opponentDisplayNameForEntry, color: avatarColor(for: entry.opponentName),
                    size: 20, iconName: avatarIcon(for: entry.opponentName)
                )
                Text(opponentDisplayNameForEntry)
                if entry.opponentName == myName { youBadge }
            }
            Text(entry.games.map { "\($0.my)-\($0.opponent)" }.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !entry.isOfficial {
                Text("clubs.practice_badge")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                ForEach(MatchReactionsView.emojiOptions, id: \.self) { emoji in
                    ReactionEmojiButton(
                        emoji: emoji,
                        reactionCount: matchReactions.filter { $0.kind == .emoji && $0.content == emoji }.count,
                        isMine: matchReactions.contains {
                            $0.kind == .emoji && $0.content == emoji && $0.authorParticipantId == myParticipantId
                        },
                        isEnabled: myParticipantId != nil,
                        action: { toggleReaction(emoji, entry: entry) }
                    )
                }
                Button {
                    reactionEntry = entry
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "text.bubble")
                        if commentCount > 0 {
                            Text("\(commentCount)")
                                .font(.caption)
                        }
                    }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("clubs.comments")
            }
            .padding(.top, 2)
        }
    }

    private func toggleReaction(_ emoji: String, entry: StatsCalculator.ActivityFeedEntry) {
        guard let myParticipantId, let myDisplayName else { return }
        let existing = store.reactions.first {
            $0.clubId == clubId && $0.matchId == entry.id &&
            $0.kind == .emoji && $0.content == emoji && $0.authorParticipantId == myParticipantId
        }
        if let existing {
            store.saveReactions(store.reactions.filter { $0.id != existing.id })
        } else {
            let reaction = ReactionRecord(
                clubId: clubId, matchId: entry.id,
                authorParticipantId: myParticipantId, authorDisplayName: myDisplayName,
                kind: .emoji, content: emoji
            )
            store.saveReactions(store.reactions + [reaction])
        }
    }

    @ViewBuilder
    private func challengeRow(_ challenge: ChallengeRecord) -> some View {
        let incoming = challenge.toParticipantId == myParticipantId
        VStack(alignment: .leading, spacing: 4) {
            Text(incoming ? challenge.fromDisplayName : challenge.toDisplayName)
            switch challenge.status {
            case .pending where incoming:
                HStack {
                    Button("clubs.accept_challenge") { respond(to: challenge, accept: true) }
                    Button("clubs.decline_challenge", role: .destructive) {
                        pendingChallengeResponse = PendingChallengeResponse(challenge: challenge, isCancel: false)
                    }
                }
            case .pending:
                HStack {
                    Text("clubs.challenge_pending")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("clubs.cancel_challenge", role: .destructive) {
                        pendingChallengeResponse = PendingChallengeResponse(challenge: challenge, isCancel: true)
                    }
                }
            case .accepted:
                Text("clubs.challenge_accepted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .declined:
                EmptyView()
            }
        }
    }

    private func rename(to newName: String, currentName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != currentName else { return }
        var updated = store.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].name = trimmed
        store.saveClubs(updated)
    }

    private func setRequireMatchConfirmation(_ newValue: Bool) {
        var updated = store.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].requireMatchConfirmation = newValue
        store.saveClubs(updated)
    }

    private func setSeasonDates(start: Date?, end: Date?) {
        var updated = store.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].seasonStartDate = start
        updated[idx].seasonEndDate = end
        store.saveClubs(updated)
    }

    private func setTrackStandings(_ newValue: Bool) {
        var updated = store.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].trackStandings = newValue
        store.saveClubs(updated)
    }

    private func confirmMatch(_ record: MatchRecord) {
        var history = store.history
        guard let idx = history.firstIndex(where: { $0.id == record.id }) else { return }
        history[idx].isConfirmed = true
        store.saveHistory(history)
    }

    private func declineMatch(_ record: MatchRecord) {
        var history = store.history
        guard let idx = history.firstIndex(where: { $0.id == record.id }) else { return }
        history[idx].clubId = nil
        store.saveHistory(history)
    }

    private func savePlayer(_ updated: Player) {
        var roster = store.roster
        if let idx = roster.firstIndex(where: { $0.id == updated.id }) {
            roster[idx] = updated
        } else {
            roster.append(updated)
        }
        store.saveRoster(roster)
        editingPlayer = nil
    }

    private func removeClub() {
        // A non-owner's implicit `clubs` delete (via saveClubs's diffing
        // below) silently no-ops — clubs_delete RLS is owner-only — so the
        // actual membership row needs an explicit removal here. The owner's
        // real delete already cascades to club_members via the FK.
        if supabaseAccountLinked && !isOwned {
            Task { await SupabaseSyncManager.shared.leaveClub(clubId: clubId) }
        }
        store.saveRoster(store.roster.map { player in
            var p = player
            if p.clubId == clubId { p.clubId = nil }
            return p
        })
        store.saveHistory(store.history.map { record in
            var r = record
            if r.clubId == clubId { r.clubId = nil }
            return r
        })
        store.saveClubs(store.clubs.filter { $0.id != clubId })
        dismiss()
    }

    private func markActivityViewed() {
        var lastViewed = ClubActivityCodec.decode(lastViewedData)
        lastViewed[clubId.uuidString] = Date()
        lastViewedData = ClubActivityCodec.encode(lastViewed)
        AppStore.shared.enqueueSettingsChange()
    }

    /// Creates a `club_invites` row and builds a `ClubInviteLink` URL —
    /// works on watchOS too (see the Watch's own ClubDetailView), unlike a
    /// system share sheet tied to one UIKit view controller. Only reachable
    /// when `supabaseAccountLinked` (see the Invite button below).
    private func prepareInvite(for club: Club?) async {
        guard let club else { return }
        isPreparingShare = true
        defer { isPreparingShare = false }
        guard let inviteId = await SupabaseSyncManager.shared.createClubInvite(clubId: club.id),
              let url = ClubInviteLink.url(inviteId: inviteId.uuidString, clubName: club.name) else {
            shareErrorMessage = NSLocalizedString("clubs.invite_create_failed_message", comment: "")
            return
        }
        clubInviteBox = ClubInviteBox(url: url)
    }

    private func sendChallenge(to participant: ClubParticipant) {
        guard let myParticipantId, let myDisplayName else { return }
        let challenge = ChallengeRecord(
            clubId: clubId,
            fromParticipantId: myParticipantId, fromDisplayName: myDisplayName,
            toParticipantId: participant.id, toDisplayName: participant.name
        )
        store.saveChallenges(store.challenges + [challenge])
    }

    /// Owner-only kick, needs to be signed into Supabase (see the swipe
    /// action above).
    private func removeMember(_ participant: ClubParticipant) {
        guard let userId = UUID(uuidString: participant.id) else { return }
        participants.removeAll { $0.id == participant.id }
        Task { await SupabaseSyncManager.shared.removeMember(clubId: clubId, userId: userId) }
    }

    private func respond(to challenge: ChallengeRecord, accept: Bool) {
        var updated = store.challenges
        guard let idx = updated.firstIndex(where: { $0.id == challenge.id }) else { return }
        updated[idx].status = accept ? .accepted : .declined
        store.saveChallenges(updated)
    }

    private func loadParticipants() {
        guard let club else {
            loadingParticipants = false
            return
        }
        loadingParticipants = true
        if supabaseAccountLinked {
            Task { await loadParticipantsFromSupabase(club: club) }
            return
        }
        // Not signed into Supabase — nothing to fetch, fall back to the
        // self-row-only view.
        loadingParticipants = false
    }

    /// Reads `club_members` joined against `profiles` for a name. `isFriend`
    /// is always false here — see `ClubParticipant.isFriend`'s doc comment.
    private func loadParticipantsFromSupabase(club: Club) async {
        let myId = await SupabaseSyncManager.shared.currentUserId()
        let members = await SupabaseSyncManager.shared.fetchClubMembers(clubId: club.id)
        // Exclude the owner (shows via myRow only when I am the owner) and
        // myself if I'm a non-owner member.
        let others = members
            .filter { $0.role != "owner" && $0.userId != myId }
            .map { ClubParticipant(id: $0.userId.uuidString, name: $0.displayName, isFriend: false) }
        await MainActor.run {
            participants = others
            myParticipantId = myId?.uuidString
            myDisplayName = myRowName
            loadingParticipants = false
        }
    }

}

/// Wraps a freshly-built `ClubInviteLink` URL for `.sheet(item:)`.
private struct ClubInviteBox: Identifiable {
    let id = UUID()
    let url: URL
}

/// The Invite sheet: a `ShareLink` over the freshly-created `ClubInviteLink`
/// URL.
private struct ClubInviteShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("clubs.invite_link_ready")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer(minLength: 0)
                ShareLink(item: url) {
                    Label("clubs.invite_share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
            .navigationTitle(Text("clubs.invite_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }
}
