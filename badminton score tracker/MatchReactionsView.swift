//
//  MatchReactionsView.swift
//  badminton score tracker (iOS)
//
//  Roadmap Phase 5 backlog (#164): the reactions/comments sheet for one club
//  match, presented from a ClubDetailView activity-feed row. iOS counterpart
//  of the Watch's pushed MatchReactionsView, with one deliberate asymmetry:
//  comments can be COMPOSED here (real keyboard), while the Watch only reads
//  them. Emoji toggling works in both places. Authoring requires a resolved
//  CKShare participant identity (myParticipantId), same as sending a
//  challenge — without it the input controls are disabled, never hidden
//  mid-session.
//

import SwiftUI
import BadmintonCore

struct MatchReactionsView: View {
    let clubId: UUID
    let entry: StatsCalculator.ActivityFeedEntry
    let myParticipantId: String?
    let myDisplayName: String?

    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""

    /// The fixed reaction palette. UI-only — the model stores whatever string
    /// it's given, so this list can grow without a data migration.
    static let emojiOptions = ["👍", "🔥", "🏸", "😮"]
    /// Keep comments one-liners; the record itself has no length rule.
    static let commentCharacterLimit = 200

    private var matchReactions: [ReactionRecord] {
        store.reactions.filter { $0.clubId == clubId && $0.matchId == entry.id }
    }

    private var comments: [ReactionRecord] {
        matchReactions.filter { $0.kind == .comment }.sorted { $0.createdDate < $1.createdDate }
    }

    private var trimmedDraft: String {
        String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.commentCharacterLimit))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(entry.myName) vs \(entry.opponentName)")
                        Text("\(entry.myGamesWon)-\(entry.opponentGamesWon)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    emojiBar
                } header: {
                    Text("clubs.reactions")
                }

                Section {
                    if comments.isEmpty {
                        Text("clubs.no_comments")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(comments) { comment in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(comment.authorDisplayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(comment.content)
                            }
                        }
                    }
                    HStack {
                        TextField("clubs.comment_placeholder", text: $draft)
                            .disabled(myParticipantId == nil)
                        Button("clubs.comment_send") { sendComment() }
                            .disabled(myParticipantId == nil || trimmedDraft.isEmpty)
                    }
                } header: {
                    Text("clubs.comments")
                }
            }
            .navigationTitle("clubs.reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
    }

    private var emojiBar: some View {
        HStack(spacing: 16) {
            ForEach(Self.emojiOptions, id: \.self) { emoji in
                ReactionEmojiButton(
                    emoji: emoji,
                    reactionCount: matchReactions.filter { $0.kind == .emoji && $0.content == emoji }.count,
                    isMine: myReaction(for: emoji) != nil,
                    isEnabled: myParticipantId != nil,
                    action: { toggle(emoji) }
                )
            }
            Spacer()
        }
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
            store.saveReactions(store.reactions.filter { $0.id != existing.id })
        } else {
            let reaction = ReactionRecord(
                clubId: clubId, matchId: entry.id,
                authorParticipantId: myParticipantId, authorDisplayName: myDisplayName,
                kind: .emoji, content: emoji
            )
            store.saveReactions(store.reactions + [reaction])
        }
    }

    private func sendComment() {
        guard let myParticipantId, let myDisplayName else { return }
        let content = trimmedDraft
        guard !content.isEmpty else { return }
        let comment = ReactionRecord(
            clubId: clubId, matchId: entry.id,
            authorParticipantId: myParticipantId, authorDisplayName: myDisplayName,
            kind: .comment, content: content
        )
        store.saveReactions(store.reactions + [comment])
        draft = ""
    }
}

/// One emoji toggle chip. Borderless so it never hijacks the enclosing
/// List row's tap; tinted when the current user has this reaction.
struct ReactionEmojiButton: View {
    let emoji: String
    let reactionCount: Int
    let isMine: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(emoji)
                if reactionCount > 0 {
                    Text("\(reactionCount)")
                        .font(.caption)
                        .foregroundStyle(isMine ? Color.accentColor : Color.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isMine ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
            )
        }
        .buttonStyle(.borderless)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(String(format: NSLocalizedString("a11y.reaction_button", comment: ""), emoji, reactionCount)))
        .accessibilityHint(isMine ? Text("a11y.my_reaction") : Text(""))
    }
}
