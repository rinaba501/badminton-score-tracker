//
//  MatchModel.swift
//  BadmintonCore
//
//  Pure, testable scoring logic for a best-of-three badminton match.
//

import Foundation

public enum Side: String, Codable, Equatable {
    case me
    case opponent
}

/// Final score of a single completed game within a match.
public struct GameScore: Codable, Equatable, Identifiable {
    public var id = UUID()
    public let my: Int
    public let opponent: Int

    public init(id: UUID = UUID(), my: Int, opponent: Int) {
        self.id = id
        self.my = my
        self.opponent = opponent
    }
}

/// Drives a single badminton match. No timers, no UI — every transition is a
/// pure function of the current state, which makes the rules unit-testable.
public struct BadmintonMatch: Codable, Equatable {
    public let pointsToWin: Int   // 21
    public let pointCap: Int      // 30 — at 29-29 the 30th point wins
    public let gamesToWin: Int    // 2  — best of three

    public private(set) var myScore: Int = 0
    public private(set) var opponentScore: Int = 0
    public private(set) var myGamesWon: Int = 0
    public private(set) var opponentGamesWon: Int = 0
    public private(set) var completedGames: [GameScore] = []
    /// Whoever won the previous rally serves next. Court side is derived from this.
    public private(set) var serverIsMe: Bool
    /// Index (0 or 1) of whichever of my team's two doubles partners currently
    /// occupies the right-hand service court. Meaningless in singles (stays 0).
    public private(set) var myRightBoxPartnerIndex: Int = 0
    public private(set) var opponentRightBoxPartnerIndex: Int = 0

    public init(serverIsMe: Bool = true,
                pointsToWin: Int = 21,
                pointCap: Int = 30,
                gamesToWin: Int = 2) {
        self.serverIsMe = serverIsMe
        self.pointsToWin = pointsToWin
        self.pointCap = pointCap
        self.gamesToWin = gamesToWin
    }

    // MARK: - Derived game / match state

    /// Winner of the *current* game, if it has just been decided. Stays non-nil
    /// (scores are left on screen) until `startNextGame()` clears the board.
    public var gameWinner: Side? {
        if myScore >= pointCap { return .me }
        if opponentScore >= pointCap { return .opponent }
        if myScore >= pointsToWin && myScore - opponentScore >= 2 { return .me }
        if opponentScore >= pointsToWin && opponentScore - myScore >= 2 { return .opponent }
        return nil
    }

    public var matchWinner: Side? {
        if myGamesWon >= gamesToWin { return .me }
        if opponentGamesWon >= gamesToWin { return .opponent }
        return nil
    }

    public var isMatchOver: Bool { matchWinner != nil }

    /// True while a game is decided but the next game hasn't started yet.
    public var isGameOver: Bool { gameWinner != nil }

    /// Either side is one rally away from winning the current game.
    public var isGamePoint: Bool {
        pointWouldEndGame(.me) || pointWouldEndGame(.opponent)
    }

    /// Either side is one rally away from winning the whole match.
    public var isMatchPoint: Bool {
        pointWouldEndMatch(.me) || pointWouldEndMatch(.opponent)
    }

    // MARK: - Serve

    public var servingSide: Side { serverIsMe ? .me : .opponent }

    /// In both singles and doubles the serving side serves from the right
    /// service court when its score is even, the left court when odd.
    public var serveFromRightCourt: Bool {
        (serverIsMe ? myScore : opponentScore) % 2 == 0
    }

    /// The doubles partner index (0 or 1) who should be serving/receiving next
    /// for `side`, given that team's current score parity and which partner
    /// currently occupies its right-hand court. Only meaningful in doubles;
    /// always resolves to 0 in singles (both box indices stay at their default).
    public func currentPartnerIndex(for side: Side) -> Int {
        let score = side == .me ? myScore : opponentScore
        let rightBoxIndex = side == .me ? myRightBoxPartnerIndex : opponentRightBoxPartnerIndex
        return score % 2 == 0 ? rightBoxIndex : 1 - rightBoxIndex
    }

