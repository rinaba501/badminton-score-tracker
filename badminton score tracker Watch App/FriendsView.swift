//
//  FriendsView.swift
//  badminton score tracker Watch App
//
//  Roadmap Phase 7e: Friends UI — pending requests, friends list, and an
//  invite-generation ShareLink. Talks to Supabase (SupabaseSyncManager/
//  SupabaseSyncEngine, AppStore.friendRequests/friends) — the original
//  CloudKit-only plumbing this shipped over (7a-7d) was fully retired as of
//  Roadmap Phase 9f-2. Unlike Phase 5e's club invite (UICloudSharingController,
//  UIKit-only, hence iOS-only), a friend invite is just a URL
//  (FriendInviteLink.url), so ShareLink works natively here too — no keyboard
//  needed, just the system share sheet. iOS restyle counterpart is
//  FriendsView.swift on that target.
//

import SwiftUI
import BadmintonCore
import CloudSyncSpike

/// Pending decline/cancel of a FriendRequest, awaiting confirmation —
/// `isCancel` distinguishes an outgoing-request cancel from an incoming
/// decline so the dialog message/button read right (`respond` itself is the
/// same call either way).
private struct PendingFriendRequestResponse: Identifiable {
    let request: FriendRequest
    let isCancel: Bool
    var id: UUID { request.id }
}

struct FriendsView: View {
    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName

    @State private var myParticipantId: String?
    @State private var enteringCode = false
    @State private var codeInput = ""
    @State private var isSendingCode = false
    @State private var codeError: String?
    @State private var promptingForName = false
    @State private var pendingName = ""
    @State private var pendingAction: (() -> Void)?
    @State private var pendingRequestResponse: PendingFriendRequestResponse?

    // Backstop for anyone who skipped the first-launch prompt (ContentView) —
    // still lets Friends work, just nudges before anything gets sent.
    private var needsName: Bool {
        myName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || myName == Player.defaultMyName
    }

    // Every friend now always mirrors their avatar (Roadmap issue #272 —
    // FriendIdentitySnapshot.colorIndex/iconName are unconditional), so a
    // friend/request/invite row can show their real avatar instead of a
    // flat gray placeholder once that snapshot has synced. Falls back to
    // gray/no-icon until then (e.g. a request that hasn't been accepted
    // yet, or the snapshot just hasn't pulled down).
    private func avatarColor(forParticipant participantId: String) -> Color {
        guard let colorIndex = appStore.friendIdentities[participantId]?.colorIndex else { return .gray }
        return Player.avatarColors[colorIndex % Player.avatarColors.count]
    }

    private func avatarIcon(forParticipant participantId: String) -> String? {
        appStore.friendIdentities[participantId]?.iconName
    }

    private var incomingRequests: [FriendRequest] {
        guard let myParticipantId else { return [] }
        return appStore.friendRequests.filter { $0.status == .pending && $0.toParticipantId == myParticipantId }
    }

    private var outgoingRequests: [FriendRequest] {
        guard let myParticipantId else { return [] }
        return appStore.friendRequests.filter { $0.status == .pending && $0.fromParticipantId == myParticipantId }
    }

    private var inviteURL: URL? {
        guard let myParticipantId else { return nil }
        return FriendInviteLink.url(participantId: myParticipantId, displayName: Player.displayName(for: myName))
    }

    var body: some View {
        friendsList
            .navigationTitle("settings.friends")
            .navigationBarTitleDisplayMode(.inline)
            .task { await refresh() }
            .sheet(isPresented: $enteringCode) {
                codeEntryPrompt
            }
            .sheet(isPresented: $promptingForName) {
                namePrompt
            }
            .confirmationDialog(
                pendingRequestResponse?.isCancel == true ? "friends.cancel_request_confirm" : "friends.decline_confirm",
                isPresented: Binding(
                    get: { pendingRequestResponse != nil },
                    set: { if !$0 { pendingRequestResponse = nil } }
                ),
                titleVisibility: .visible
            ) {
                if let pendingRequestResponse {
                    Button(pendingRequestResponse.isCancel ? "friends.cancel_request" : "friends.decline", role: .destructive) {
                        respond(to: pendingRequestResponse.request, accept: false)
                    }
                }
            }
    }

    // MARK: - Pieces

