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
    private static let allStorageServiceGroupMasterKeys = NewKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_All")

    // A list of the groups we need to try to restore. Values are serialized GroupV2Records.
    private static let storageServiceGroupsToRestore = NewKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_EnqueuedRecordForRestore")

    // A deprecated list of the groups we need to restore. Values are master keys.
    private static let legacyStorageServiceGroupsToRestore = NewKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_EnqueuedForRestore")

    // A list of the groups we failed to restore.
    //
    // Values are irrelevant (bools).
    private static let failedStorageServiceGroupMasterKeys = NewKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_Failed")

    static func isGroupKnownToStorageService(groupModel: TSGroupModelV2, transaction: DBReadTransaction) -> Bool {
        do {
            let masterKeyData = try groupModel.masterKey().serialize()
            let key = restoreGroupKey(forMasterKeyData: masterKeyData)
            return allStorageServiceGroupMasterKeys.fetchValue(Bool.self, forKey: key, tx: transaction) != nil
        } catch {
            owsFailDebug("Error: \(error)")
            return false
        }
    }

    static func enqueuedGroupRecordForRestore(
        masterKeyData: Data,
        transaction: DBReadTransaction,
    ) -> StorageServiceProtoGroupV2Record? {
        let key = restoreGroupKey(forMasterKeyData: masterKeyData)
        guard let recordData = storageServiceGroupsToRestore.fetchValue(Data.self, forKey: key, tx: transaction) else {
            return nil
        }
        return try? .init(serializedData: recordData)
    }

    static func enqueueGroupRestore(
        groupRecord: StorageServiceProtoGroupV2Record,
        transaction: DBWriteTransaction,
    ) {
        guard GroupMasterKey.isValid(groupRecord.masterKey) else {
            owsFailDebug("Invalid master key.")
            return
        }

        let key = restoreGroupKey(forMasterKeyData: groupRecord.masterKey)

        if allStorageServiceGroupMasterKeys.fetchValue(Bool.self, forKey: key, tx: transaction) == nil {
            allStorageServiceGroupMasterKeys.writeValue(true, forKey: key, tx: transaction)
        }

        guard failedStorageServiceGroupMasterKeys.fetchValue(Bool.self, forKey: key, tx: transaction) == nil else {
            // Past restore attempts failed in an unrecoverable way.
            return
        }

        guard let serializedData = try? groupRecord.serializedData() else {
            owsFailDebug("Can't restore group with unserializable record")
            return
        }

        // Clear any legacy restore info.
        legacyStorageServiceGroupsToRestore.removeValue(forKey: key, tx: transaction)

        // Store the record for restoration.
        storageServiceGroupsToRestore.writeValue(serializedData, forKey: key, tx: transaction)

        transaction.addSyncCompletion {
            self.enqueueRestoreGroupPass()
        }
    }

    private static func restoreGroupKey(forMasterKeyData masterKeyData: Data) -> String {
        return masterKeyData.hexadecimalString
    }

    private static func canProcessGroupRestore() async -> Bool {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        let reachabilityManager = SSKEnvironment.shared.reachabilityManagerRef

        let isMainAppAndActive = await CurrentAppContext().isMainAppAndActiveIsolated
        let isReachable = reachabilityManager.isReachable
        let isRegistered = tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered

        return (
            isMainAppAndActive
                && isReachable
                && isRegistered,
        )
    }

    private static let restoreTaskQueue = SerialTaskQueue()

    static func enqueueRestoreGroupPass() {
        restoreTaskQueue.enqueue {
            let shouldContinue = await tryToRestoreNextGroup()
            if shouldContinue {
                enqueueRestoreGroupPass()
            }
        }
    }

    private static func anyEnqueuedGroupRecord(transaction: DBReadTransaction) -> StorageServiceProtoGroupV2Record? {
        guard
            let randomKey = storageServiceGroupsToRestore.fetchKeys(tx: transaction).randomElement(),
            let serializedData = storageServiceGroupsToRestore.fetchValue(Data.self, forKey: randomKey, tx: transaction)
        else {
            return nil
        }
        return try? .init(serializedData: serializedData)
    }

    /// Processes & removes (up to) one group from the queue.
    ///
    /// - Returns: True if there is another group to process immediately. False
    /// if there are no more groups to process or the app can't process updates
    /// (eg because the device is in Airplane Mode).
    private static func tryToRestoreNextGroup() async -> Bool {
        guard await canProcessGroupRestore() else {
            return false
        }

        let (masterKeyData, groupRecord) = SSKEnvironment.shared.databaseStorageRef.read { transaction -> (Data?, StorageServiceProtoGroupV2Record?) in
            if let groupRecord = self.anyEnqueuedGroupRecord(transaction: transaction) {
                return (groupRecord.masterKey, groupRecord)
            } else if
                // Make sure we don't have any legacy master key only enqueued groups
                let randomKey = legacyStorageServiceGroupsToRestore.fetchKeys(tx: transaction).randomElement(),
                let legacyMasterKey = legacyStorageServiceGroupsToRestore.fetchValue(Data.self, forKey: randomKey, tx: transaction)
            {
                return (legacyMasterKey, nil)
            } else {
                return (nil, nil)
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
                self.storageServiceGroupsToRestore.removeValue(forKey: key, tx: transaction)
                self.legacyStorageServiceGroupsToRestore.removeValue(forKey: key, tx: transaction)
                self.failedStorageServiceGroupMasterKeys.writeValue(true, forKey: key, tx: transaction)
            }
        }

        let markAsComplete = {
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
                let isPrimaryDevice = DependenciesBridge.shared.tsAccountManager
                    .registrationState(tx: tx).isRegisteredPrimaryDevice

                // Now that the thread exists, re-apply the pending group record from
                // storage service.
                if let groupRecord {
                    let recordUpdater = StorageServiceGroupV2RecordUpdater(
                        authedAccount: .implicit(),
                        isPrimaryDevice: isPrimaryDevice,
                        avatarDefaultColorManager: DependenciesBridge.shared.avatarDefaultColorManager,
                        blockingManager: SSKEnvironment.shared.blockingManagerRef,
                        groupsV2: SSKEnvironment.shared.groupsV2Ref,
                        profileManager: SSKEnvironment.shared.profileManagerRef,
                    )
                    _ = recordUpdater.mergeRecord(groupRecord, transaction: tx)
                }

                self.storageServiceGroupsToRestore.removeValue(forKey: key, tx: tx)
                self.legacyStorageServiceGroupsToRestore.removeValue(forKey: key, tx: tx)
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
            return TSGroupThread.fetchThread(forGroupId: groupContextInfo.groupId, tx: transaction) != nil
        }
        if isGroupInDatabase {
            // No work to be done, group already in database.
            await markAsComplete()
            return true
        }

        let isGroupBlocked = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return SSKEnvironment.shared.blockingManagerRef.isGroupIdBlocked(groupContextInfo.groupId, transaction: tx)
        }
        if isGroupBlocked {
            Logger.warn("Failing because group is blocked")
            await markAsFailed()
            return true
        }

        do {
            try await SSKEnvironment.shared.groupV2UpdatesRef.fetchAndApplyCurrentGroupV2SnapshotFromService(
                secretParams: groupContextInfo.groupSecretParams,
                spamReportingMetadata: .learnedByLocallyInitatedRefresh,
                options: [.throttle],
                skipTerminatedGroup: true,
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
        } catch GroupsV2Error.skipRestoringTerminatedGroup {
            Logger.warn("Failing because group has terminated")
            await markAsFailed()
            return true
        } catch {
            Logger.warn("Failed to restore group! \(error)")
            await markAsFailed()
            return true
        }
    }
}
