//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalRingRTC

#if TESTABLE_BUILD

@objc(OWSFakeStorageServiceManager)
public class FakeStorageServiceManager: NSObject, StorageServiceManager {
    public func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiers) {}

    public func currentManifestVersion(tx: DBReadTransaction) -> UInt64 { 0 }
    public func currentManifestHasRecordIkm(tx: DBReadTransaction) -> Bool { false }

    public func recordPendingUpdates(updatedRecipientUniqueIds: [RecipientUniqueId]) {}
    public func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {}
    public func recordPendingUpdates(updatedGroupV2MasterKeys: [Data]) {}
    public func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) {}
    public func recordPendingUpdates(callLinkRootKeys: [CallLinkRootKey]) {}
    public func recordPendingLocalAccountUpdates() {}

    public func backupPendingChanges(authedDevice: AuthedDevice) {}

    public var restoreOrCreateManifestIfNecessaryMock: (AuthedDevice) -> Promise<Void> = { _ in .value(()) }

    public func restoreOrCreateManifestIfNecessary(authedDevice: AuthedDevice) -> Promise<Void> {
        return restoreOrCreateManifestIfNecessaryMock(authedDevice)
    }

    public func rotateManifest(mode: ManifestRotationMode, authedDevice: AuthedDevice) async throws {}

    public func waitForPendingRestores() -> Promise<Void> { Promise.value(()) }

    public func resetLocalData(transaction: DBWriteTransaction) {}
}

#endif
