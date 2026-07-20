//
//  FriendSharingSettingsView.swift
//  badminton score tracker (iOS)
//
//  Split out of FriendsView: the six per-field "share with friends" toggles
//  are a set-once-and-forget decision, not something scored day-to-day, so
//  they live on their own screen (pushed from a single row) instead of
//  crowding the top of the friends list. Watch counterpart is
//  FriendSharingSettingsView.swift on that target.
//

import SwiftUI
import BadmintonCore

struct FriendSharingSettingsView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppStorageKeys.supabaseAccountLinked) private var supabaseAccountLinked = false
    @AppStorage(AppStorageKeys.shareHistoryWithFriends) private var shareHistoryWithFriends = false
    @AppStorage(AppStorageKeys.shareAvatarWithFriends) private var shareAvatarWithFriends = false
    @AppStorage(AppStorageKeys.shareGenderWithFriends) private var shareGenderWithFriends = false
    @AppStorage(AppStorageKeys.shareBirthdayWithFriends) private var shareBirthdayWithFriends = false
    @AppStorage(AppStorageKeys.shareIntroductionWithFriends) private var shareIntroductionWithFriends = false
    @AppStorage(AppStorageKeys.shareStatsWithFriends) private var shareStatsWithFriends = false

    var body: some View {
        Form {
            Section(header: Text("friends.share_section_header"), footer: Text("friends.share_name_always_visible_footer")) {
                Toggle("friends.share_avatar_toggle", isOn: $shareAvatarWithFriends)
                    .onChange(of: shareAvatarWithFriends) { _, isOn in toggleIdentityField(isOn) }
                Toggle("friends.share_gender_toggle", isOn: $shareGenderWithFriends)
                    .onChange(of: shareGenderWithFriends) { _, isOn in toggleIdentityField(isOn) }
                Toggle("friends.share_birthday_toggle", isOn: $shareBirthdayWithFriends)
                    .onChange(of: shareBirthdayWithFriends) { _, isOn in toggleIdentityField(isOn) }
                Toggle("friends.share_introduction_toggle", isOn: $shareIntroductionWithFriends)
                    .onChange(of: shareIntroductionWithFriends) { _, isOn in toggleIdentityField(isOn) }
                Toggle("friends.share_stats_toggle", isOn: $shareStatsWithFriends)
                    .onChange(of: shareStatsWithFriends) { _, isOn in toggleStatsSharing(isOn) }
                Toggle("friends.share_history_toggle", isOn: $shareHistoryWithFriends)
                    .onChange(of: shareHistoryWithFriends) { _, isOn in
                        toggleShareHistoryWithFriends(isOn)
                    }
            }
        }
        .navigationTitle("friends.sharing_settings_title")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Actions

    // Turning on: create/reuse the "FriendsHistory" share and add every
    // current friend as a read-only participant. Turning off: strip all
    // participants only once every other per-field toggle is also off (see
    // AppStore.isSharingAnyProfileData) — the share/zone itself is always
    // left in place (see CloudKitSyncManager.revokeFriendsHistoryAccess).
    // Supabase-active: none of this has an equivalent (Roadmap 9e-3) — the
    // settings write above is already the complete access change, since
    // friend visibility there is RLS + this same toggle, not a per-
    // participant share list.
    private func toggleShareHistoryWithFriends(_ isOn: Bool) {
        AppStore.shared.enqueueSettingsChange()
        guard !supabaseAccountLinked else { return }
        Task { @MainActor in
            let manager = CloudKitSyncManager.shared
            if isOn {
                await manager.syncFriendsHistoryParticipants()
                let personalHistory = store.history.filter { $0.clubId == nil }.map(\.id)
                let personalRoster = store.roster.filter { $0.clubId == nil }.map(\.id)
                manager.enqueueFriendsHistoryChanges(upsertedIds: personalHistory, deletedIds: [])
                manager.enqueueFriendsRosterChanges(upsertedIds: personalRoster, deletedIds: [])
            } else if !store.isSharingAnyProfileData {
                await manager.revokeFriendsHistoryAccess()
            }
        }
    }

    // shareAvatar/Gender/Birthday/IntroductionWithFriends all gate fields on
    // the SAME single "FriendIdentity" record (see AppStore.
    // refreshMyIdentitySnapshotIfSharing), so every one of these four toggles
    // shares this one handler regardless of which direction it flipped.
    // refreshMyIdentitySnapshotIfSharing() itself is already backend-
    // polymorphic (routes through AppStore.syncEngine) — only the CKShare
    // participant-list calls below are CloudKit-specific.
    private func toggleIdentityField(_ isOn: Bool) {
        AppStore.shared.enqueueSettingsChange()
        Task { @MainActor in
            if isOn && !supabaseAccountLinked {
                await CloudKitSyncManager.shared.syncFriendsHistoryParticipants()
            }
            store.refreshMyIdentitySnapshotIfSharing()
            if !isOn && !supabaseAccountLinked && !store.isSharingAnyProfileData {
                await CloudKitSyncManager.shared.revokeFriendsHistoryAccess()
            }
        }
    }

    // Roadmap Phase 9e-2: enqueueFriendStatsChange()/removeFriendStatsRecord()
    // now route through AppStore.syncEngine (backend-polymorphic) instead of
    // calling CloudKitSyncManager.shared directly — the same View-bypass
    // pattern 9c-4 fixed for enqueueSettingsChange(), previously invisible
    // here because CloudKitSyncManager.shared happened to equal
    // AppStore.shared.syncEngine on every device until Supabase existed.
    private func toggleStatsSharing(_ isOn: Bool) {
        AppStore.shared.enqueueSettingsChange()
        Task { @MainActor in
            if isOn {
                if !supabaseAccountLinked {
                    await CloudKitSyncManager.shared.syncFriendsHistoryParticipants()
                }
                AppStore.shared.syncEngine.enqueueFriendStatsChange()
            } else {
                AppStore.shared.syncEngine.removeFriendStatsRecord()
                if !supabaseAccountLinked && !store.isSharingAnyProfileData {
                    await CloudKitSyncManager.shared.revokeFriendsHistoryAccess()
                }
            }
        }
    }
}