    // MARK: - Mutations

    /// Award a rally to `side`. No-op once the current game or match is over —
    /// the caller advances with `startNextGame()`.
    public mutating func score(_ side: Side) {
        guard matchWinner == nil, gameWinner == nil else { return }

        // A team's two doubles partners swap right/left court occupancy only
        // when that team wins a rally while already serving (their service
        // run continues); a side-out never moves either team's partners —
        // whoever is already standing in the correct court becomes the next
        // server once that team wins the serve back. See MatchModel.swift's
        // header comment / plan for the derivation of this rule.
        let wasAlreadyServing = (side == servingSide)
        switch side {
        case .me:
            myScore += 1
            serverIsMe = true
            if wasAlreadyServing { myRightBoxPartnerIndex = 1 - myRightBoxPartnerIndex }
        case .opponent:
            opponentScore += 1
            serverIsMe = false
            if wasAlreadyServing { opponentRightBoxPartnerIndex = 1 - opponentRightBoxPartnerIndex }
        }

        if let winner = gameWinner {
            completedGames.append(GameScore(my: myScore, opponent: opponentScore))
            if winner == .me { myGamesWon += 1 } else { opponentGamesWon += 1 }
        }
    }

    /// Clear the board for the next game. Pass `serverIsMe` to override the
    /// automatic serve assignment, and the box-partner indices to set which
    /// partner starts in the right-hand court for each team (defaults to the
    /// first-listed partner on both teams, same UX bar as singles today,
    /// which has no "who serves first" picker either).
    public mutating func startNextGame(
        serverIsMe: Bool? = nil,
        myRightBoxPartnerIndex: Int? = nil,
        opponentRightBoxPartnerIndex: Int? = nil
    ) {
        guard gameWinner != nil, matchWinner == nil else { return }
        self.serverIsMe = serverIsMe ?? (myScore > opponentScore)
        self.myRightBoxPartnerIndex = myRightBoxPartnerIndex ?? 0
        self.opponentRightBoxPartnerIndex = opponentRightBoxPartnerIndex ?? 0
        myScore = 0
        opponentScore = 0
    }

    /// Force-ends the current game in favour of `winner` (used for sudden death in time mode).
    /// Records the current score as the game result and resets the board.
    public mutating func recordSuddenDeathGame(winner: Side) {
        guard gameWinner == nil, matchWinner == nil else { return }
        completedGames.append(GameScore(my: myScore, opponent: opponentScore))
        if winner == .me { myGamesWon += 1 } else { opponentGamesWon += 1 }
        serverIsMe = (winner == .me)
        myRightBoxPartnerIndex = 0
        opponentRightBoxPartnerIndex = 0
        myScore = 0
        opponentScore = 0
    }

    /// True when all games have been played and the result is a draw (only possible with an even gamesInMatch setting).
    public var isTied: Bool {
        let totalPlayed = completedGames.count
        return matchWinner == nil && totalPlayed >= (gamesToWin * 2 - 1) && myGamesWon == opponentGamesWon
    }

    /// True for exactly the one rally, across the whole deciding game, where
    /// a score first reaches the BWF mid-game end-change threshold (half of
    /// `pointsToWin`, rounded up) in the deciding game of a multi-game match
    /// (Law 12.1c) — e.g. 11 of 21. Always false in a single-game match
    /// (`gamesToWin == 1`, which has no "deciding game" distinct from its
    /// only game) or any game before the last. `side` must be the side that
    /// *just* scored the rally being checked.
    ///
    /// Requires the other side's score to still be under the threshold, not
    /// just that `side`'s score equals it — otherwise this fires a second
    /// time whenever the trailing side later catches up to (or ties) the
    /// threshold value the leader already crossed, long after the real
    /// end-change moment already happened.
    public func isCourtChangeThreshold(after side: Side) -> Bool {
        guard gamesToWin > 1, completedGames.count == gamesToWin * 2 - 2 else { return false }
        let threshold = (pointsToWin + 1) / 2
        let ownScore = side == .me ? myScore : opponentScore
        let otherScore = side == .me ? opponentScore : myScore
        return ownScore == threshold && otherScore < threshold
    }

