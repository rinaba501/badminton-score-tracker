//
//  NewMatchFlow.swift
//  badminton score tracker (iOS)
//
//  Modal container for scoring a match on the phone: player selection
//  (PreMatchView) then live scoring (GameView). Presented as a fullScreenCover
//  from ContentView; `onClose` dismisses it. PreMatchView writes the match
//  config to @AppStorage (matchMyName/…, gameMode) and GameView's view model
//  reads it on appear — the same shared-AppStorage handoff the Watch uses
//  between its .preMatch and .game routes.
//

import SwiftUI

struct NewMatchFlow: View {
    let onClose: () -> Void

    @State private var phase: Phase = .preMatch

    private enum Phase { case preMatch, game }

    var body: some View {
        switch phase {
        case .preMatch:
            PreMatchView(onReady: { phase = .game }, onCancel: onClose)
        case .game:
            GameView(onExit: onClose)
        }
    }
}
