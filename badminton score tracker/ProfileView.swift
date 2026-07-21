//
//  ProfileView.swift
//  badminton score tracker (iOS)
//
//  Dedicated "who am I" page, split out from the shared roster (RosterView,
//  which now only manages other players) and from Friends (FriendsView,
//  which now only manages the friend graph). Owns name/avatar editing for
//  "Me". iOS-only: on watchOS "Me" stays a distinguished row inside
//  Settings/Roster, since the small screen doesn't warrant another
//  top-level nav destination. Roadmap Phase 9f-2: the CloudKit account-link
//  toggle (a metadata-only "link this device" flag with no behavioral effect
//  even before Supabase existed) was removed as dead code.
//
//  Each identity field (gender/birthday/bio) carries its own inline "share
//  with friends" toggle right next to where it's edited, so the sharing
//  decision happens at the moment the data is entered rather than requiring
//  a trip to FriendsView's Sharing Settings screen — that screen remains the
//  one place all five toggles (these three plus stats/history) are visible
//  together. Avatar has no toggle (Roadmap issue #272) — it always mirrors,
//  same as the name. toggleIdentityField here is a deliberate duplicate of
//  FriendSharingSettingsView's — keep the two in sync.
//

import SwiftUI
import BadmintonCore
import CloudSyncSpike

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore
    @AppStorage(AppStorageKeys.myName) private var myName = Player.defaultMyName
    @AppStorage(AppStorageKeys.shareGenderWithFriends) private var shareGenderWithFriends = false
    @AppStorage(AppStorageKeys.shareBirthdayWithFriends) private var shareBirthdayWithFriends = false
    @AppStorage(AppStorageKeys.shareIntroductionWithFriends) private var shareIntroductionWithFriends = false

    @State private var editingPlayer: Player?
    @State private var toastMessage: String?

    // Gender/birthday/introduction aren't @AppStorage-native types (String?/
    // Date?), so they're loaded once on appear and written straight to
    // UserDefaults on save — editing here is separate from *sharing*: filling
    // these in doesn't share them, the per-field toggles in FriendsView do
    // (see FriendIdentitySnapshot.swift).
    @State private var gender: String?
    @State private var hasBirthday = false
    @State private var birthday = Date()
    @State private var introduction = ""
    private static let introductionCharacterLimit = 200

    private var roster: [Player] { store.roster }

    private func meAsPlayer() -> Player {
        roster.first(where: { $0.name == myName }) ?? Player(id: store.localPlayerId, name: myName, colorIndex: 0)
    }

    var body: some View {
        List {
            Section {
                Button {
                    editingPlayer = meAsPlayer()
                } label: {
                    let me = meAsPlayer()
                    HStack(spacing: 10) {
                        AvatarView(name: myName, color: me.avatarColor, size: 44, iconName: me.iconName)
                        Text(myName).foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section(footer: Text("profile.share_toggle_footer")) {
                HStack {
                    Picker("profile.gender_label", selection: $gender) {
                        Text("profile.gender_prefer_not_to_say").tag(String?.none)
                        Text("profile.gender_male").tag(String?.some("male"))
                        Text("profile.gender_female").tag(String?.some("female"))
                        Text("profile.gender_nonbinary").tag(String?.some("nonbinary"))
                    }
                    .onChange(of: gender) { _, newValue in writeGender(newValue) }

                    shareToggle(
                        "friends.share_gender_toggle",
                        isOn: $shareGenderWithFriends,
                        onChange: toggleIdentityField
                    )
                }

                Toggle("profile.birthday_label", isOn: $hasBirthday)
                    .onChange(of: hasBirthday) { _, isOn in
                        if isOn {
                            writeBirthday(birthday)
                        } else {
                            writeBirthday(nil)
                        }
                    }
                if hasBirthday {
                    HStack {
                        DatePicker("profile.birthday_label", selection: $birthday, displayedComponents: .date)
                            .labelsHidden()
                            .onChange(of: birthday) { _, newValue in writeBirthday(newValue) }

                        Spacer()

                        shareToggle(
                            "friends.share_birthday_toggle",
                            isOn: $shareBirthdayWithFriends,
                            onChange: toggleIdentityField
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("profile.introduction_label").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        shareToggle(
                            "friends.share_introduction_toggle",
                            isOn: $shareIntroductionWithFriends,
                            onChange: toggleIdentityField
                        )
                    }
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $introduction)
                            .frame(minHeight: 80)
                            .onChange(of: introduction) { _, newValue in
                                introduction = String(newValue.prefix(Self.introductionCharacterLimit))
                                writeIntroduction(introduction)
                            }
                        if introduction.isEmpty {
                            Text("profile.introduction_placeholder")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding(6)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let toastMessage {
                Text(toastMessage)
                    .font(.footnote)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: toastMessage)
        .navigationTitle("ios.profile")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingPlayer) { player in
            PlayerEditView(
                initialPlayer: player,
                existingNames: roster.filter { $0.name != myName }.map(\.name),
                clubs: store.clubs,
                onSave: saveMe
            )
        }
        .onAppear { loadIdentityFields() }
    }

    // MARK: - Pieces

    // Icon-only button-styled Toggle (native on/off accessibility + visual
    // state come from `.toggleStyle(.button)`) — the localized `titleKey`
    // doubles as its accessibility label since `.labelStyle(.iconOnly)`
    // hides the text visually but keeps it for VoiceOver.
    private func shareToggle(
        _ titleKey: LocalizedStringKey,
        isOn: Binding<Bool>,
        onChange: @escaping (Bool) -> Void
    ) -> some View {
        Toggle(isOn: isOn) {
            Label(titleKey, systemImage: isOn.wrappedValue ? "person.2.fill" : "person.2")
        }
        .toggleStyle(.button)
        .labelStyle(.iconOnly)
        .onChange(of: isOn.wrappedValue) { _, newValue in
            onChange(newValue)
            showToast(newValue ? "profile.share_toast_on" : "profile.share_toast_off")
        }
    }

    // Icon-only toggles have no room for a text label, so a toast teaches
    // what just happened at the moment it happens instead of relying on the
    // section footer alone. Re-tapping restarts the timer via the message
    // identity check, so a rapid on/off/on doesn't dismiss early.
    private func showToast(_ messageKey: String) {
        let message = NSLocalizedString(messageKey, comment: "")
        toastMessage = message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if toastMessage == message {
                toastMessage = nil
            }
        }
    }

    // MARK: - Actions

    // Write myName before any save* that enqueues Settings so the
    // materialize path reads the updated identity name (same ordering
    // RosterView's savePlayerEdit used before this moved here).
    private func saveMe(_ updated: Player) {
        let old = roster.first(where: { $0.id == updated.id })
        let renamed = old != nil && old?.name != updated.name
        if renamed {
            myName = updated.name
        }

        var r = roster
        if let idx = r.firstIndex(where: { $0.id == updated.id }) {
            r[idx] = updated
        } else {
            r.insert(updated, at: 0)
        }
        store.saveRoster(r)

        if renamed {
            var history = store.history
            for i in history.indices {
                if history[i].myPlayerId == updated.id {
                    history[i].myName = updated.name
                }
                if history[i].opponentPlayerId == updated.id {
                    history[i].opponentName = updated.name
                }
            }
            store.saveHistory(history)
        }

        editingPlayer = nil
    }

    private func loadIdentityFields() {
        let defaults = UserDefaults.standard
        gender = defaults.string(forKey: AppStorageKeys.gender)
        if let existing = defaults.object(forKey: AppStorageKeys.birthday) as? Date {
            hasBirthday = true
            birthday = existing
        } else {
            hasBirthday = false
        }
        introduction = defaults.string(forKey: AppStorageKeys.introduction) ?? ""
    }

    private func writeGender(_ newValue: String?) {
        let defaults = UserDefaults.standard
        if let newValue { defaults.set(newValue, forKey: AppStorageKeys.gender) } else { defaults.removeObject(forKey: AppStorageKeys.gender) }
        AppStore.shared.enqueueSettingsChange()
        store.refreshMyIdentitySnapshot()
    }

    private func writeBirthday(_ newValue: Date?) {
        let defaults = UserDefaults.standard
        if let newValue { defaults.set(newValue, forKey: AppStorageKeys.birthday) } else { defaults.removeObject(forKey: AppStorageKeys.birthday) }
        AppStore.shared.enqueueSettingsChange()
        store.refreshMyIdentitySnapshot()
    }

    private func writeIntroduction(_ newValue: String) {
        let defaults = UserDefaults.standard
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { defaults.removeObject(forKey: AppStorageKeys.introduction) } else { defaults.set(trimmed, forKey: AppStorageKeys.introduction) }
        AppStore.shared.enqueueSettingsChange()
        store.refreshMyIdentitySnapshot()
    }

    // shareGender/Birthday/IntroductionWithFriends all gate fields on the
    // SAME single "FriendIdentity" record (see AppStore.
    // refreshMyIdentitySnapshot), so every one of these three inline
    // toggles shares this one handler. Duplicate of FriendSharingSettingsView's
    // — see this file's header comment.
    private func toggleIdentityField(_ isOn: Bool) {
        AppStore.shared.enqueueSettingsChange()
        store.refreshMyIdentitySnapshot()
    }
}
