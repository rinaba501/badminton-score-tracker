//
//  FriendSharingSettingsView.swift
//  badminton score tracker Watch App
//
//  Split out of FriendsView: the six per-field "share with friends" toggles
//  are a set-once-and-forget decision, not something scored day-to-day, so
//  they live on their own screen (pushed from a single row) instead of
//  crowding the top of the friends list. iOS restyle counterpart is
//  FriendSharingSettingsView.swift on that target.
//

import SwiftUI
import BadmintonCore

struct FriendSharingSettingsView: View {
    @EnvironmentObject private var appStore: AppStore
    @AppStorage(AppStorageKeys.shareHistoryWithFriends) private var shareHistoryWithFriends = false
    @AppStorage(AppStorageKeys.shareAvatarWithFriends) private var shareAvatarWithFriends = false
    @AppStorage(AppStorageKeys.shareGenderWithFriends) private var shareGenderWithFriends = false
    @AppStorage(AppStorageKeys.shareBirthdayWithFriends) private var shareBirthdayWithFriends = false
    @AppStorage(AppStorageKeys.shareIntroductionWithFriends) private var shareIntroductionWithFriends = false
    @AppStorage(AppStorageKeys.shareStatsWithFriends) private var shareStatsWithFriends = false

    var body: some View {
        List {
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
    private func toggleShareHistoryWithFriends(_ isOn: Bool) {
        CloudKitSyncManager.shared.enqueueSettingsChange()
        Task { @MainActor in
            let manager = CloudKitSyncManager.shared
            if isOn {
                await manager.syncFriendsHistoryParticipants()
                let personalHistory = appStore.history.filter { $0.clubId == nil }.map(\.id)
                let personalRoster = appStore.roster.filter { $0.clubId == nil }.map(\.id)
                manager.enqueueFriendsHistoryChanges(upsertedIds: personalHistory, deletedIds: [])
                manager.enqueueFriendsRosterChanges(upsertedIds: personalRoster, deletedIds: [])
            } else if !appStore.isSharingAnyProfileData {
                await manager.revokeFriendsHistoryAccess()
            }
        }
    }

    // shareAvatar/Gender/Birthday/IntroductionWithFriends all gate fields on
    // the SAME single "FriendIdentity" record (see AppStore.
    // refreshMyIdentitySnapshotIfSharing), so every one of these four toggles
    // shares this one handler regardless of which direction it flipped.
    private func toggleIdentityField(_ isOn: Bool) {
        CloudKitSyncManager.shared.enqueueSettingsChange()
        Task { @MainActor in
            let manager = CloudKitSyncManager.shared
            if isOn {
                await manager.syncFriendsHistoryParticipants()
            }
            appStore.refreshMyIdentitySnapshotIfSharing()
            if !isOn && !appStore.isSharingAnyProfileData {
                await manager.revokeFriendsHistoryAccess()
            }
        }
    }

    private func toggleStatsSharing(_ isOn: Bool) {
        CloudKitSyncManager.shared.enqueueSettingsChange()
        Task { @MainActor in
            let manager = CloudKitSyncManager.shared
            if isOn {
                await manager.syncFriendsHistoryParticipants()
                manager.enqueueFriendStatsChange()
            } else {
                manager.removeFriendStatsRecord()
                if !appStore.isSharingAnyProfileData {
                    await manager.revokeFriendsHistoryAccess()
                }
            }
        }
    }
}
