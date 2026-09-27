//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

import Foundation
public import LibSignalClient
public import SignalRingRTC

public class FakeStorageServiceManager: StorageServiceManager {
    public func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiers) {}
    public func registerForCron(_ cron: Cron) {}

    public func currentManifestVersion(tx: DBReadTransaction) -> UInt64 { 0 }
    public func currentManifestHasRecordIkm(tx: DBReadTransaction) -> Bool { false }

    public func recordPendingUpdates(updatedRecipientUniqueIds: [RecipientUniqueId]) {}
    public func recordPendingUpdates(updatedAddresses: [SignalServiceAddress]) {}
    public func recordPendingUpdates(updatedGroupV2MasterKeys: [GroupMasterKey]) {}
    public func recordPendingInsertions(forGroupMasterKeys groupMasterKeys: [GroupMasterKey]) {}
    public func recordPendingUpdates(updatedStoryDistributionListIds: [Data]) {}
    public func recordPendingUpdates(callLinkRootKeys: [CallLinkRootKey]) {}
    public func recordPendingLocalAccountUpdates() {}

    public func backupPendingChanges(authedAccount: AuthedAccount) {}

    public var restoreOrCreateManifestIfNecessaryMock: (AuthedAccount, StorageService.MasterKeySource) -> Promise<Void> = { _, _ in .value(()) }

    public func restoreOrCreateManifestIfNecessary(authedAccount: AuthedAccount, masterKeySource: StorageService.MasterKeySource) -> Promise<Void> {
        return restoreOrCreateManifestIfNecessaryMock(authedAccount, masterKeySource)
    }

    public func rotateManifest(mode: ManifestRotationMode, authedAccount: AuthedAccount) async throws {}

    public func waitForPendingRestores() async throws { }
    public func waitForSteadyState() async throws(CancellationError) { }

    public func resetLocalData(transaction: DBWriteTransaction) {}
}

#endif
