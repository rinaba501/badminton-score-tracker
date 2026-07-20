//
//  FriendInviteView.swift
//  badminton score tracker (iOS)
//
//  Friends v1 (invite-link slice, Roadmap 7d): the confirmation sheet shown
//  when a `badminton://addfriend` link is opened (parsed by ContentView's
//  onOpenURL via BadmintonCore.FriendInviteLink). Nothing is sent until the
//  user explicitly confirms — opening a link must never write to the backend
//  by itself, since the URL is untrusted input anyone can compose.
//
//  On confirm it upserts my public profile first (using the roster "Me"
//  name, myName — there's no separate Friends display name to seed), sends
//  the request via Supabase, then reconciles AppStore.friendRequests
//  (SupabaseSyncEngine.refreshFriendRequests). Roadmap Phase 9f-2: the
//  original CloudKit-branch this shipped with (7d) was removed — Friends is
//  Supabase-only now.
//

import SwiftUI
import BadmintonCore
import CloudSyncSpike

struct FriendInviteView: View {
    let invite: FriendInviteLink.Invite
    let onClose: () -> Void

    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName

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
            Text(String(format: NSLocalizedString("friends.invite_message", comment: ""), inviterLabel))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
        } else {
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
        // Rendered through displayName(for:) so the roster "Me" sentinel
        // never leaks to another player.
        let displayName = Player.displayName(for: myName)
        // @MainActor: the awaits on the (MainActor) sync manager would
        // otherwise resume on a background executor before mutating @State.
        Task { @MainActor in
            await sendViaSupabase(displayName: displayName)
        }
    }

    /// `invite.participantId` must be a real `auth.uid()` string here — an
    /// invite link sent from another device always encodes one, so no
    /// separate `profiles` lookup is needed; `invite.displayName` (the
    /// link's own embedded UGC name) is trusted as-is too, not re-resolved
    /// against `profiles`.
    private func sendViaSupabase(displayName: String) async {
        guard let toId = UUID(uuidString: invite.participantId) else {
            sendState = .failed(NSLocalizedString("friends.error_generic", comment: ""))
            return
        }
        guard let myId = await SupabaseSyncManager.shared.currentUserId() else {
            sendState = .failed(NSLocalizedString("friends.error_generic", comment: ""))
            return
        }
        await SupabaseSyncManager.shared.upsertMyProfile(displayName: displayName)
        let request = FriendRequest(
            fromParticipantId: myId.uuidString, fromDisplayName: displayName,
            toParticipantId: toId.uuidString, toDisplayName: invite.displayName
        )
        guard let payload = PersistenceStore.encodeFriendRequest(request) else {
            sendState = .failed(NSLocalizedString("friends.error_generic", comment: ""))
            return
        }
        do {
            try await SupabaseSyncManager.shared.sendFriendRequest(
                id: request.id, fromParticipantId: myId, toParticipantId: toId, payload: payload
            )
            await SupabaseSyncEngine.shared.refreshFriendRequests()
            sendState = .sent
        } catch SupabaseSyncManager.FriendRequestError.selfRequest {
            sendState = .failed(NSLocalizedString("friends.error_self", comment: ""))
        } catch SupabaseSyncManager.FriendRequestError.alreadyPending {
            sendState = .failed(NSLocalizedString("friends.error_pending", comment: ""))
        } catch {
            sendState = .failed(NSLocalizedString("friends.error_generic", comment: ""))
        }
    }
}
