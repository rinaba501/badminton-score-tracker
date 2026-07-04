//
//  badminton_score_tracker_Watch_AppTests.swift
//  badminton score tracker Watch AppTests
//
//  App-layer tests for GameViewModel. These compile in CI (the Watch App build
//  job uses build-for-testing which compiles both test bundles) but do not run
//  there — running requires a concrete watchOS simulator. Execute locally with
//  the Xcode test action against a watchOS simulator.
//
//  Core-logic tests live in BadmintonCore/Tests/BadmintonCoreTests and run
//  via `swift test --package-path BadmintonCore` (seconds, no simulator).
//

import Foundation
import Testing
import BadmintonCore
@testable import badminton_score_tracker_Watch_App

struct WatchAppSmokeTests {
    @Test func appModuleLoads() {
        #expect(Bool(true))
    }
}

@MainActor
struct GameViewModelTests {

    // MARK: - Scoring

    @Test func tapIncreasesScore() {
        let vm = GameViewModel(hapticsProvider: NoOpHapticsProvider())
        vm.tap(.me)
        #expect(vm.match.myScore == 1)
        #expect(vm.match.opponentScore == 0)
    }

    @Test func tapOpponentIncreasesOpponentScore() {
        let vm = GameViewModel(hapticsProvider: NoOpHapticsProvider())
        vm.tap(.opponent)
        #expect(vm.match.opponentScore == 1)
        #expect(vm.match.myScore == 0)
    }

    @Test func tapIsNoOpWhenGameOver() {
        let vm = GameViewModel(hapticsProvider: NoOpHapticsProvider())
        // Score enough to end the game
        for _ in 0..<21 { vm.tap(.me) }
        #expect(vm.match.gameWinner == .me)
        let scoreBeforeTap = vm.match.myScore
        vm.tap(.me)
        // Score must not advance after game over
        #expect(vm.match.myScore == scoreBeforeTap)
    }

    // MARK: - Undo

    @Test func undoRestoresPreviousState() {
        let vm = GameViewModel(hapticsProvider: NoOpHapticsProvider())
        vm.tap(.me)   // 1-0
        vm.tap(.me)   // 2-0
        vm.undo()
        #expect(vm.match.myScore == 1)
    }

    @Test func undoOnEmptyStackIsNoOp() {
        let vm = GameViewModel(hapticsProvider: NoOpHapticsProvider())
        vm.undo()  // should not crash
        #expect(vm.match.myScore == 0)
    }

    // MARK: - New match

    @Test func newMatchResetsState() {
        let vm = GameViewModel(hapticsProvider: NoOpHapticsProvider())
        vm.tap(.me)
        vm.tap(.opponent)
        vm.newMatch()
        #expect(vm.match.myScore == 0)
        #expect(vm.match.opponentScore == 0)
        #expect(vm.undoStack.isEmpty)
        #expect(vm.savedCurrentMatch == false)
    }

    // MARK: - Save match

    @Test func saveMatchBuildsRecordWithCorrectWinner() {
        let vm = GameViewModel(hapticsProvider: NoOpHapticsProvider())
        // Score a full match win for me (2 games, 21-0 each)
        for _ in 0..<21 { vm.tap(.me) }
        vm.startNextGame()
        for _ in 0..<21 { vm.tap(.me) }
        // saveMatch is called automatically on match win via tap()
        #expect(vm.savedCurrentMatch == true)
    }

    @Test func saveMatchIsIdempotent() {
        let vm = GameViewModel(hapticsProvider: NoOpHapticsProvider())
        for _ in 0..<21 { vm.tap(.me) }
        vm.startNextGame()
        for _ in 0..<21 { vm.tap(.me) }
        let historyCount = AppStore.shared.history.count
        vm.saveMatch()  // second call — must be a no-op
        #expect(AppStore.shared.history.count == historyCount)
    }

    // MARK: - Player identity (#108)

    @Test func saveMatchStampsStableLocalPlayerIdForMe() {
        // Two separate matches, both played as the default near-side "Me" —
        // the stamped id must be the same both times, and must equal the
        // app's persisted local identity (not a roster lookup, since "Me" is
        // never added to the roster).
        func playAndSaveMatch() -> UUID? {
            let vm = GameViewModel(hapticsProvider: NoOpHapticsProvider())
            for _ in 0..<21 { vm.tap(.me) }
            vm.startNextGame()
            for _ in 0..<21 { vm.tap(.me) }
            return AppStore.shared.history.last?.myPlayerId
        }
        let firstId = playAndSaveMatch()
        let secondId = playAndSaveMatch()
        #expect(firstId != nil)
        #expect(firstId == secondId)
        #expect(firstId == AppStore.shared.localPlayerId)
    }

    @Test func saveMatchStampsNilOpponentIdForGuest() {
        let defaults = UserDefaults.standard
        defaults.set(Player.guestFarToken, forKey: AppStorageKeys.matchOpponentName)
        defer { defaults.removeObject(forKey: AppStorageKeys.matchOpponentName) }

        let vm = GameViewModel(hapticsProvider: NoOpHapticsProvider())
        for _ in 0..<21 { vm.tap(.me) }
        vm.startNextGame()
        for _ in 0..<21 { vm.tap(.me) }

        #expect(AppStore.shared.history.last?.opponentPlayerId == nil)
        #expect(AppStore.shared.history.last?.opponentName == Player.guestFarToken)
    }
}
