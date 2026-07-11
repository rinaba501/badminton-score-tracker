//
//  FriendInviteView.swift
//  badminton score tracker (iOS)
//
//  Friends v1 (invite-link slice, Roadmap 7d): the confirmation sheet shown
//  when a `badminton://addfriend` link is opened (parsed by ContentView's
//  onOpenURL via BadmintonCore.FriendInviteLink). Nothing is sent until the
//  user explicitly confirms — opening a link must never write to CloudKit by
//  itself, since the URL is untrusted input anyone can compose.
//
//  Sending requires `cloudKitSyncEnabled` (same gate as ClubDetailView's
//  invite button, Phase 5e): CloudKitSyncManager.shared is never touched
//  while the flag is off, so the inert-without-entitlement guarantee holds.
//  On confirm it upserts my public FriendProfile first (using the roster
//  "Me" name as a fallback if `myFriendsDisplayName` was never set — a user
//  can reach this sheet via a deep link before ever visiting FriendsView's
//  7e display-name prompt, so the fallback stays as a backstop), sends the
//  request, then reconciles AppStore.friendRequests with a fresh public-DB
//  fetch (the saveFriendRequests convention — no CKSyncEngine involved).
//

import SwiftUI
import BadmintonCore

struct FriendInviteView: View {
    let invite: FriendInviteLink.Invite
    let onClose: () -> Void

    @EnvironmentObject private var store: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.myFriendsDisplayName) private var myFriendsDisplayName = ""

    private enum SendState: Equatable {
        case idle, sending, sent, failed(String)
    }
    @State private var sendState: SendState = .idle

    private var inviterLabel: String {
        invite.displayName.isEmpty
            ? NSLocalizedString("friends.unknown_inviter", comment: "")
            : invite.displayName
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text(inviterLabel)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                statusSection

                Spacer(minLength: 0)

                actionButton
            }
            .padding(24)
            .navigationTitle(Text("friends.invite_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("history.cancel") { onClose() }
                }
            }
            .interactiveDismissDisabled(sendState == .sending)
        }
    }

    // MARK: - Pieces

    @ViewBuilder private var statusSection: some View {
        switch sendState {
        case .idle, .sending:
            if CloudKitSyncManager.isEnabled {
                Text(String(format: NSLocalizedString("friends.invite_message", comment: ""), inviterLabel))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("friends.invite_requires_sync")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        case .sent:
            Label("friends.invite_sent", systemImage: "checkmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message)
                .font(.body)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder private var actionButton: some View {
        if sendState == .sent {
            Button {
                onClose()
            } label: {
                Text("common.done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else if CloudKitSyncManager.isEnabled {
            Button {
                send()
            } label: {
                if sendState == .sending {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("friends.invite_send")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(sendState == .sending)
        }
    }

    // MARK: - Sending

    private func send() {
        sendState = .sending
        // Backstop for a deep link opened before FriendsView's display-name
        // prompt ever ran: never send an anonymous request. The roster "Me"
        // name stands in (rendered through displayName(for:) so the sentinel
        // never leaks).
        if myFriendsDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            myFriendsDisplayName = Player.displayName(for: myName)
        }
        let displayName = myFriendsDisplayName
        // @MainActor: the awaits on the (MainActor) sync manager would
        // otherwise resume on a background executor before mutating @State.
        Task { @MainActor in
            do {
                let manager = CloudKitSyncManager.shared
                try await manager.ensureMyProfileExists(displayName: displayName)
                try await manager.sendFriendRequest(
                    toParticipantId: invite.participantId,
                    toDisplayName: invite.displayName
                )
                let requests = try await manager.fetchMyFriendRequests()
                store.saveFriendRequests(requests)
                sendState = .sent
            } catch CloudKitSyncManager.FriendRequestError.selfRequest {
                sendState = .failed(NSLocalizedString("friends.error_self", comment: ""))
            } catch CloudKitSyncManager.FriendRequestError.alreadyPending {
                sendState = .failed(NSLocalizedString("friends.error_pending", comment: ""))
            } catch {
                sendState = .failed(NSLocalizedString("friends.error_generic", comment: ""))
            }
        }
    }
}
