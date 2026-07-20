//
//  ClubDetailView.swift
//  badminton score tracker Watch App
//
//  Roadmap Phase 5d: rename, member list, and per-club roster for a single
//  Club. Member list is read live from the CKShare (Phase 5c's
//  fetchOrCreateShare) when Supabase isn't active, and always shows a self
//  row (myRow, badged rather than labeled "You" — see youBadge) as a
//  fallback first row so viewing a club never depends on CloudKit — see the
//  local-first invariant in ROADMAP.md. Since invite-sending UI (5e) doesn't
//  exist yet, a club's only real participant today is its owner, so the
//  fetched list filters out the `.owner` role to avoid double-listing myRow.
//  Roadmap Phase 9f-1: the CloudKit member-list fetch above only actually
//  runs once CloudKit is started again (see CLAUDE.md/AppStore.swift) — with
//  CloudKit no longer auto-started at launch, an unlinked device just falls
//  back to the self-row-only view immediately instead of calling
//  fetchOrCreateShare, since that would silently create a real-but-empty
//  CKShare zone (this club's data was never pushed there).
//  Deleting/leaving a club never deletes match/player data — it only clears
//  clubId back to personal (nil) on every roster player and match record
//  tagged with it, then removes the club via the same AppStore.saveClubs
//  diffing that already routes owned vs. shared deletion correctly (Phase 5c).
//  Roadmap Phase 9d-3: Supabase-active devices read the member list from
//  `club_members`/`profiles` (SupabaseSyncManager.fetchClubMembers) instead
//  of a CKShare, get an owner-only swipe-to-kick action (no equivalent
//  needed on the CloudKit path — UICloudSharingController already offers
//  participant management), and a non-owner's "leave" also explicitly calls
//  leaveClub() since Supabase's owner-only clubs_delete RLS means the
//  existing saveClubs-diffing delete alone wouldn't actually remove
//  membership the way CloudKit's permissive shared-zone delete does.
//

import SwiftUI
import CloudKit
import BadmintonCore
import CloudSyncSpike

/// A club member resolved from a live CKShare fetch, with a stable identity
/// (Roadmap Phase 5 backlog #162) — unlike the display-name-only list this
/// replaced, `id` survives across fetches so a challenge can target a
/// specific participant rather than just a name string.
private struct ClubParticipant: Identifiable, Equatable {
    let id: String
    let name: String
    /// True when this member's CKShare participant id matches an accepted
    /// Friend's FriendProfile.participantId — both resolve to the same
    /// CloudKit user record id for a given Apple ID, so a plain Set lookup
    /// is enough; this is the first place the codebase cross-references
    /// the two id spaces (see AppStore.friends).
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

    @EnvironmentObject private var appStore: AppStore
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
    @State private var promptingForName = false
    @State private var pendingName = ""
    @State private var clubInviteBox: ClubInviteBox?
    @State private var isPreparingInvite = false
    @State private var inviteErrorMessage: String?

    private var club: Club? { appStore.clubs.first { $0.id == clubId } }
    private var isOwned: Bool { club?.ownerRecordName == nil }

