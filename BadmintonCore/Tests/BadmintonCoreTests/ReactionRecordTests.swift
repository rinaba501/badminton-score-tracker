//
//  ReactionRecordTests.swift
//  BadmintonCoreTests
//
//  Roadmap Phase 5 backlog (#164): ReactionRecord codec round-trips.
//

import Foundation
import Testing
@testable import BadmintonCore

struct ReactionRecordTests {

    private func makeReaction(
        id: UUID = UUID(),
        clubId: UUID = UUID(),
        matchId: UUID = UUID(),
        kind: ReactionRecord.Kind = .emoji,
        content: String = "👍"
    ) -> ReactionRecord {
        ReactionRecord(
            id: id, clubId: clubId, matchId: matchId,
            authorParticipantId: "alice-id", authorDisplayName: "Alice",
            kind: kind, content: content,
            createdDate: Date(timeIntervalSince1970: 1_000)
        )
    }

    @Test func encodeDecodeRoundTripsAReactionList() throws {
        let reactions = [
            makeReaction(),
            makeReaction(kind: .comment, content: "Great match!")
        ]
        let encoded = try #require(PersistenceStore.encodeReactions(reactions))
        #expect(PersistenceStore.decodeReactions(encoded) == reactions)
    }

    @Test func decodeReactionsReturnsEmptyArrayOnEmptyOrGarbageData() {
        #expect(PersistenceStore.decodeReactions(Data()).isEmpty)
        #expect(PersistenceStore.decodeReactions(Data("not json".utf8)).isEmpty)
    }

    @Test func singleReactionEncodeDecodeRoundTrip() throws {
        let reaction = makeReaction()
        let encoded = try #require(PersistenceStore.encodeReaction(reaction))
        let decoded = try #require(PersistenceStore.decodeReaction(encoded))
        #expect(decoded == reaction)
    }

    @Test func kindRoundTripsThroughAllCases() throws {
        for kind: ReactionRecord.Kind in [.emoji, .comment] {
            let reaction = makeReaction(kind: kind)
            let encoded = try #require(PersistenceStore.encodeReaction(reaction))
            let decoded = try #require(PersistenceStore.decodeReaction(encoded))
            #expect(decoded.kind == kind)
        }
    }

    @Test func unicodeContentRoundTripsIntact() throws {
        for content in ["🔥", "🏸", "😮", "ナイスゲーム！", "好球 👍🏽"] {
            let reaction = makeReaction(kind: .comment, content: content)
            let encoded = try #require(PersistenceStore.encodeReaction(reaction))
            let decoded = try #require(PersistenceStore.decodeReaction(encoded))
            #expect(decoded.content == content)
        }
    }

    @Test func diffReactionsReportsUpsertsAndDeletes() {
        let clubId = UUID()
        let matchId = UUID()
        let unchanged = makeReaction(clubId: clubId, matchId: matchId)
        let toRemove = makeReaction(clubId: clubId, matchId: matchId, content: "🔥")
        // Same id, different content — an in-place change must surface as an upsert.
        let edited = makeReaction(id: unchanged.id, clubId: clubId, matchId: matchId, content: "😮")
        let added = makeReaction(clubId: clubId, matchId: matchId, kind: .comment, content: "Nice!")

        let diff = PersistenceStore.diffReactions(from: [unchanged, toRemove], to: [edited, added])
        #expect(Set(diff.upsertedIds) == Set([edited.id, added.id]))
        #expect(diff.deletedIds == [toRemove.id])
    }
}
