//
//  PlayerEditView.swift
//  badminton score tracker Watch App
//
//  Editor sheet for a single player: name (with duplicate detection),
//  avatar color, avatar image, and SF Symbol icon.
//

import SwiftUI
import BadmintonCore

struct PlayerEditView: View {
    let initialPlayer: Player
    let onSave: (Player) -> Void
    let existingNames: [String]
    /// Roadmap Phase 5d: clubs offered in the "belongs to" picker below. Empty
    /// by default so call sites that don't manage club membership (e.g. the
    /// pre-match add-player flow) don't need to thread `AppStore.clubs` through.
    let clubs: [Club]

    @EnvironmentObject private var storeManager: StoreManager
    @State private var localPlayer: Player
    @State private var isDuplicate = false
    @State private var showPaywall = false

    init(initialPlayer: Player, existingNames: [String] = [], clubs: [Club] = [], onSave: @escaping (Player) -> Void) {
        self.initialPlayer = initialPlayer
        self.existingNames = existingNames
        self.clubs = clubs
        self.onSave = onSave
        _localPlayer = State(initialValue: initialPlayer)
    }

    private var nameIsValid: Bool {
        !localPlayer.name.trimmingCharacters(in: .whitespaces).isEmpty && !isDuplicate
    }

    private func checkDuplicate() {
        isDuplicate = existingNames.contains(localPlayer.name.trimmingCharacters(in: .whitespaces))
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    AvatarView(
                        name: localPlayer.name,
                        color: localPlayer.avatarColor,
                        size: 48,
                        iconName: localPlayer.iconName
                    )
                    Spacer()
                }
                .padding(.top, 4)

                Text("playeredit.name")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextField("playeredit.name", text: $localPlayer.name)
                    .textFieldStyle(.plain)
                    .padding(6)
                    .background(isDuplicate ? Color.red.opacity(0.2) : Color.secondary.opacity(0.15))
                    .cornerRadius(8)
                    .onSubmit { checkDuplicate() }
                    .onChange(of: localPlayer.name) { _ in checkDuplicate() }
                if isDuplicate {
                    Text("playeredit.name_taken")
                        .font(.caption2)
                        .foregroundColor(.red)
                }

                if !clubs.isEmpty {
                    Text("playeredit.club")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Picker("playeredit.club", selection: $localPlayer.clubId) {
                        Text("playeredit.club_personal").tag(UUID?.none)
                        ForEach(clubs) { club in
                            Text(club.name).tag(UUID?.some(club.id))
                        }
                    }
                    .labelsHidden()
                }

                Text("playeredit.color")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(Player.avatarColors.enumerated()), id: \.offset) { i, color in
                        Circle()
                            .fill(color)
                            .frame(height: 28)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: localPlayer.colorIndex == i ? 2.5 : 0)
                            )
                            .onTapGesture { localPlayer.colorIndex = i }
                    }
                }

                Text("playeredit.avatar")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(localPlayer.iconName == nil
                                  ? Color.blue.opacity(0.5)
                                  : Color.secondary.opacity(0.25))
                        Text("A")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(height: 36)
                    .onTapGesture { localPlayer.iconName = nil }

                    ForEach(Player.avatarImageNames, id: \.self) { imageName in
                        avatarCell(isSelected: localPlayer.iconName == imageName, iconName: imageName) {
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .padding(3)
                        }
                    }
                }

                Text("playeredit.icons")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Player.sportIcons, id: \.self) { icon in
                        avatarCell(isSelected: localPlayer.iconName == icon, iconName: icon) {
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                    }
                }

                Button("playeredit.save") {
                    onSave(localPlayer)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
                .disabled(!nameIsValid)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle(localPlayer.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
    }

    /// One selectable avatar/icon cell. Premium catalog entries show a lock
    /// while unentitled and open the paywall instead of selecting.
    private func avatarCell<Content: View>(isSelected: Bool,
                                           iconName: String,
                                           @ViewBuilder content: () -> Content) -> some View {
        let locked = Player.isPremiumAvatar(iconName) && !storeManager.entitlements.hasAllAvatars
        return ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.blue.opacity(0.5) : Color.secondary.opacity(0.25))
            content()
                .opacity(locked ? 0.4 : 1)
            if locked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.white)
                    .accessibilityLabel(Text("paywall.locked"))
            }
        }
        .frame(height: 36)
        .onTapGesture {
            if locked {
                showPaywall = true
            } else {
                localPlayer.iconName = iconName
            }
        }
    }
}