    private var clubRoster: [Player] {
        appStore.roster.filter { $0.clubId == clubId }
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
    /// Settings saves a real Player row (SettingsView.savePlayerEdit), so
    /// this shows your actual customized avatar instead of a flat gray
    /// placeholder. Falls back to gray for names with no matching roster
    /// entry (real Club/Friends identities we have no local avatar for).
    private func avatarColor(for name: String) -> Color {
        appStore.roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        appStore.roster.first(where: { $0.name == name })?.iconName
    }

    /// Small badge marking a name as "me" — used on the Members row and on
    /// the matching Standings entry (matched by myName, since that's the
    /// exact string every MatchRecord stores as the participant name).
    private var youBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.caption2)
            .foregroundColor(.secondary)
            .accessibilityLabel("clubs.you")
    }

    private var myRow: some View {
        HStack(spacing: 8) {
            AvatarView(name: myRowName, color: avatarColor(for: myName), size: 24, iconName: avatarIcon(for: myName))
            Text(myRowName).font(.caption)
            youBadge
        }
    }

    private var clubMatches: [MatchRecord] {
        appStore.history.filter { $0.clubId == clubId }
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
    /// Standings footer (#163) — nil when no season is set. No editing UI on
    /// Watch (no DatePicker precedent anywhere in this target); season dates
    /// are set from the iOS companion app only.
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
        appStore.challenges.filter { $0.clubId == clubId }
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
                Section(header: Text("clubs.name")) {
                    TextField("clubs.name", text: $name)
                        .onSubmit { rename(to: name, currentName: club.name) }
                    if isOwned {
                        Toggle("clubs.require_confirmation", isOn: Binding(
                            get: { requireMatchConfirmation },
                            set: { setRequireMatchConfirmation($0) }
                        ))
                        .font(.caption)
                        Toggle("clubs.track_standings", isOn: Binding(
                            get: { trackStandings },
                            set: { setTrackStandings($0) }
                        ))
                        .font(.caption)
                        // Roadmap Phase 9d-2: Watch never had a CKShare
                        // invite flow (UICloudSharingController is
                        // UIKit-only, iOS-only) — a club invite *link*
                        // has no such dependency, so this is the Watch's
                        // first invite-sending affordance, gated to the
                        // Supabase-active case only.
                        if supabaseAccountLinked {
                            Button {
                                Task { await prepareInvite(for: club) }
                            } label: {
                                if isPreparingInvite {
                                    ProgressView()
                                } else {
                                    Label("clubs.invite", systemImage: "person.badge.plus")
                                }
                            }
                            .disabled(isPreparingInvite)
                            .font(.caption)
                        }
                    }
                }

                if !pendingMatches.isEmpty {
                    Section(header: Text("clubs.pending_confirmation")) {
                        ForEach(pendingMatches) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 4) {
                                    Text("\(record.myName) vs \(record.opponentName)")
                                        .font(.caption)
                                    if record.myName == myName || record.opponentName == myName {
                                        youBadge
                                    }
                                }
                                Text("\(record.myGamesWon)-\(record.opponentGamesWon)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Button("clubs.confirm_match") { confirmMatch(record) }
                                        .font(.caption2)
                                    Button("clubs.decline_match", role: .destructive) { pendingDeclineMatch = record }
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }

                if !myChallenges.isEmpty {
                    Section(header: Text("clubs.challenges")) {
                        ForEach(myChallenges) { challenge in
                            challengeRow(challenge)
                        }
                    }
                }

                Section(header: Text("clubs.activity")) {
                    if activityFeed.isEmpty {
                        Text("stats.no_matches")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(activityFeed) { entry in
                            activityRow(entry)
                        }
                    }
                }

                Section(header: Text("clubs.members")) {
                    myRow
                    if loadingParticipants {
                        ProgressView()
                    } else {
                        ForEach(participants) { participant in
                            HStack {
                                AvatarView(name: participant.name, color: .gray, size: 24)
                                Text(participant.name).font(.caption)
                                if participant.isFriend {
                                    Image(systemName: "person.2.fill")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .accessibilityLabel("a11y.club_friend_badge")
                                }
                                Spacer()
                                if !hasPendingChallenge(with: participant.id) {
                                    Button("clubs.challenge") { sendChallenge(to: participant) }
                                        .font(.caption2)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                // Owner-only kick, Supabase-active only — the
                                // CloudKit path already gets this for free
                                // from UICloudSharingController's own
                                // participant-management UI (iOS, but the
                                // membership it edits is shared with Watch).
                                if isOwned && supabaseAccountLinked {
                                    Button("clubs.remove_member", role: .destructive) {
                                        removeMember(participant)
                                    }
                                }
                            }
                        }
                    }
                }

                if trackStandings {
                    Section(
                        header: Text("clubs.standings"),
                        footer: Group {
                            if let seasonLabel {
                                Text(seasonLabel)
                                    .font(.caption2)
                            }
                        }
                    ) {
                        if standings.isEmpty {
                            Text("stats.no_matches")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(standings) { entry in
                                HStack {
                                    AvatarView(name: entry.name, color: avatarColor(for: entry.name), size: 24, iconName: avatarIcon(for: entry.name))
                                    Text(entry.name).font(.caption)
                                    if entry.name == myName {
                                        youBadge
                                    }
                                    Spacer()
                                    Text("\(entry.wins)-\(entry.losses)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }

                Section(header: Text("clubs.roster")) {
                    if clubRoster.isEmpty {
                        Text("settings.no_players")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(clubRoster) { player in
                            Button(action: { editingPlayer = player }) {
                                HStack(spacing: 8) {
                                    AvatarView(name: player.name, color: player.avatarColor, size: 24, iconName: player.iconName)
                                    Text(player.name).font(.caption)
                                }
                            }
                        }
                    }
                    Button(action: {
                        let appearance = Player.randomDefaultAppearance()
                        editingPlayer = Player(
                            name: "",
                            colorIndex: appearance.colorIndex,
                            iconName: appearance.iconName,
                            clubId: clubId
                        )
                    }) {
                        Label("clubs.add_player", systemImage: "plus")
                    }
                }

                Section {
                    Button(role: .destructive, action: { showRemoveConfirm = true }) {
                        Text(isOwned ? "clubs.delete_club" : "clubs.leave_club")
                    }
                }
            }
        }
        .navigationTitle(club?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let club { name = club.name }
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
            let others = appStore.roster.filter { $0.id != player.id }.map(\.name)
            PlayerEditView(initialPlayer: player, existingNames: others, clubs: appStore.clubs, onSave: savePlayer)
        }
        .sheet(item: $clubInviteBox) { box in
            ClubInviteShareSheet(url: box.url)
        }
        .alert("clubs.invite_failed", isPresented: Binding(
            get: { inviteErrorMessage != nil },
            set: { if !$0 { inviteErrorMessage = nil } }
        )) {
            Button("common.ok") { inviteErrorMessage = nil }
        } message: {
            Text(inviteErrorMessage ?? "")
        }
    }

    private var namePrompt: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("friends.display_name_prompt_message")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                TextField("friends.display_name_placeholder", text: $pendingName)
                Button("playeredit.save") { savePendingName() }
                    .disabled(pendingName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("history.cancel") { promptingForName = false }
            }
            .padding()
            .navigationTitle(Text("friends.display_name_prompt_title"))
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

    /// Reaction/comment counts for one feed entry, shown as a caption so the
    /// row itself stays glanceable; the interactive UI lives in the pushed
    /// MatchReactionsView (#164).
    private func reactionSummary(for entry: StatsCalculator.ActivityFeedEntry) -> String {
        let matchReactions = appStore.reactions.filter { $0.clubId == clubId && $0.matchId == entry.id }
        var parts = MatchReactionsView.emojiOptions.compactMap { emoji -> String? in
            let reactionCount = matchReactions.filter { $0.kind == .emoji && $0.content == emoji }.count
            return reactionCount > 0 ? "\(emoji) \(reactionCount)" : nil
        }
        let commentCount = matchReactions.filter { $0.kind == .comment }.count
        if commentCount > 0 {
            parts.append("💬 \(commentCount)")
        }
        return parts.joined(separator: "  ")
    }

    @ViewBuilder
    private func activityRow(_ entry: StatsCalculator.ActivityFeedEntry) -> some View {
        let summary = reactionSummary(for: entry)
        NavigationLink(destination: MatchReactionsView(
            clubId: clubId, entry: entry,
            myParticipantId: myParticipantId, myDisplayName: myDisplayName
        )) {
            let myDisplayNameForEntry = Player.displayName(for: entry.myName)
            let opponentDisplayNameForEntry = Player.displayName(for: entry.opponentName)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    AvatarView(name: myDisplayNameForEntry, color: avatarColor(for: entry.myName), size: 18, iconName: avatarIcon(for: entry.myName))
                    Text(myDisplayNameForEntry)
                    if entry.myName == myName { youBadge }
                    Text("vs")
                    AvatarView(
                        name: opponentDisplayNameForEntry, color: avatarColor(for: entry.opponentName),
                        size: 18, iconName: avatarIcon(for: entry.opponentName)
                    )
                    Text(opponentDisplayNameForEntry)
                    if entry.opponentName == myName { youBadge }
                }
                .font(.caption)
                Text(entry.games.map { "\($0.my)-\($0.opponent)" }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if !entry.isOfficial {
                    Text("clubs.practice_badge")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                if !summary.isEmpty {
                    Text(summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func challengeRow(_ challenge: ChallengeRecord) -> some View {
        let incoming = challenge.toParticipantId == myParticipantId
        VStack(alignment: .leading, spacing: 4) {
            Text(incoming ? challenge.fromDisplayName : challenge.toDisplayName)
                .font(.caption)
            switch challenge.status {
            case .pending where incoming:
                HStack {
                    Button("clubs.accept_challenge") { respond(to: challenge, accept: true) }
                        .font(.caption2)
                    Button("clubs.decline_challenge", role: .destructive) {
                        pendingChallengeResponse = PendingChallengeResponse(challenge: challenge, isCancel: false)
                    }
                        .font(.caption2)
                }
            case .pending:
                HStack {
                    Text("clubs.challenge_pending")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button("clubs.cancel_challenge", role: .destructive) {
                        pendingChallengeResponse = PendingChallengeResponse(challenge: challenge, isCancel: true)
                    }
                        .font(.caption2)
                }
            case .accepted:
                Text("clubs.challenge_accepted")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            case .declined:
                EmptyView()
            }
        }
    }

    private func rename(to newName: String, currentName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != currentName else { return }
        var updated = appStore.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].name = trimmed
        appStore.saveClubs(updated)
    }

    private func setRequireMatchConfirmation(_ newValue: Bool) {
        var updated = appStore.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].requireMatchConfirmation = newValue
        appStore.saveClubs(updated)
    }

    private func setTrackStandings(_ newValue: Bool) {
        var updated = appStore.clubs
        guard let idx = updated.firstIndex(where: { $0.id == clubId }) else { return }
        updated[idx].trackStandings = newValue
        appStore.saveClubs(updated)
    }

    private func confirmMatch(_ record: MatchRecord) {
        var history = appStore.history
        guard let idx = history.firstIndex(where: { $0.id == record.id }) else { return }
        history[idx].isConfirmed = true
        appStore.saveHistory(history)
    }

    private func declineMatch(_ record: MatchRecord) {
        var history = appStore.history
        guard let idx = history.firstIndex(where: { $0.id == record.id }) else { return }
        history[idx].clubId = nil
        appStore.saveHistory(history)
    }

    private func savePlayer(_ updated: Player) {
        var roster = appStore.roster
        if let idx = roster.firstIndex(where: { $0.id == updated.id }) {
            roster[idx] = updated
        } else {
            roster.append(updated)
        }
        appStore.saveRoster(roster)
        editingPlayer = nil
    }

    private func removeClub() {
        // Under Supabase, a non-owner's implicit `clubs` delete (via
        // saveClubs's diffing below) silently no-ops — clubs_delete RLS is
        // owner-only — so the actual membership row needs an explicit
        // removal here. The owner's real delete already cascades to
        // club_members via the FK, matching CloudKit's zone-delete cascade.
        if supabaseAccountLinked && !isOwned {
            Task { await SupabaseSyncManager.shared.leaveClub(clubId: clubId) }
        }
        appStore.saveRoster(appStore.roster.map { player in
            var p = player
            if p.clubId == clubId { p.clubId = nil }
            return p
        })
        appStore.saveHistory(appStore.history.map { record in
            var r = record
            if r.clubId == clubId { r.clubId = nil }
            return r
        })
        appStore.saveClubs(appStore.clubs.filter { $0.id != clubId })
        dismiss()
    }

    private func markActivityViewed() {
        var lastViewed = ClubActivityCodec.decode(lastViewedData)
        lastViewed[clubId.uuidString] = Date()
        lastViewedData = ClubActivityCodec.encode(lastViewed)
        AppStore.shared.enqueueSettingsChange()
    }

    private func sendChallenge(to participant: ClubParticipant) {
        guard let myParticipantId, let myDisplayName else { return }
        let challenge = ChallengeRecord(
            clubId: clubId,
            fromParticipantId: myParticipantId, fromDisplayName: myDisplayName,
            toParticipantId: participant.id, toDisplayName: participant.name
        )
        appStore.saveChallenges(appStore.challenges + [challenge])
    }

    /// Owner-only kick, Supabase-active only (see the swipe action above).
    /// No CloudKit counterpart needed here — kicking a CKShare participant
    /// already happens through UICloudSharingController's own system UI.
    private func removeMember(_ participant: ClubParticipant) {
        guard let userId = UUID(uuidString: participant.id) else { return }
        participants.removeAll { $0.id == participant.id }
        Task { await SupabaseSyncManager.shared.removeMember(clubId: clubId, userId: userId) }
    }

    private func respond(to challenge: ChallengeRecord, accept: Bool) {
        var updated = appStore.challenges
        guard let idx = updated.firstIndex(where: { $0.id == challenge.id }) else { return }
        updated[idx].status = accept ? .accepted : .declined
        appStore.saveChallenges(updated)
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
        // Roadmap Phase 9f-1: CloudKit is no longer started at launch, so
        // AppStore's syncEngine defaults to NoOpSyncEngine until an explicit
        // Supabase sign-in — this club's roster/history/membership data was
        // never pushed to CloudKit in the first place. Calling
        // fetchOrCreateShare here would still silently create (or read) a
        // real CKShare zone with nothing behind it, worse than just falling
        // back to the self-only view a genuine share-fetch failure already
        // produces below.
        loadingParticipants = false
    }

    /// Supabase-active counterpart to the CKShare fetch above — reads
    /// `club_members` (joined against `profiles` for a name) instead of a
    /// live CKShare's participant list. `isFriend` is always false here:
    /// Friends stays CloudKit-only until 9e, so there's no Supabase-side
    /// friend graph yet to cross-reference a member's `auth.uid()` against.
    private func loadParticipantsFromSupabase(club: Club) async {
        let myId = await SupabaseSyncManager.shared.currentUserId()
        let members = await SupabaseSyncManager.shared.fetchClubMembers(clubId: club.id)
        // Same owner-exclusion rule as the CKShare path (owner shows via
        // myRow only when I am the owner), plus exclude myself if I'm a
        // non-owner member.
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

    /// Roadmap Phase 9d-2: creates a `club_invites` row and builds a
    /// `ClubInviteLink` URL — the Watch's first invite-sending affordance,
    /// since CKShare invites (UICloudSharingController) never had a Watch
    /// counterpart. Only reachable when `supabaseAccountLinked`.
    private func prepareInvite(for club: Club?) async {
        guard let club else { return }
        isPreparingInvite = true
        defer { isPreparingInvite = false }
        guard let inviteId = await SupabaseSyncManager.shared.createClubInvite(clubId: club.id),
              let url = ClubInviteLink.url(inviteId: inviteId.uuidString, clubName: club.name) else {
            inviteErrorMessage = NSLocalizedString("clubs.invite_create_failed_message", comment: "")
            return
        }
        clubInviteBox = ClubInviteBox(url: url)
    }
}

/// Wraps a freshly-built `ClubInviteLink` URL for `.sheet(item:)`.
private struct ClubInviteBox: Identifiable {
    let id = UUID()
    let url: URL
}

/// A `ShareLink` over the freshly-created invite URL — works on watchOS
/// since it's just a URL, unlike CloudKit's UICloudSharingController.
private struct ClubInviteShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("clubs.invite_link_ready")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                ShareLink(item: url) {
                    Label("clubs.invite_share", systemImage: "square.and.arrow.up")
                }
                Button("common.done") { dismiss() }
            }
            .padding()
        }
    }
}
