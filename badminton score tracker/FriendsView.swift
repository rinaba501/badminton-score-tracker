//
//  FriendsView.swift
//  badminton score tracker (iOS)
//
//  Roadmap Phase 7e: Friends UI — pending requests, friends list, and an
//  invite-generation ShareLink, over the CloudKit public-DB plumbing built in
//  7a-7d (CloudKitSyncManager's Friends section, AppStore.friendRequests/
//  friends). Unlike Phase 5e's club invite (UICloudSharingController,
//  UIKit-only, hence iOS-only), a friend invite is just a URL
//  (FriendInviteLink.url), so ShareLink works natively on watchOS too — this
//  view is symmetric with the Watch's FriendsView, styling aside, the same
//  way ClubsView is.
//

import SwiftUI
import BadmintonCore

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
    @AppStorage(AppStorageKeys.accountLinked) private var accountLinked = false

    @State private var myParticipantId: String?
    @State private var enteringCode = false
    @State private var codeInput = ""
    @State private var isSendingCode = false
    @State private var codeError: String?
    @State private var promptingForName = false
    @State private var pendingName = ""
    @State private var pendingAction: (() -> Void)?
    @State private var pendingRequestResponse: PendingFriendRequestResponse?
    @State private var showUnlinkConfirm = false

    // Backstop for anyone who skipped the first-launch prompt (ContentView) —
    // still lets Friends work, just nudges before anything gets sent.
    private var needsName: Bool {
        myName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || myName == Player.defaultMyName
    }

    // Same avatarColor(for:)/avatarIcon(for:) roster lookup ClubDetailView/
    // PreMatchView use — editing "Me" in RosterView saves a real Player row,
    // so the linked-account row shows your actual customized avatar instead
    // of a flat gray placeholder.
    private func avatarColor(for name: String) -> Color {
        store.roster.first(where: { $0.name == name })?.avatarColor ?? .gray
    }

    private func avatarIcon(for name: String) -> String? {
        store.roster.first(where: { $0.name == name })?.iconName
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
                "friends.unlink_account_confirm",
                isPresented: $showUnlinkConfirm,
                titleVisibility: .visible
            ) {
                Button("friends.unlink_account", role: .destructive) { unlinkAccount() }
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
            Section("friends.account_section_header") {
                if accountLinked {
                    HStack(spacing: 8) {
                        AvatarView(name: Player.displayName(for: myName), color: avatarColor(for: myName), size: 24, iconName: avatarIcon(for: myName))
                        Text(String(format: NSLocalizedString("friends.linked_as", comment: ""), Player.displayName(for: myName)))
                    }
                    Button("friends.unlink_account", role: .destructive) { showUnlinkConfirm = true }
                } else {
                    Button {
                        linkAccount()
                    } label: {
                        Label("friends.link_account", systemImage: "link")
                    }
                }
            }

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

            Section("friends.your_friends") {
                if store.friends.isEmpty {
                    Text("friends.no_friends_yet")
                        .foregroundStyle(.secondary)
                        .font(.callout)
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
        let manager = CloudKitSyncManager.shared
        if let id = try? await manager.resolveMyParticipantId() {
            myParticipantId = id
        }
        if needsName {
            pendingName = ""
            promptingForName = true
        } else {
            try? await manager.ensureMyProfileExists(displayName: Player.displayName(for: myName))
        }
        if let requests = try? await manager.fetchMyFriendRequests() {
            store.saveFriendRequests(requests)
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
            pendingAction?()
            pendingAction = nil
        }
    }

    // Explicit "link this device to one CloudKit account" opt-in flag —
    // purely informational today (Club's "you" row/badge no longer branches
    // on it, since there's only one identity to show), kept for future use.
    private func linkAccount() {
        guard !needsName else {
            pendingName = ""
            pendingAction = { [self] in
                accountLinked = true
                CloudKitSyncManager.shared.enqueueSettingsChange()
            }
            promptingForName = true
            return
        }
        accountLinked = true
        CloudKitSyncManager.shared.enqueueSettingsChange()
    }

    // Non-destructive: does not delete the FriendProfile, remove friends, or
    // leave clubs — just detaches the local link so Club stops showing the
    // shared name. Re-linking later restores it.
    private func unlinkAccount() {
        accountLinked = false
        CloudKitSyncManager.shared.enqueueSettingsChange()
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
            let manager = CloudKitSyncManager.shared
            guard let profile = await manager.fetchProfile(participantId: participantId) else {
                codeError = NSLocalizedString("friends.error_not_found", comment: "")
                isSendingCode = false
                return
            }
            do {
                try await manager.ensureMyProfileExists(displayName: Player.displayName(for: myName))
                try await manager.sendFriendRequest(toParticipantId: participantId, toDisplayName: profile.displayName)
                if let requests = try? await manager.fetchMyFriendRequests() {
                    store.saveFriendRequests(requests)
                }
                isSendingCode = false
                enteringCode = false
                codeInput = ""
            } catch CloudKitSyncManager.FriendRequestError.selfRequest {
                codeError = NSLocalizedString("friends.error_self", comment: "")
                isSendingCode = false
            } catch CloudKitSyncManager.FriendRequestError.alreadyPending {
                codeError = NSLocalizedString("friends.error_pending", comment: "")
                isSendingCode = false
            } catch {
                codeError = NSLocalizedString("friends.error_generic", comment: "")
                isSendingCode = false
            }
        }
    }

    private func respond(to request: FriendRequest, accept: Bool) {
        // @MainActor: the awaits on the (MainActor) sync manager would
        // otherwise resume on a background executor before mutating store.
        Task { @MainActor in
            let manager = CloudKitSyncManager.shared
            try? await manager.respondToFriendRequest(request, accept: accept)
            if let requests = try? await manager.fetchMyFriendRequests() {
                store.saveFriendRequests(requests)
            }
        }
    }
}