    private var friendsList: some View {
        List {
            if !incomingRequests.isEmpty {
                Section(header: Text("friends.pending_received")) {
                    ForEach(incomingRequests) { request in
                        incomingRequestRow(request)
                    }
                }
            }

            if !outgoingRequests.isEmpty {
                Section(header: Text("friends.pending_sent")) {
                    ForEach(outgoingRequests) { request in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                AvatarView(
                                    name: request.toDisplayName,
                                    color: avatarColor(forParticipant: request.toParticipantId),
                                    size: 24,
                                    iconName: avatarIcon(forParticipant: request.toParticipantId)
                                )
                                Text(request.toDisplayName)
                            }
                            Button("friends.cancel_request", role: .destructive) {
                                pendingRequestResponse = PendingFriendRequestResponse(request: request, isCancel: true)
                            }
                        }
                    }
                }
            }

            if !appStore.matchConflicts.isEmpty {
                Section(header: Text("friends.match_conflicts_section")) {
                    ForEach(appStore.matchConflicts) { invite in
                        matchConflictRow(invite)
                    }
                }
            }

            Section(header: Text("friends.your_friends")) {
                if appStore.friends.isEmpty {
                    Text("friends.no_friends_yet")
                        .foregroundColor(.secondary)
                        .font(.caption)
                } else {
                    ForEach(appStore.friends, id: \.participantId) { friend in
                        HStack(spacing: 8) {
                            AvatarView(
                                name: friend.displayName,
                                color: avatarColor(forParticipant: friend.participantId),
                                size: 24,
                                iconName: avatarIcon(forParticipant: friend.participantId)
                            )
                            Text(friend.displayName)
                        }
                    }
                }
            }

            Section {
                if let inviteURL {
                    ShareLink(item: inviteURL) {
                        Label("friends.add_friend", systemImage: "person.badge.plus")
                    }
                } else {
                    ProgressView()
                }
                Button {
                    enteringCode = true
                } label: {
                    Label("friends.enter_code", systemImage: "number")
                }
            }

