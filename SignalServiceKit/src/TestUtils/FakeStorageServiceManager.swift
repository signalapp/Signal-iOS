//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSFakeStorageServiceManager)
class FakeStorageServiceManager: NSObject, StorageServiceManagerProtocol {
    func recordPendingDeletions(deletedIds: [AccountId]) {}
    func recordPendingDeletions(deletedAddresses: [SignalServiceAddress]) {}

    func recordPendingUpdates(updatedIds: [AccountId]) {}
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {}

    func backupPendingChanges() {}
    func restoreOrCreateManifestIfNecessary() {}
}
