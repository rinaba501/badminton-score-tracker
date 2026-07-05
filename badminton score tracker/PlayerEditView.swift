//
//  PlayerEditView.swift
//  badminton score tracker (iOS)
//
//  Editor sheet for a single player: name (with duplicate detection), avatar
//  color, avatar image, and SF Symbol icon. iOS restyle of the Watch's editor
//  with a real keyboard and a Cancel/Save toolbar; validation logic
//  (nameIsValid / duplicate detection) is ported verbatim.
//

import SwiftUI
import BadmintonCore

struct PlayerEditView: View {
    let initialPlayer: Player
    let existingNames: [String]
    let onSave: (Player) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var localPlayer: Player
    @State private var isDuplicate = false

    init(initialPlayer: Player, existingNames: [String] = [], onSave: @escaping (Player) -> Void) {
        self.initialPlayer = initialPlayer
        self.existingNames = existingNames
        self.onSave = onSave
        _localPlayer = State(initialValue: initialPlayer)
    }

    private var nameIsValid: Bool {
        !localPlayer.name.trimmingCharacters(in: .whitespaces).isEmpty && !isDuplicate
    }

    private func checkDuplicate() {
        isDuplicate = existingNames.contains(localPlayer.name.trimmingCharacters(in: .whitespaces))
    }

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        AvatarView(name: localPlayer.name, color: localPlayer.avatarColor,
                                   size: 72, iconName: localPlayer.iconName)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("playeredit.name", text: $localPlayer.name)
                        .onChange(of: localPlayer.name) { _, _ in checkDuplicate() }
                    if isDuplicate {
                        Text("playeredit.name_taken")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("playeredit.name")
                }

                Section {
                    colorGrid
                } header: {
                    Text("playeredit.color")
                }

                Section {
                    avatarGrid
                } header: {
                    Text("playeredit.avatar")
                }

                Section {
                    iconGrid
                } header: {
                    Text("playeredit.icons")
                }
            }
            .navigationTitle(localPlayer.name.isEmpty ? Text("settings.add_player") : Text(localPlayer.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("history.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("playeredit.save") { onSave(localPlayer) }
                        .disabled(!nameIsValid)
                }
            }
        }
    }

    private var colorGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Array(Player.avatarColors.enumerated()), id: \.offset) { i, color in
                Circle()
                    .fill(color)
                    .frame(width: 36, height: 36)
                    .overlay(
                        Circle().stroke(Color.primary, lineWidth: localPlayer.colorIndex == i ? 3 : 0)
                    )
                    .onTapGesture { localPlayer.colorIndex = i }
                    .accessibilityAddTraits(localPlayer.colorIndex == i ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }

    private var avatarGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            avatarCell(isSelected: localPlayer.iconName == nil) {
                localPlayer.iconName = nil
            } content: {
                Text(verbatim: "A").font(.headline).foregroundStyle(.white)
            }

            ForEach(Player.avatarImageNames, id: \.self) { imageName in
                avatarCell(isSelected: localPlayer.iconName == imageName) {
                    localPlayer.iconName = imageName
                } content: {
                    Image(imageName).resizable().scaledToFit().padding(4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var iconGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(Player.sportIcons, id: \.self) { icon in
                avatarCell(isSelected: localPlayer.iconName == icon) {
                    localPlayer.iconName = icon
                } content: {
                    Image(systemName: icon).font(.title3).foregroundStyle(.white)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func avatarCell<Content: View>(isSelected: Bool,
                                           action: @escaping () -> Void,
                                           @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
            content()
        }
        .frame(width: 44, height: 44)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture(perform: action)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
