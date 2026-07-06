//
//  SceneDelegate.swift
//  badminton score tracker (iOS)
//
//  Handles window scene events, specifically catching user acceptance of
//  CloudKit shares (CKShare) so they can be processed by CloudKitSyncManager.
//

import UIKit
import CloudKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            CloudKitSyncManager.shared.acceptShare(metadata: metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        CloudKitSyncManager.shared.acceptShare(metadata: cloudKitShareMetadata)
    }
}
