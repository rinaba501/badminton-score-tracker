//
//  HapticsProvider.swift
//  badminton score tracker Watch App
//
//  Abstracts WKInterfaceDevice haptics behind a protocol so GameViewModel
//  can be tested without a physical device.
//

import WatchKit

protocol HapticsProvider {
    func play(_ type: WKHapticType)
}

final class WatchHapticsProvider: HapticsProvider {
    func play(_ type: WKHapticType) {
        WKInterfaceDevice.current().play(type)
    }
}

struct NoOpHapticsProvider: HapticsProvider {
    func play(_ type: WKHapticType) {}
}
