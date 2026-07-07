//
//  CloudSharingView.swift
//  badminton score tracker (iOS)
//
//  Roadmap Phase 5e: SwiftUI wrapper around UICloudSharingController, the
//  system sheet for sending a CKShare invite. iOS-only — UIKit has no
//  watchOS counterpart, so this is the reason invite-sending only exists
//  on the iOS target. Presented from ClubDetailView with the CKShare
//  returned by CloudKitSyncManager.fetchOrCreateShare(for:).
//

import SwiftUI
import CloudKit

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let itemTitle: String

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(itemTitle: itemTitle)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let itemTitle: String

        init(itemTitle: String) {
            self.itemTitle = itemTitle
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            itemTitle
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            // The CKShare record itself is already persisted by fetchOrCreateShare
            // before this sheet is shown, so a failure here only affects sending
            // this particular invite — the user can just reopen Invite to retry.
        }
    }
}
