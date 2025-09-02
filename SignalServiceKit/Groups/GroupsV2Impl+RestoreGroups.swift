//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public extension GroupsV2Impl {

    // MARK: - Restore Groups

    // A list of all groups we've learned of from the storage service.
    //
    // Values are irrelevant (bools).
    private static let allStorageServiceGroupMasterKeys = KeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_All")

    // A list of the groups we need to try to restore. Values are serialized GroupV2Records.
    private static let storageServiceGroupsToRestore = KeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_EnqueuedRecordForRestore")

    // A deprecated list of the groups we need to restore. Values are master keys.
    private static let legacyStorageServiceGroupsToRestore = KeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_EnqueuedForRestore")

    // A list of the groups we failed to restore.
    //
    // Values are irrelevant (bools).
    private static let failedStorageServiceGroupMasterKeys = KeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_Failed")

    static func isGroupKnownToStorageService(groupModel: TSGroupModelV2, transaction: DBReadTransaction) -> Bool {
        do {
            let masterKeyData = try groupModel.masterKey().serialize()
            let key = restoreGroupKey(forMasterKeyData: masterKeyData)
            return allStorageServiceGroupMasterKeys.hasValue(key, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return false
        }
    }

    static func enqueuedGroupRecordForRestore(
        masterKeyData: Data,
        transaction: DBReadTransaction
    ) -> StorageServiceProtoGroupV2Record? {
        let key = restoreGroupKey(forMasterKeyData: masterKeyData)
        guard let recordData = storageServiceGroupsToRestore.getData(key, transaction: transaction) else {
            return nil
        }
        return try? .init(serializedData: recordData)
    }

    static func enqueueGroupRestore(
        groupRecord: StorageServiceProtoGroupV2Record,
        account: AuthedAccount,
        transaction: DBWriteTransaction
    ) {
        guard GroupMasterKey.isValid(groupRecord.masterKey) else {
            owsFailDebug("Invalid master key.")
            return
        }

        let key = restoreGroupKey(forMasterKeyData: groupRecord.masterKey)

        if !allStorageServiceGroupMasterKeys.hasValue(key, transaction: transaction) {
            allStorageServiceGroupMasterKeys.setBool(true, key: key, transaction: transaction)
        }

        guard !failedStorageServiceGroupMasterKeys.hasValue(key, transaction: transaction) else {
            // Past restore attempts failed in an unrecoverable way.
            return
        }

        guard let serializedData = try? groupRecord.serializedData() else {
            owsFailDebug("Can't restore group with unserializable record")
            return
        }

        // Clear any legacy restore info.
        legacyStorageServiceGroupsToRestore.removeValue(forKey: key, transaction: transaction)

        // Store the record for restoration.
        storageServiceGroupsToRestore.setData(serializedData, key: key, transaction: transaction)

        transaction.addSyncCompletion {
            self.enqueueRestoreGroupPass(authedAccount: account)
        }
    }

    private static func restoreGroupKey(forMasterKeyData masterKeyData: Data) -> String {
        return masterKeyData.hexadecimalString
    }

    private static func canProcessGroupRestore(authedAccount: AuthedAccount) async -> Bool {
        return await (
            self.isMainAppAndActive()
            && SSKEnvironment.shared.reachabilityManagerRef.isReachable
            && isRegisteredWithSneakyTransaction(authedAccount: authedAccount)
        )
    }

    @MainActor
    private static func isMainAppAndActive() -> Bool {
        return CurrentAppContext().isMainAppAndActive
    }

    private static func isRegisteredWithSneakyTransaction(authedAccount: AuthedAccount) -> Bool {
        switch authedAccount.info {
        case .explicit:
            return false
        case .implicit:
            return DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered
        }
    }

    private struct State {
        var inProgress = false
        var pendingAuthedAccount: AuthedAccount?

        mutating func startIfNeeded(authedAccount: AuthedAccount) -> AuthedAccount? {
            if self.inProgress {
                // Already started, so queue up the next one for whenever it finishes.
                self.pendingAuthedAccount = self.pendingAuthedAccount?.orIfImplicitUse(authedAccount) ?? authedAccount
                return nil
            } else {
                self.inProgress = true
                return authedAccount
            }
        }

        mutating func continueIfNeeded(hasMore: Bool, authedAccount: AuthedAccount) -> AuthedAccount? {
            assert(self.inProgress)
            if hasMore {
                self.pendingAuthedAccount = self.pendingAuthedAccount?.orIfImplicitUse(authedAccount) ?? authedAccount
            }
            let result = self.pendingAuthedAccount
            self.pendingAuthedAccount = nil
            self.inProgress = (result != nil)
            return result
        }
    }

    private static let state = AtomicValue<State>(State(), lock: .init())

    static func enqueueRestoreGroupPass(authedAccount: AuthedAccount) {
        let authedAccountToStart = self.state.update { $0.startIfNeeded(authedAccount: authedAccount) }
        Task { await startRestoreGroupPass(authedAccount: authedAccountToStart) }
    }

    private static func startRestoreGroupPass(authedAccount initialAuthedAccount: AuthedAccount?) async {
        var nextAuthedAccount = initialAuthedAccount
        while let currentAuthedAccount = nextAuthedAccount {
            let hasMore = await tryToRestoreNextGroup(authedAccount: currentAuthedAccount)
            nextAuthedAccount = self.state.update { $0.continueIfNeeded(hasMore: hasMore, authedAccount: currentAuthedAccount) }
        }
    }

    private static func anyEnqueuedGroupRecord(transaction: DBReadTransaction) -> StorageServiceProtoGroupV2Record? {
        guard let serializedData = storageServiceGroupsToRestore.anyDataValue(transaction: transaction) else {
            return nil
        }
        return try? .init(serializedData: serializedData)
    }

    /// Processes & removes (up to) one group from the queue.
    ///
    /// - Returns: True if there is another group to process immediately. False
    /// if there are no more groups to process or the app can't process updates
    /// (eg because the device is in Airplane Mode).
    private static func tryToRestoreNextGroup(authedAccount: AuthedAccount) async -> Bool {
        guard await canProcessGroupRestore(authedAccount: authedAccount) else {
            return false
        }

        let (masterKeyData, groupRecord) = SSKEnvironment.shared.databaseStorageRef.read { transaction -> (Data?, StorageServiceProtoGroupV2Record?) in
            if let groupRecord = self.anyEnqueuedGroupRecord(transaction: transaction) {
                return (groupRecord.masterKey, groupRecord)
            } else {
                // Make sure we don't have any legacy master key only enqueued groups
                return (legacyStorageServiceGroupsToRestore.anyDataValue(transaction: transaction), nil)
            }
        }

        guard let masterKeyData else {
            return false
        }

        let key = self.restoreGroupKey(forMasterKeyData: masterKeyData)

        // If we have an unrecoverable failure, remove the key from the store so
        // that we stop retrying until storage service asks us to try again.
        let markAsFailed = {
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                self.storageServiceGroupsToRestore.removeValue(forKey: key, transaction: transaction)
                self.legacyStorageServiceGroupsToRestore.removeValue(forKey: key, transaction: transaction)
                self.failedStorageServiceGroupMasterKeys.setBool(true, key: key, transaction: transaction)
            }
        }

        let markAsComplete = {
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                let isPrimaryDevice = DependenciesBridge.shared.tsAccountManager
                    .registrationState(tx: tx).isRegisteredPrimaryDevice

                // Now that the thread exists, re-apply the pending group record from
                // storage service.
                if var groupRecord {
                    // First apply any migrations
                    if StorageServiceUnknownFieldMigrator.shouldInterceptRemoteManifestBeforeMerging(tx: tx) {
                        groupRecord = StorageServiceUnknownFieldMigrator.interceptRemoteManifestBeforeMerging(
                            record: groupRecord,
                            tx: tx
                        )
                    }

                    let recordUpdater = StorageServiceGroupV2RecordUpdater(
                        authedAccount: authedAccount,
                        isPrimaryDevice: isPrimaryDevice,
                        avatarDefaultColorManager: DependenciesBridge.shared.avatarDefaultColorManager,
                        blockingManager: SSKEnvironment.shared.blockingManagerRef,
                        groupsV2: SSKEnvironment.shared.groupsV2Ref,
                        profileManager: SSKEnvironment.shared.profileManagerRef
                    )
                    _ = recordUpdater.mergeRecord(groupRecord, transaction: tx)
                }

                self.storageServiceGroupsToRestore.removeValue(forKey: key, transaction: tx)
                self.legacyStorageServiceGroupsToRestore.removeValue(forKey: key, transaction: tx)
            }
        }

        let groupContextInfo: GroupV2ContextInfo
        do {
            groupContextInfo = try GroupV2ContextInfo.deriveFrom(masterKeyData: masterKeyData)
        } catch {
            owsFailDebug("Error: \(error)")
            await markAsFailed()
            return true
        }

        let isGroupInDatabase = SSKEnvironment.shared.databaseStorageRef.read { transaction in
            TSGroupThread.fetch(forGroupId: groupContextInfo.groupId, tx: transaction) != nil
        }
        if isGroupInDatabase {
            // No work to be done, group already in database.
            await markAsComplete()
            return true
        }

        // This will try to update the group using incremental "changes" but
        // failover to using a "snapshot".
        do {
            try await SSKEnvironment.shared.groupV2UpdatesRef.refreshGroup(
                secretParams: groupContextInfo.groupSecretParams,
                options: [.throttle]
            )
            await markAsComplete()
            return true
        } catch where error.isNetworkFailureOrTimeout {
            Logger.warn("Error: \(error)")
            return false
        } catch GroupsV2Error.localUserNotInGroup {
            Logger.warn("Failing because we're not a group member")
            await markAsFailed()
            return true
        } catch {
            owsFailDebug("Error: \(error)")
            await markAsFailed()
            return true
        }
    }
}
