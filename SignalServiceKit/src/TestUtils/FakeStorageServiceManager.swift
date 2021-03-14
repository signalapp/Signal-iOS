//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSFakeStorageServiceManager)
public class FakeStorageServiceManager: NSObject, StorageServiceManagerProtocol {
    public func recordPendingDeletions(deletedAccountIds: [AccountId]) {}
    public func recordPendingDeletions(deletedAddresses: [SignalServiceAddress]) {}
    public func recordPendingDeletions(deletedGroupV1Ids: [Data]) {}
    public func recordPendingDeletions(deletedGroupV2MasterKeys: [Data]) {}

    public func recordPendingUpdates(updatedAccountIds: [AccountId]) {}
    public func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {}
    public func recordPendingUpdates(updatedGroupV1Ids: [Data]) {}
    public func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) {}
    public func recordPendingUpdates(groupModel: TSGroupModel) {}
    public func recordPendingLocalAccountUpdates() {}

    public func backupPendingChanges() {}
    public func restoreOrCreateManifestIfNecessary() -> AnyPromise { AnyPromise(Promise.value(())) }

    public func resetLocalData(transaction: SDSAnyWriteTransaction) {}
}
