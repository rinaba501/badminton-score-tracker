//
//  HapticsProvider.swift
//  badminton score tracker (iOS)
//
//  iOS haptics behind a protocol (mirrors the Watch's HapticsProvider, which
//  the shared GameViewModel design was built around). The Watch uses
//  WKHapticType; iOS has no equivalent, so a platform-neutral GameHapticType
//  maps to UIKit's impact / notification generators.
//

import UIKit

enum GameHapticType {
    case click          // a point scored
    case notification   // game/match point reached, or sudden death
    case success        // game or match won
    case retry          // secondary buzz after a game win
    case directionUp    // undo
    case start          // next game / match start
}

protocol HapticsProvider {
    func play(_ type: GameHapticType)
}

final class UIKitHapticsProvider: HapticsProvider {
    func play(_ type: GameHapticType) {
        switch type {
        case .click:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .notification:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .retry:
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        case .directionUp:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .start:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

struct NoOpHapticsProvider: HapticsProvider {
    func play(_ type: GameHapticType) {}
}
