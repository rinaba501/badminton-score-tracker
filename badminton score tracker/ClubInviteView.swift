//
//  ClubInviteView.swift
//  badminton score tracker (iOS)
//
//  Roadmap Phase 9d-2: the confirmation sheet shown when a
//  `badminton://joinclub` link is opened (parsed by ContentView's
//  onOpenURL via BadmintonCore.ClubInviteLink) — the Supabase-active
//  alternative to accepting a CloudKit CKShare invite. Nothing is redeemed
//  until the user explicitly confirms — opening a link must never write to
//  the database by itself, since the URL is untrusted input anyone can
//  compose. No Watch counterpart, same precedent as FriendInviteView (a
//  club invite *link* can be sent from either target via ShareLink, but is
//  only consumed on iOS).
//
//  On confirm, calls SupabaseSyncManager.redeemClubInvite(inviteId:), which
//  wraps the redeem_club_invite RPC (validates expiry/max_uses server-side,
//  inserts the caller into club_members) — then triggers a one-time
//  catch-up pull (SupabaseSyncEngine.shared.startIfActive()) so the
//  newly-joined club's data appears immediately instead of waiting for the
//  next launch or Realtime event.
//

import SwiftUI
import BadmintonCore
import CloudSyncSpike

struct ClubInviteView: View {
    let invite: ClubInviteLink.Invite
    let onClose: () -> Void

    private enum JoinState: Equatable {
        case idle, joining, joined, failed(String)
    }
    @State private var joinState: JoinState = .idle

    private var clubLabel: String {
        invite.clubName.isEmpty
            ? NSLocalizedString("clubs.invite_unknown_club", comment: "")
            : invite.clubName
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                Text(clubLabel)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)

                statusSection

                Spacer(minLength: 0)

                actionButton
            }
            .padding(24)
            .navigationTitle(Text("clubs.invite_join_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("history.cancel") { onClose() }
                }
            }
            .interactiveDismissDisabled(joinState == .joining)
        }
    }

    // MARK: - Pieces

    @ViewBuilder private var statusSection: some View {
        switch joinState {
        case .idle, .joining:
            Text(String(format: NSLocalizedString("clubs.invite_join_message", comment: ""), clubLabel))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        case .joined:
            Label("clubs.invite_joined", systemImage: "checkmark.circle.fill")
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
        if joinState == .joined {
            Button {
                onClose()
            } label: {
                Text("common.done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button {
                join()
            } label: {
                if joinState == .joining {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("clubs.invite_join")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(joinState == .joining)
        }
    }

    // MARK: - Joining

    private func join() {
        guard let inviteId = UUID(uuidString: invite.inviteId) else {
            joinState = .failed(NSLocalizedString("clubs.invite_join_failed", comment: ""))
            return
        }
        joinState = .joining
        // @MainActor: the awaits on the (MainActor) sync manager would
        // otherwise resume on a background executor before mutating @State.
        Task { @MainActor in
            guard await SupabaseSyncManager.shared.redeemClubInvite(inviteId: inviteId) != nil else {
                joinState = .failed(NSLocalizedString("clubs.invite_join_failed", comment: ""))
                return
            }
            SupabaseSyncEngine.shared.startIfActive()
            joinState = .joined
        }
    }
}
