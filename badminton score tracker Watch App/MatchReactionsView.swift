//
//  MatchReactionsView.swift
//  badminton score tracker Watch App
//
//  Roadmap Phase 5 backlog (#164): reactions/comments for one club match,
//  pushed from a ClubDetailView activity-feed row. A detail screen (rather
//  than buttons inside the tiny feed row) keeps every emoji a full-size tap
//  target and avoids List-row tap conflicts. Emoji reactions toggle on tap;
//  comments are read-only here — composing one needs a real keyboard, so
//  authoring lives in the iOS app's counterpart view.
//

import SwiftUI
import BadmintonCore

struct MatchReactionsView: View {
    let clubId: UUID
    let entry: StatsCalculator.ActivityFeedEntry
    let myParticipantId: String?
    let myDisplayName: String?

    @EnvironmentObject private var appStore: AppStore

    /// The fixed reaction palette. UI-only — the model stores whatever string
    /// it's given, so this list can grow without a data migration.
    static let emojiOptions = ["👍", "🔥", "🏸", "😮"]

    private var matchReactions: [ReactionRecord] {
        appStore.reactions.filter { $0.clubId == clubId && $0.matchId == entry.id }
    }

    private var comments: [ReactionRecord] {
        matchReactions.filter { $0.kind == .comment }.sorted { $0.createdDate < $1.createdDate }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(entry.myName) vs \(entry.opponentName)")
                        .font(.caption)
                    Text(entry.games.map { "\($0.my)-\($0.opponent)" }.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("clubs.reactions")) {
                ForEach(Self.emojiOptions, id: \.self) { emoji in
                    emojiRow(emoji)
                }
            }

            if !comments.isEmpty {
                Section(header: Text("clubs.comments")) {
                    ForEach(comments) { comment in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(comment.authorDisplayName)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(comment.content)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("clubs.reactions")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func emojiRow(_ emoji: String) -> some View {
        let reactionCount = matchReactions.filter { $0.kind == .emoji && $0.content == emoji }.count
        let mine = myReaction(for: emoji) != nil
        Button(action: { toggle(emoji) }) {
            HStack {
                Text(emoji)
                Spacer()
                if reactionCount > 0 {
                    Text("\(reactionCount)")
                        .font(.caption)
                        .foregroundColor(mine ? .accentColor : .secondary)
                }
            }
        }
        .disabled(myParticipantId == nil)
        .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.reaction_button", comment: ""), emoji, reactionCount)))
        .accessibilityHint(mine ? Text("a11y.my_reaction") : Text(""))
    }

    private func myReaction(for emoji: String) -> ReactionRecord? {
        guard let myParticipantId else { return nil }
        return matchReactions.first {
            $0.kind == .emoji && $0.content == emoji && $0.authorParticipantId == myParticipantId
        }
    }

    private func toggle(_ emoji: String) {
        guard let myParticipantId, let myDisplayName else { return }
        if let existing = myReaction(for: emoji) {
            appStore.saveReactions(appStore.reactions.filter { $0.id != existing.id })
        } else {
            let reaction = ReactionRecord(
                clubId: clubId, matchId: entry.id,
                authorParticipantId: myParticipantId, authorDisplayName: myDisplayName,
                kind: .emoji, content: emoji
            )
            appStore.saveReactions(appStore.reactions + [reaction])
        }
    }
}