    // MARK: - Helpers

    private func pointWouldEndGame(_ side: Side) -> Bool {
        guard gameWinner == nil else { return false }
        var copy = self
        copy.score(side)
        return copy.gameWinner == side
    }

    private func pointWouldEndMatch(_ side: Side) -> Bool {
        guard gameWinner == nil else { return false }
        var copy = self
        copy.score(side)
        return copy.matchWinner == side
    }
}

/// Which stored slot (`myName`/`myPlayerId` vs `opponentName`/`opponentPlayerId`)
/// won a `MatchRecord` — distinct from the live-match `Side` (`.me`/`.opponent`,
/// which is the *local device's* perspective during play). `RecordSide` is a
/// persisted, viewer-neutral tag: "near" is whichever team occupies the
/// my*/opponent* slots for this record, not necessarily the reader's own team.
/// Any viewer (including a future shared-club participant who isn't the
/// recorder) resolves their own win/loss by checking which slot their player
/// id or name falls into (see `StatsCalculator`'s `nearTeamNames`/`farTeamNames`),
/// then comparing against this tag — the same way it already worked when
/// `winner` was a display-name string, just without duplicating the name.
public enum RecordSide: String, Codable, Equatable {
    case near
    case far
}

/// A finished match, persisted to history.
public struct MatchRecord: Identifiable, Codable, Equatable {
    public let id: UUID
    public let games: [GameScore]
    public let myGamesWon: Int
    public let opponentGamesWon: Int
    public var winner: RecordSide
    public var myName: String
    public var opponentName: String
    public let date: Date
    public let duration: TimeInterval
    public var myPlayerId: UUID?
    public var opponentPlayerId: UUID?
    /// Second player on each team, for doubles. `nil` for singles matches —
    /// a record is "doubles" precisely when either partner field is non-nil;
    /// there is deliberately no separate isDoubles/gameMode flag to keep in
    /// sync. Optional so old singles records decode unaffected (no schema
    /// migration needed — see PersistenceStoreTests/SchemaVersioningTests).
    public var myPartnerName: String?
    public var opponentPartnerName: String?
    public var myPartnerPlayerId: UUID?
    public var opponentPartnerPlayerId: UUID?
    /// Roadmap Phase 5b: which `Club` this match belongs to. `nil` means
    /// personal (today's behavior, unchanged) — see Club.swift.
    public var clubId: UUID?
    /// Roadmap Phase 5 backlog (#160): false only while the match sits in a
    /// club with `Club.requireMatchConfirmation` on and no one has confirmed
    /// it yet. Defaults true so personal matches and clubs with the toggle
    /// off are always countable — see StatsCalculator call sites, which
    /// filter this out before computing standings (this type stays agnostic
    /// about the club's toggle, same as `clubId` stays agnostic about
    /// club-scoping logic).
    public var isConfirmed: Bool = true
    /// Practice-match tag: true (default) means Official — this match counts
    /// toward Standings/the Pending Confirmation queue like every match did
    /// before this field existed. `false` means Practice: it still appears
    /// in the club Activity Feed (full chronological log) but is filtered
    /// out of Standings and never enters Pending Confirmation regardless of
    /// `Club.requireMatchConfirmation`, since a match that never counts
    /// toward standings has nothing to gate. Defaults true so legacy history
    /// with no key on disk keeps counting toward standings unchanged.
    public var isOfficial: Bool = true
    /// Roadmap Phase 10a: the opponent's real account id (an `auth.uid()`
    /// string, same opaque-identity convention as `ChallengeRecord`'s
    /// participant fields), set only when the opponent was picked from
    /// Friends rather than the local roster/a guest. Deliberately distinct
    /// from `opponentPlayerId` (`UUID?`), which points into THIS device's
    /// own roster and is meaningless on the friend's device — see
    /// `MatchInvite.swift`. `nil` (the default) is every match that isn't
    /// tagged with a friend opponent, which is most of them.
    public var opponentParticipantId: String?
    /// Roadmap Phase 10a: set only on a record this device *mirrored* from
    /// an accepted `SharedMatchInvite` (see `MatchInviteMirror.swift`) —
    /// points back at the sender's own `MatchRecord.id`/`SharedMatchInvite.id`
    /// (the two are the same value by construction). `nil` means "not a
    /// mirror," which is the guard `AppStore.saveHistory` uses to avoid a
    /// mirrored record spawning its own outbound invite.
    public var sourceMatchId: UUID?

