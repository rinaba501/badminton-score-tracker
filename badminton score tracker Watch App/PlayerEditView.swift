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
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(localPlayer.iconName == imageName
                                      ? Color.blue.opacity(0.5)
                                      : Color.secondary.opacity(0.25))
                            Image(imageName)
                                .resizable()
                                .scaledToFit()
                                .padding(3)
                        }
                        .frame(height: 36)
                        .onTapGesture { localPlayer.iconName = imageName }
                    }
                }

                Text("playeredit.icons")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Player.sportIcons, id: \.self) { icon in
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(localPlayer.iconName == icon
                                      ? Color.blue.opacity(0.5)
                                      : Color.secondary.opacity(0.25))
                            Image(systemName: icon)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                        }
                        .frame(height: 36)
                        .onTapGesture { localPlayer.iconName = icon }
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
    }
}
