//
//  WatchAppDelegate.swift
//  badminton score tracker Watch App
//
//  WKApplicationDelegate implementation for watchOS to catch and handle
//  CloudKit share acceptance events.
//

import WatchKit
import CloudKit

class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func userDidAcceptCloudKitShare(with cloudKitShareMetadata: CKShare.Metadata) {
        CloudKitSyncManager.shared.acceptShare(metadata: cloudKitShareMetadata)
    }
}
