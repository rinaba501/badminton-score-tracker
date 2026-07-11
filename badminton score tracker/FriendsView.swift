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

struct FriendsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.myFriendsDisplayName) private var myFriendsDisplayName = ""

    @State private var myParticipantId: String?
    @State private var promptingForDisplayName = false
    @State private var pendingDisplayName = ""
    @State private var enteringCode = false
    @State private var codeInput = ""
    @State private var isSendingCode = false
    @State private var codeError: String?

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
        return FriendInviteLink.url(participantId: myParticipantId, displayName: myFriendsDisplayName)
    }

    var body: some View {
        Group {
            if CloudKitSyncManager.isEnabled {
                friendsList
            } else {
                requiresSyncMessage
            }
        }
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

    private var requiresSyncMessage: some View {
        Text("friends.invite_requires_sync")
            .font(.body)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding()
    }

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
                        Text(request.toDisplayName)
                            .swipeActions {
                                Button("friends.cancel_request", role: .destructive) {
                                    respond(to: request, accept: false)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(request.fromDisplayName.isEmpty
                 ? NSLocalizedString("friends.unknown_inviter", comment: "")
                 : request.fromDisplayName)
            HStack {
                Button("friends.accept") { respond(to: request, accept: true) }
                Button("friends.decline", role: .destructive) { respond(to: request, accept: false) }
            }
        }
    }

    private var displayNamePrompt: some View {
        NavigationStack {
            Form {
                Section {
                    Text("friends.display_name_prompt_message")
                        .foregroundStyle(.secondary)
                    TextField("friends.display_name_placeholder", text: $pendingDisplayName)
                }
            }
            .navigationTitle(Text("friends.display_name_prompt_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("history.cancel") { promptingForDisplayName = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("playeredit.save") { saveDisplayName() }
                        .disabled(pendingDisplayName.trimmingCharacters(in: .whitespaces).isEmpty)
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

    // MARK: - Actions

    private func refresh() async {
        guard CloudKitSyncManager.isEnabled else { return }
        let manager = CloudKitSyncManager.shared
        if let id = try? await manager.resolveMyParticipantId() {
            myParticipantId = id
        }
        if myFriendsDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pendingDisplayName = Player.displayName(for: myName)
            promptingForDisplayName = true
        }
        if let requests = try? await manager.fetchMyFriendRequests() {
            store.saveFriendRequests(requests)
        }
    }

    private func saveDisplayName() {
        let trimmed = pendingDisplayName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        myFriendsDisplayName = trimmed
        promptingForDisplayName = false
        Task { @MainActor in
            try? await CloudKitSyncManager.shared.ensureMyProfileExists(displayName: trimmed)
        }
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
            }
            do {
                try await manager.ensureMyProfileExists(displayName: myFriendsDisplayName)
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
