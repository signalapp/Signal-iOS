//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSFakeStorageServiceManager)
class FakeStorageServiceManager: NSObject, StorageServiceManagerProtocol {
    func recordPendingDeletions(deletedAccountIds: [AccountId]) {}
    func recordPendingDeletions(deletedAddresses: [SignalServiceAddress]) {}
    func recordPendingDeletions(deletedGroupV1Ids: [Data]) {}
    func recordPendingDeletions(deletedGroupV2MasterKeys: [Data]) {}

    func recordPendingUpdates(updatedAccountIds: [AccountId]) {}
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {}
    func recordPendingUpdates(updatedGroupV1Ids: [Data]) {}
    func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) {}
    func recordPendingUpdates(groupModel: TSGroupModel) {}
    func recordPendingLocalAccountUpdates() {}

    func backupPendingChanges() {}
    func restoreOrCreateManifestIfNecessary() -> AnyPromise { AnyPromise(Promise.value(())) }

    func resetLocalData(transaction: SDSAnyWriteTransaction) {}
}