    /// True when either partner field is populated — the single home of the
    /// "is this record a Doubles match" check (see the comment above).
    public var isDoubles: Bool { myPartnerName != nil || opponentPartnerName != nil }

    /// Derives (myGamesWon, opponentGamesWon, winner) from a manually entered
    /// list of per-game scores — there is no live `BadmintonMatch` to read
    /// these from when a match is logged after the fact instead of played
    /// live (issue #278). Returns `nil` if `games` is empty, any single game
    /// is tied (impossible in real badminton — every game has a winner), or
    /// the overall game count is tied (a match can't end without one side
    /// winning more games than the other).
    public static func resultFromManualGames(_ games: [GameScore]) -> ManualResult? {
        guard !games.isEmpty, games.allSatisfy({ $0.my != $0.opponent }) else { return nil }
        let myGamesWon = games.filter({ $0.my > $0.opponent }).count
        let opponentGamesWon = games.count - myGamesWon
        guard myGamesWon != opponentGamesWon else { return nil }
        return ManualResult(myGamesWon: myGamesWon, opponentGamesWon: opponentGamesWon,
                             winner: myGamesWon > opponentGamesWon ? .near : .far)
    }

    /// Named tuple stand-in for `resultFromManualGames` — a plain 3-member
    /// tuple trips SwiftLint's `large_tuple` rule, same reasoning as
    /// `CloudSyncSpike`'s `PendingRecord`.
    public struct ManualResult: Equatable {
        public let myGamesWon: Int
        public let opponentGamesWon: Int
        public let winner: RecordSide
    }

    public init(id: UUID = UUID(),
                games: [GameScore],
                myGamesWon: Int,
                opponentGamesWon: Int,
                winner: RecordSide,
                myName: String = "",
                opponentName: String = "",
                date: Date,
                duration: TimeInterval = 0,
                myPlayerId: UUID? = nil,
                opponentPlayerId: UUID? = nil,
                myPartnerName: String? = nil,
                opponentPartnerName: String? = nil,
                myPartnerPlayerId: UUID? = nil,
                opponentPartnerPlayerId: UUID? = nil,
                clubId: UUID? = nil,
                isConfirmed: Bool = true,
                isOfficial: Bool = true,
                opponentParticipantId: String? = nil,
                sourceMatchId: UUID? = nil) {
        self.id = id
        self.games = games
        self.myGamesWon = myGamesWon
        self.opponentGamesWon = opponentGamesWon
        self.winner = winner
        self.myName = myName
        self.opponentName = opponentName
        self.date = date
        self.duration = duration
        self.myPlayerId = myPlayerId
        self.opponentPlayerId = opponentPlayerId
        self.myPartnerName = myPartnerName
        self.opponentPartnerName = opponentPartnerName
        self.myPartnerPlayerId = myPartnerPlayerId
        self.opponentPartnerPlayerId = opponentPartnerPlayerId
        self.clubId = clubId
        self.isConfirmed = isConfirmed
        self.isOfficial = isOfficial
        self.opponentParticipantId = opponentParticipantId
        self.sourceMatchId = sourceMatchId
    }

