//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc(OWSFakeStorageServiceManager)
public class FakeStorageServiceManager: NSObject, StorageServiceManagerProtocol {
    public func recordPendingDeletions(deletedGroupV1Ids: [Data]) {}

    public func recordPendingUpdates(updatedAccountIds: [AccountId]) {}
    public func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {}
    public func recordPendingUpdates(updatedGroupV1Ids: [Data]) {}
    public func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) {}
    public func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) {}
    public func recordPendingUpdates(groupModel: TSGroupModel) {}
    public func recordPendingLocalAccountUpdates() {}

    public func backupPendingChanges() {}
    public func restoreOrCreateManifestIfNecessary() -> AnyPromise { AnyPromise(Promise.value(())) }

    public func resetLocalData(transaction: SDSAnyWriteTransaction) {}
}