            // Deliberately last: activity/sharing are set-once-and-forget,
            // not day-to-day actions, so they sit below the friends list
            // instead of competing with pending requests for top billing.
            Section(header: Text("friends.more_section_header")) {
                NavigationLink("friends.activity_title") {
                    FriendActivityView()
                }
                NavigationLink("friends.sharing_settings_title") {
                    FriendSharingSettingsView()
                }
            }
        }
    }

    private func incomingRequestRow(_ request: FriendRequest) -> some View {
        let name = request.fromDisplayName.isEmpty
            ? NSLocalizedString("friends.unknown_inviter", comment: "")
            : request.fromDisplayName
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AvatarView(
                    name: name,
                    color: avatarColor(forParticipant: request.fromParticipantId),
                    size: 24,
                    iconName: avatarIcon(forParticipant: request.fromParticipantId)
                )
                Text(name)
            }
            Button("friends.accept") { respond(to: request, accept: true) }
            Button("friends.decline", role: .destructive) {
                pendingRequestResponse = PendingFriendRequestResponse(request: request, isCancel: false)
            }
        }
    }

    /// Roadmap Phase 10c (#316): a conflict `StatsCalculator.conflictingRecord`
    /// flagged — the sender's own perspective (`invite.matchSnapshot.games`)
    /// and the recipient's own pre-existing record (`conflict.games`) are
    /// both already in each side's own natural "my"/"opponent" orientation,
    /// so no flip math is needed to display them, just a "You"/sender-name
    /// label per line (reusing the already-localized "clubs.you" string
    /// rather than adding a redundant one).
    private func matchConflictRow(_ invite: SharedMatchInvite) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AvatarView(
                    name: invite.fromDisplayName,
                    color: avatarColor(forParticipant: invite.fromParticipantId),
                    size: 24,
                    iconName: avatarIcon(forParticipant: invite.fromParticipantId)
                )
                Text(invite.fromDisplayName)
            }
            if let conflict = appStore.conflictingRecord(for: invite) {
                HStack(spacing: 4) {
                    Text("clubs.you").foregroundColor(.secondary)
                    Text(gameLine(conflict.games))
                }
                .font(.caption2)
                HStack(spacing: 4) {
                    Text(invite.fromDisplayName).foregroundColor(.secondary)
                    Text(gameLine(invite.matchSnapshot.games))
                }
                .font(.caption2)
            }
            Button("friends.match_conflict_accept") { appStore.acceptConflictingMatchInvite(invite) }
            Button("friends.match_conflict_ignore") { appStore.respondToMatchInvite(invite, accept: false) }
        }
    }

    /// Same "X-Y, X-Y" per-game formatting as HistoryView's gameLine.
    private func gameLine(_ games: [GameScore]) -> String {
        games.map { "\($0.my)-\($0.opponent)" }.joined(separator: ", ")
    }

    private var codeEntryPrompt: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("friends.code_prompt_message")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                TextField("friends.code_placeholder", text: $codeInput)
                if let codeError {
                    Text(codeError)
                        .font(.caption2)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                }
                if isSendingCode {
                    ProgressView()
                } else {
                    Button("friends.code_send") { sendCode() }
                        .disabled(codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Button("history.cancel") {
                    codeInput = ""
                    codeError = nil
                    enteringCode = false
                }
            }
            .padding()
            .navigationTitle(Text("friends.enter_code"))
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
                Button("history.cancel") {
                    pendingAction = nil
                    promptingForName = false
                }
            }
            .padding()
            .navigationTitle(Text("friends.display_name_prompt_title"))
        }
    }

    // MARK: - Actions

    private func refresh() async {
        if let uid = await SupabaseSyncManager.shared.currentUserId() {
            myParticipantId = uid.uuidString
        }
        if needsName {
            pendingName = ""
            promptingForName = true
        } else {
            await SupabaseSyncManager.shared.upsertMyProfile(displayName: Player.displayName(for: myName))
        }
        await SupabaseSyncEngine.shared.refreshFriendRequests()
    }

    private func savePendingName() {
        let trimmed = pendingName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        myName = trimmed
        promptingForName = false
        AppStore.shared.enqueueSettingsChange()
        Task { @MainActor in
            await SupabaseSyncManager.shared.upsertMyProfile(displayName: Player.displayName(for: myName))
            pendingAction?()
            pendingAction = nil
        }
    }

    private func sendCode() {
        guard !needsName else {
            pendingName = ""
            pendingAction = { [self] in sendCode() }
            promptingForName = true
            return
        }
        let trimmed = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let participantId: String
        if let url = URL(string: trimmed), let invite = FriendInviteLink.parse(url) {
            participantId = invite.participantId
        } else {
            participantId = trimmed
        }
        isSendingCode = true
        codeError = nil
        // @MainActor: the awaits on the (MainActor) sync manager would
        // otherwise resume on a background executor before mutating @State.
        Task { @MainActor in
            await sendCodeViaSupabase(participantId: participantId)
        }
    }

    /// `participantId` must be a real `auth.uid()` string here (an invite
    /// link/code sent from another device always encodes one) — a
    /// malformed/unparseable code fails the UUID parse and reports the same
    /// "not found" error a truly unknown id would.
    private func sendCodeViaSupabase(participantId: String) async {
        guard let toId = UUID(uuidString: participantId),
              let toDisplayName = await SupabaseSyncManager.shared.fetchProfileDisplayName(participantId: toId) else {
            codeError = NSLocalizedString("friends.error_not_found", comment: "")
            isSendingCode = false
            return
        }
        guard let myId = await SupabaseSyncManager.shared.currentUserId() else {
            codeError = NSLocalizedString("friends.error_generic", comment: "")
            isSendingCode = false
            return
        }
        let request = FriendRequest(
            fromParticipantId: myId.uuidString, fromDisplayName: Player.displayName(for: myName),
            toParticipantId: toId.uuidString, toDisplayName: toDisplayName
        )
        guard let payload = PersistenceStore.encodeFriendRequest(request) else {
            codeError = NSLocalizedString("friends.error_generic", comment: "")
            isSendingCode = false
            return
        }
        do {
            try await SupabaseSyncManager.shared.sendFriendRequest(
                id: request.id, fromParticipantId: myId, toParticipantId: toId, payload: payload
            )
            await SupabaseSyncEngine.shared.refreshFriendRequests()
            isSendingCode = false
            enteringCode = false
            codeInput = ""
        } catch SupabaseSyncManager.FriendRequestError.selfRequest {
            codeError = NSLocalizedString("friends.error_self", comment: "")
            isSendingCode = false
        } catch SupabaseSyncManager.FriendRequestError.alreadyPending {
            codeError = NSLocalizedString("friends.error_pending", comment: "")
            isSendingCode = false
        } catch {
            codeError = NSLocalizedString("friends.error_generic", comment: "")
            isSendingCode = false
        }
    }

    private func respond(to request: FriendRequest, accept: Bool) {
        // @MainActor: the awaits on the (MainActor) sync manager would
        // otherwise resume on a background executor before mutating appStore.
        Task { @MainActor in
            var updated = request
            updated.status = accept ? .accepted : .declined
            guard let payload = PersistenceStore.encodeFriendRequest(updated) else { return }
            await SupabaseSyncManager.shared.respondToFriendRequest(id: request.id, status: updated.status.rawValue, payload: payload)
            await SupabaseSyncEngine.shared.refreshFriendRequests()
            // No FriendsHistory-participant-list equivalent needed here —
            // friend history/identity/stats visibility under Supabase is
            // RLS + settings-toggle gated, not a per-participant share
            // list (see Roadmap 9e-2/9e-3), so accepting/declining alone
            // is already the complete access change.
        }
    }
}