    private enum CodingKeys: String, CodingKey {
        case id, games, myGamesWon, opponentGamesWon, winner, myName, opponentName, date, duration,
             myPlayerId, opponentPlayerId, myPartnerName, opponentPartnerName, myPartnerPlayerId, opponentPartnerPlayerId,
             clubId, isConfirmed, isOfficial, opponentParticipantId, sourceMatchId
    }

    /// Self-migrating: reads the current `RecordSide` shape, or — for records
    /// persisted before this change — the legacy `winner: String` (a copy of
    /// either `myName` or `opponentName`) and converts it. This keeps the
    /// migration local to the type itself, so `PersistenceStore`'s generic
    /// envelope/tolerant-decode machinery needs no changes and no schema
    /// version bump (see PersistenceStoreTests/SchemaVersioningTests).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        games = try container.decode([GameScore].self, forKey: .games)
        myGamesWon = try container.decode(Int.self, forKey: .myGamesWon)
        opponentGamesWon = try container.decode(Int.self, forKey: .opponentGamesWon)
        myName = try container.decodeIfPresent(String.self, forKey: .myName) ?? ""
        opponentName = try container.decodeIfPresent(String.self, forKey: .opponentName) ?? ""
        date = try container.decode(Date.self, forKey: .date)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        myPlayerId = try container.decodeIfPresent(UUID.self, forKey: .myPlayerId)
        opponentPlayerId = try container.decodeIfPresent(UUID.self, forKey: .opponentPlayerId)
        myPartnerName = try container.decodeIfPresent(String.self, forKey: .myPartnerName)
        opponentPartnerName = try container.decodeIfPresent(String.self, forKey: .opponentPartnerName)
        myPartnerPlayerId = try container.decodeIfPresent(UUID.self, forKey: .myPartnerPlayerId)
        opponentPartnerPlayerId = try container.decodeIfPresent(UUID.self, forKey: .opponentPartnerPlayerId)
        clubId = try container.decodeIfPresent(UUID.self, forKey: .clubId)
        isConfirmed = try container.decodeIfPresent(Bool.self, forKey: .isConfirmed) ?? true
        isOfficial = try container.decodeIfPresent(Bool.self, forKey: .isOfficial) ?? true
        opponentParticipantId = try container.decodeIfPresent(String.self, forKey: .opponentParticipantId)
        sourceMatchId = try container.decodeIfPresent(UUID.self, forKey: .sourceMatchId)

        if let side = try? container.decode(RecordSide.self, forKey: .winner) {
            winner = side
        } else {
            let legacyWinnerName = try container.decode(String.self, forKey: .winner)
            winner = legacyWinnerName == myName ? .near : .far
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(games, forKey: .games)
        try container.encode(myGamesWon, forKey: .myGamesWon)
        try container.encode(opponentGamesWon, forKey: .opponentGamesWon)
        try container.encode(winner, forKey: .winner)
        try container.encode(myName, forKey: .myName)
        try container.encode(opponentName, forKey: .opponentName)
        try container.encode(date, forKey: .date)
        try container.encode(duration, forKey: .duration)
        try container.encodeIfPresent(myPlayerId, forKey: .myPlayerId)
        try container.encodeIfPresent(opponentPlayerId, forKey: .opponentPlayerId)
        try container.encodeIfPresent(myPartnerName, forKey: .myPartnerName)
        try container.encodeIfPresent(opponentPartnerName, forKey: .opponentPartnerName)
        try container.encodeIfPresent(myPartnerPlayerId, forKey: .myPartnerPlayerId)
        try container.encodeIfPresent(opponentPartnerPlayerId, forKey: .opponentPartnerPlayerId)
        try container.encodeIfPresent(clubId, forKey: .clubId)
        try container.encode(isConfirmed, forKey: .isConfirmed)
        try container.encode(isOfficial, forKey: .isOfficial)
        try container.encodeIfPresent(opponentParticipantId, forKey: .opponentParticipantId)
        try container.encodeIfPresent(sourceMatchId, forKey: .sourceMatchId)
    }
}
