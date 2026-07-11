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

    @State private var myParticipantId: String?
    @State private var promptingForDisplayName = false
    @State private var pendingDisplayName = ""

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
    }

    // MARK: - Pieces

    private var requiresSyncMessage: some View {
        Text("friends.invite_requires_sync")
            .font(.caption)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
    }

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
            appStore.saveFriendRequests(requests)
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
