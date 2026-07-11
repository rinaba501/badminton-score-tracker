//
//  FriendsView.swift
//  badminton score tracker Watch App
//
//  Roadmap Phase 7e: Friends UI — pending requests, friends list, and an
//  invite-generation ShareLink, over the CloudKit public-DB plumbing built in
//  7a-7d (CloudKitSyncManager's Friends section, AppStore.friendRequests/
//  friends). Unlike Phase 5e's club invite (UICloudSharingController,
//  UIKit-only, hence iOS-only), a friend invite is just a URL
//  (FriendInviteLink.url), so ShareLink works natively here too — no keyboard
//  needed, just the system share sheet. iOS restyle counterpart is
//  FriendsView.swift on that target.
//

import SwiftUI
import BadmintonCore

struct FriendsView: View {
    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.myFriendsDisplayName) private var myFriendsDisplayName = ""
    @AppStorage(AppStorageKeys.accountLinked) private var accountLinked = false

    @State private var myParticipantId: String?
    @State private var promptingForDisplayName = false
    @State private var linkingAccount = false
    @State private var pendingDisplayName = ""
    @State private var enteringCode = false
    @State private var codeInput = ""
    @State private var isSendingCode = false
    @State private var codeError: String?

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
        return FriendInviteLink.url(participantId: myParticipantId, displayName: myFriendsDisplayName)
    }

    var body: some View {
        friendsList
            .navigationTitle("settings.friends")
            .navigationBarTitleDisplayMode(.inline)
            .task { await refresh() }
            .sheet(isPresented: $promptingForDisplayName) {
                displayNamePrompt
            }
            .sheet(isPresented: $enteringCode) {
                codeEntryPrompt
            }
    }

    // MARK: - Pieces

    private var friendsList: some View {
        List {
            Section(header: Text("friends.account_section_header")) {
                if accountLinked {
                    Text(String(format: NSLocalizedString("friends.linked_as", comment: ""), myFriendsDisplayName))
                    Button("friends.unlink_account", role: .destructive) { unlinkAccount() }
                } else {
                    Button {
                        linkAccount()
                    } label: {
                        Label("friends.link_account", systemImage: "link")
                    }
                }
            }

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
                            Text(request.toDisplayName)
                            Button("friends.cancel_request", role: .destructive) {
                                respond(to: request, accept: false)
                            }
                        }
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
                        Text(friend.displayName)
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
        }
    }

    private func incomingRequestRow(_ request: FriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(request.fromDisplayName.isEmpty
                 ? NSLocalizedString("friends.unknown_inviter", comment: "")
                 : request.fromDisplayName)
            Button("friends.accept") { respond(to: request, accept: true) }
            Button("friends.decline", role: .destructive) { respond(to: request, accept: false) }
        }
    }

    private var displayNamePrompt: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Text("friends.display_name_prompt_message")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                TextField("friends.display_name_placeholder", text: $pendingDisplayName)
                Button("playeredit.save") { saveDisplayName() }
                    .disabled(pendingDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("history.cancel") { promptingForDisplayName = false }
            }
            .padding()
            .navigationTitle(Text("friends.display_name_prompt_title"))
        }
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

    // MARK: - Actions

    private func refresh() async {
        let manager = CloudKitSyncManager.shared
        if let id = try? await manager.resolveMyParticipantId() {
            myParticipantId = id
        }
        if myFriendsDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingDisplayName = Player.displayName(for: myName)
            promptingForDisplayName = true
        }
        if let requests = try? await manager.fetchMyFriendRequests() {
            appStore.saveFriendRequests(requests)
        }
    }

    private func saveDisplayName() {
        let trimmed = pendingDisplayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        myFriendsDisplayName = trimmed
        promptingForDisplayName = false
        if linkingAccount {
            accountLinked = true
            linkingAccount = false
        }
        CloudKitSyncManager.shared.enqueueSettingsChange()
        Task { @MainActor in
            try? await CloudKitSyncManager.shared.ensureMyProfileExists(displayName: trimmed)
        }
    }

    // Explicit "link this device to one CloudKit account" action — separate
    // from the auto-prompt in refresh(), which only seeds a Friends display
    // name. Linking additionally flips accountLinked, which Club reads to
    // show the same name on the "You" row (see ClubDetailView).
    private func linkAccount() {
        if myFriendsDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingDisplayName = Player.displayName(for: myName)
            linkingAccount = true
            promptingForDisplayName = true
        } else {
            accountLinked = true
            CloudKitSyncManager.shared.enqueueSettingsChange()
        }
    }

    // Non-destructive: does not delete the FriendProfile, remove friends, or
    // leave clubs — just detaches the local link so Club stops showing the
    // shared name. Re-linking later restores it.
    private func unlinkAccount() {
        accountLinked = false
        CloudKitSyncManager.shared.enqueueSettingsChange()
    }

    private func sendCode() {
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
            // Same backstop as FriendInviteView.send(): never send anonymously.
            if myFriendsDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                myFriendsDisplayName = Player.displayName(for: myName)
                manager.enqueueSettingsChange()
            }
            do {
                try await manager.ensureMyProfileExists(displayName: myFriendsDisplayName)
                try await manager.sendFriendRequest(toParticipantId: participantId, toDisplayName: profile.displayName)
                if let requests = try? await manager.fetchMyFriendRequests() {
                    appStore.saveFriendRequests(requests)
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
        // otherwise resume on a background executor before mutating appStore.
        Task { @MainActor in
            let manager = CloudKitSyncManager.shared
            try? await manager.respondToFriendRequest(request, accept: accept)
            if let requests = try? await manager.fetchMyFriendRequests() {
                appStore.saveFriendRequests(requests)
            }
        }
    }
}
