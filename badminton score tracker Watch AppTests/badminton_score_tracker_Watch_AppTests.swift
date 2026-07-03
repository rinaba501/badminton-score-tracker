//
//  badminton_score_tracker_Watch_AppTests.swift
//  badminton score tracker Watch AppTests
//
//  The core-logic tests moved to BadmintonCore/Tests/BadmintonCoreTests —
//  run them with `swift test --package-path BadmintonCore` (seconds on any
//  Mac, no watchOS simulator needed). This target remains as the home for
//  future app-layer tests (e.g. the issue #96 GameView view-model tests)
//  and to keep the shared scheme's test action valid.
//

import Testing
@testable import badminton_score_tracker_Watch_App

struct WatchAppSmokeTests {
    @Test func appModuleLoads() {
        #expect(Bool(true))
    }
}
