//
//  ClubDetailView.swift
//  badminton score tracker Watch App
//
//  Roadmap Phase 5d: rename, member list, and per-club roster for a single
//  Club. Member list is read live from the CKShare (Phase 5c's
//  fetchOrCreateShare) when CloudKit sync is on, and always shows a self row
//  (myRow, badged rather than labeled "You" — see youBadge) as a fallback
//  first row so viewing a club never depends on CloudKit — see the
//  local-first invariant in ROADMAP.md. Since invite-sending UI (5e) doesn't
//  exist yet, a club's only real participant today is its owner, so the
//  fetched list filters out the `.owner` role to avoid double-listing myRow.
//  Deleting/leaving a club never deletes match/player data — it only clears
//  clubId back to personal (nil) on every roster player and match record
//  tagged with it, then removes the club via the same AppStore.saveClubs
//  diffing that already routes owned vs. shared deletion correctly (Phase 5c).
//

import SwiftUI
import CloudKit
import BadmintonCore

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

struct ClubDetailView: View {
    let clubId: UUID

    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppStorageKeys.clubLastViewedActivity) private var lastViewedData = Data()
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName

    @State private var name = ""
    @State private var participants: [ClubParticipant] = []
    @State private var myParticipantId: String?
    @State private var myDisplayName: String?
    @State private var loadingParticipants = true
    @State private var showRemoveConfirm = false
    @State private var editingPlayer: Player?
    @State private var promptingForName = false
    @State private var pendingName = ""

    private var club: Club? { appStore.clubs.first { $0.id == clubId } }
    private var isOwned: Bool { club?.ownerRecordName == nil }

    private var clubRoster: [Player] {
        appStore.roster.filter { $0.clubId == clubId }
    }

    private var requireMatchConfirmation: Bool { club?.requireMatchConfirmation ?? false }

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
        requireMatchConfirmation ? clubMatches.filter { !$0.isConfirmed } : []
    }

    private var standings: [StatsCalculator.StandingsEntry] {
        StatsCalculator.standings(history: clubMatches.filter { $0.isConfirmed || !requireMatchConfirmation })
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
                    }
                }

                if !pendingMatches.isEmpty {
                    Section(header: Text("clubs.pending_confirmation")) {
                        ForEach(pendingMatches) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(record.myName) vs \(record.opponentName)")
                                    .font(.caption)
                                Text("\(record.myGamesWon)-\(record.opponentGamesWon)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                HStack {
                                    Button("clubs.confirm_match") { confirmMatch(record) }
                                        .font(.caption2)
                                    Button("clubs.decline_match", role: .destructive) { declineMatch(record) }
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
                        }
                    }
                }

                Section(header: Text("clubs.standings")) {
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
                        editingPlayer = Player(name: "", colorIndex: appStore.roster.count % Player.avatarColors.count, clubId: clubId)
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
        .sheet(item: $editingPlayer) { player in
            let others = appStore.roster.filter { $0.id != player.id }.map(\.name)
            PlayerEditView(initialPlayer: player, existingNames: others, clubs: appStore.clubs, onSave: savePlayer)
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
        CloudKitSyncManager.shared.enqueueSettingsChange()
        Task { @MainActor in
            try? await CloudKitSyncManager.shared.ensureMyProfileExists(displayName: Player.displayName(for: myName))
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
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    AvatarView(name: entry.myName, color: avatarColor(for: entry.myName), size: 18, iconName: avatarIcon(for: entry.myName))
                    Text(entry.myName)
                    if entry.myName == myName { youBadge }
                    Text("vs")
                    AvatarView(name: entry.opponentName, color: avatarColor(for: entry.opponentName), size: 18, iconName: avatarIcon(for: entry.opponentName))
                    Text(entry.opponentName)
                    if entry.opponentName == myName { youBadge }
                }
                .font(.caption)
                Text(entry.games.map { "\($0.my)-\($0.opponent)" }.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
                    Button("clubs.decline_challenge", role: .destructive) { respond(to: challenge, accept: false) }
                        .font(.caption2)
                }
            case .pending:
                HStack {
                    Text("clubs.challenge_pending")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Button("clubs.cancel_challenge", role: .destructive) { respond(to: challenge, accept: false) }
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
        CloudKitSyncManager.shared.enqueueSettingsChange()
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
        Task {
            do {
                let share = try await CloudKitSyncManager.shared.fetchOrCreateShare(for: club)
                let me = share.currentUserParticipant
                let myId = me?.userIdentity.userRecordID?.recordName
                let friendIds = Set(appStore.friends.map(\.participantId))
                // Exclude the owner (shown separately as myRow when I am the owner)
                // and, when I'm a non-owner member, exclude myself too — otherwise
                // I'd see my own name (and a "Challenge" button) in the list.
                let others = share.participants
                    .filter { $0.role != .owner }
                    .compactMap { participant -> ClubParticipant? in
                        guard let id = participant.userIdentity.userRecordID?.recordName, id != myId else { return nil }
                        return ClubParticipant(id: id, name: displayName(for: participant), isFriend: friendIds.contains(id))
                    }
                await MainActor.run {
                    participants = others
                    myParticipantId = me?.userIdentity.userRecordID?.recordName
                    myDisplayName = me.map { displayName(for: $0) }
                    loadingParticipants = false
                }
            } catch {
                await MainActor.run { loadingParticipants = false }
            }
        }
    }

    /// Same nameComponents/email resolution for any participant, self included
    /// (`CKShare.currentUserParticipant` is just another `CKShare.Participant`).
    private func displayName(for participant: CKShare.Participant) -> String {
        if let components = participant.userIdentity.nameComponents {
            return PersonNameComponentsFormatter().string(from: components)
        }
        return participant.userIdentity.lookupInfo?.emailAddress ?? NSLocalizedString("clubs.you", comment: "")
    }
}
