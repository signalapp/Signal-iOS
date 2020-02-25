//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSFakeStorageServiceManager)
class FakeStorageServiceManager: NSObject, StorageServiceManagerProtocol {
    func recordPendingDeletions(deletedIds: [AccountId]) {}
    func recordPendingDeletions(deletedAddresses: [SignalServiceAddress]) {}
    func recordPendingDeletions(deletedGroupIds: [Data]) {}

    func recordPendingUpdates(updatedIds: [AccountId]) {}
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {}
    func recordPendingUpdates(updatedGroupIds: [Data]) {}

    func backupPendingChanges() {}
    func restoreOrCreateManifestIfNecessary() -> AnyPromise { AnyPromise(Promise.value(())) }

    func resetLocalData(transaction: SDSAnyWriteTransaction) {}
}
