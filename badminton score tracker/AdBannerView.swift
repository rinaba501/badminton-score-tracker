//
//  AdBannerView.swift
//  badminton score tracker (iOS)
//
//  The single home of all ad code (iOS-only — no ad SDK exists for watchOS;
//  BadmintonCore and the Watch App never see GoogleMobileAds). A fixed-size
//  AdMob banner shown at the bottom of the browse screens (menu, History,
//  Stats) for non-Pro users — never on the live-scoring Game screen. Call
//  sites gate on Entitlements.showsAds, so buying Pro removes every banner
//  without touching this file.
//
//  Consent: on first appearance the Google UMP consent flow runs (GDPR),
//  then the ATT prompt (personalized vs. non-personalized ads), and only
//  then does the SDK start and the banner load. Until consent allows ad
//  requests this view renders as empty space of zero height.
//
//  The ad-unit ID below and GADApplicationIdentifier in Info.plist are
//  Google's public TEST ids — replace both with real AdMob ids before
//  App Store release.
//

import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI
import UIKit
import UserMessagingPlatform

/// Google's public test banner ad-unit. Replace before release.
private let bannerAdUnitID = "ca-app-pub-3940256099942544/2934735716"

struct AdBannerView: View {
    @StateObject private var coordinator = AdCoordinator.shared

    var body: some View {
        Group {
            if coordinator.canRequestAds {
                BannerAdRepresentable()
                    .frame(width: 320, height: 50)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(Text("ads.banner"))
            }
        }
        .onAppear { coordinator.startIfNeeded() }
    }
}

/// Runs the one-time UMP consent → ATT prompt → SDK start sequence and
/// publishes whether ads may be requested. Shared so the flow runs once no
/// matter which screen shows a banner first.
@MainActor
private final class AdCoordinator: ObservableObject {
    static let shared = AdCoordinator()

    @Published private(set) var canRequestAds = false
    private var started = false

    func startIfNeeded() {
        guard !started else { return }
        started = true
        ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters()) { [weak self] _ in
            // On error UMP leaves canRequestAds at its last known value —
            // fall through and honor whatever it reports.
            ConsentForm.loadAndPresentIfRequired(from: nil) { _ in
                Task { @MainActor in self?.finishStartup() }
            }
        }
    }

    private func finishStartup() {
        guard ConsentInformation.shared.canRequestAds else { return }
        // ATT after UMP: denial just means non-personalized ads.
        ATTrackingManager.requestTrackingAuthorization { [weak self] _ in
            Task { @MainActor in
                MobileAds.shared.start()
                self?.canRequestAds = true
            }
        }
    }
}

private struct BannerAdRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeBanner)
        banner.adUnitID = bannerAdUnitID
        banner.load(Request())
        return banner
    }

    func updateUIView(_ uiView: BannerView, context: Context) {}
}
