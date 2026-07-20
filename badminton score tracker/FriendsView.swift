//
//  FriendsView.swift
//  badminton score tracker (iOS)
//
//  Roadmap Phase 7e: Friends UI — pending requests, friends list, and an
//  invite-generation ShareLink. Talks to Supabase (SupabaseSyncManager/
//  SupabaseSyncEngine, AppStore.friendRequests/friends) — the original
//  CloudKit-only plumbing this shipped over (7a-7d) was fully retired as of
//  Roadmap Phase 9f-2. Unlike Phase 5e's club invite (UICloudSharingController,
//  UIKit-only, hence iOS-only), a friend invite is just a URL
//  (FriendInviteLink.url), so ShareLink works natively on watchOS too — this
//  view is symmetric with the Watch's FriendsView, styling aside, the same
//  way ClubsView is. The account link/unlink toggle lived in ProfileView until
//  it, too, was removed as dead code in 9f-2 — this view is the friend graph
//  only.
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
    @EnvironmentObject private var store: AppStore
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

    private var incomingRequests: [FriendRequest] {
        guard let myParticipantId else { return [] }
        return store.friendRequests.filter { $0.status == .pending && $0.toParticipantId == myParticipantId }
    }

    private var outgoingRequests: [FriendRequest] {
        guard let myParticipantId else { return [] }
        return store.friendRequests.filter { $0.status == .pending && $0.fromParticipantId == myParticipantId }
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
                Section("friends.pending_received") {
                    ForEach(incomingRequests) { request in
                        incomingRequestRow(request)
                    }
                }
            }

            if !outgoingRequests.isEmpty {
                Section("friends.pending_sent") {
                    ForEach(outgoingRequests) { request in
                        HStack(spacing: 8) {
                            AvatarView(name: request.toDisplayName, color: .gray, size: 24)
                            Text(request.toDisplayName)
                        }
                        .swipeActions {
                            Button("friends.cancel_request", role: .destructive) {
                                pendingRequestResponse = PendingFriendRequestResponse(request: request, isCancel: true)
                            }
                        }
                    }
                }
            }

            Section {
                if store.friends.isEmpty {
                    ContentUnavailableView("friends.no_friends_yet", systemImage: "person.2.slash")
                } else {
                    ForEach(store.friends, id: \.participantId) { friend in
                        HStack(spacing: 8) {
                            AvatarView(name: friend.displayName, color: .gray, size: 24)
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
                        .frame(maxWidth: .infinity)
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
            Section("friends.more_section_header") {
                NavigationLink("friends.activity_title") {
                    FriendActivityView()
                }
                NavigationLink("friends.sharing_settings_title") {
                    FriendSharingSettingsView()
                }
            }
        }
        .refreshable { await refresh() }
    }

    private func incomingRequestRow(_ request: FriendRequest) -> some View {
        let name = request.fromDisplayName.isEmpty
            ? NSLocalizedString("friends.unknown_inviter", comment: "")
            : request.fromDisplayName
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AvatarView(name: name, color: .gray, size: 24)
                Text(name)
            }
            HStack {
                Button("friends.accept") { respond(to: request, accept: true) }
                Button("friends.decline", role: .destructive) {
                    pendingRequestResponse = PendingFriendRequestResponse(request: request, isCancel: false)
                }
            }
        }
    }

    private var codeEntryPrompt: some View {
        NavigationStack {
            Form {
                Section {
                    Text("friends.code_prompt_message")
                        .foregroundStyle(.secondary)
                    TextField("friends.code_placeholder", text: $codeInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let codeError {
                        Text(codeError)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle(Text("friends.enter_code"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("history.cancel") {
                        codeInput = ""
                        codeError = nil
                        enteringCode = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSendingCode {
                        ProgressView()
                    } else {
                        Button("friends.code_send") { sendCode() }
                            .disabled(codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
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
                    Button("history.cancel") {
                        pendingAction = nil
                        promptingForName = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("playeredit.save") { savePendingName() }
                        .disabled(pendingName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
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
        // otherwise resume on a background executor before mutating store.
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
