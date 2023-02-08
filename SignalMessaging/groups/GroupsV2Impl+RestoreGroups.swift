//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public extension GroupsV2Impl {

    // MARK: - Restore Groups

    // A list of all groups we've learned of from the storage service.
    //
    // Values are irrelevant (bools).
    private static let groupsFromStorageService_All = SDSKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_All")

    // A list of the groups we need to try to restore. Values are serialized GroupV2Records.
    private static let groupsFromStorageService_EnqueuedRecordForRestore = SDSKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_EnqueuedRecordForRestore")

    // A deprecated list of the groups we need to restore. Values are master keys.
    // TODO: This can be deleted Jan 2023
    private static let groupsFromStorageService_LegacyEnqueuedForRestore = SDSKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_EnqueuedForRestore")

    // A list of the groups we failed to restore.
    //
    // Values are irrelevant (bools).
    private static let groupsFromStorageService_Failed = SDSKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_Failed")

    private static let restoreGroupsOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.name = "restoreGroupsOperationQueue"
        return queue
    }()

    static func isGroupKnownToStorageService(groupModel: TSGroupModelV2,
                                             transaction: SDSAnyReadTransaction) -> Bool {
        do {
            let masterKeyData = try groupsV2.masterKeyData(forGroupModel: groupModel)
            let key = restoreGroupKey(forMasterKeyData: masterKeyData)
            return groupsFromStorageService_All.hasValue(forKey: key, transaction: transaction)
        } catch {
            owsFailDebug("Error: \(error)")
            return false
        }
    }

    static func enqueuedGroupRecordForRestore(
        masterKeyData: Data,
        transaction: SDSAnyReadTransaction
    ) -> StorageServiceProtoGroupV2Record? {
        let key = restoreGroupKey(forMasterKeyData: masterKeyData)
        guard let recordData = groupsFromStorageService_EnqueuedRecordForRestore.getData(key, transaction: transaction) else { return nil }
        return try? .init(serializedData: recordData)
    }

    static func enqueueGroupRestore(
        groupRecord: StorageServiceProtoGroupV2Record,
        transaction: SDSAnyWriteTransaction
    ) {

        guard groupsV2.isValidGroupV2MasterKey(groupRecord.masterKey) else {
            owsFailDebug("Invalid master key.")
            return
        }

        let key = restoreGroupKey(forMasterKeyData: groupRecord.masterKey)

        if !groupsFromStorageService_All.hasValue(forKey: key, transaction: transaction) {
            groupsFromStorageService_All.setBool(true, key: key, transaction: transaction)
        }

        guard !groupsFromStorageService_Failed.hasValue(forKey: key, transaction: transaction) else {
            // Past restore attempts failed in an unrecoverable way.
            return
        }

        guard let serializedData = try? groupRecord.serializedData() else {
            owsFailDebug("Can't restore group with unserializable record")
            return
        }

        // Clear any legacy restore info.
        groupsFromStorageService_LegacyEnqueuedForRestore.removeValue(forKey: key, transaction: transaction)

        // Store the record for restoration.
        groupsFromStorageService_EnqueuedRecordForRestore.setData(serializedData, key: key, transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            self.enqueueRestoreGroupPass()
        }
    }

    private static func restoreGroupKey(forMasterKeyData masterKeyData: Data) -> String {
        return masterKeyData.hexadecimalString
    }

    private static var canProcessGroupRestore: Bool {
        // CurrentAppContext().isMainAppAndActive should
        // only be called on the main thread.
        guard CurrentAppContext().isMainApp,
            CurrentAppContext().isAppForegroundAndActive() else {
            return false
        }
        guard reachabilityManager.isReachable else {
            return false
        }
        guard tsAccountManager.isRegisteredAndReady else {
            return false
        }
        return true
    }

    static func enqueueRestoreGroupPass() {
        guard canProcessGroupRestore else {
            return
        }
        let operation = RestoreGroupOperation()
        GroupsV2Impl.restoreGroupsOperationQueue.addOperation(operation)
    }

    fileprivate enum RestoreGroupOutcome: CustomStringConvertible {
        case success
        case unretryableFailure
        case retryableFailure
        case emptyQueue
        case cantProcess

        // MARK: - CustomStringConvertible

        public var description: String {
            switch self {
            case .success:
                return "success"
            case .unretryableFailure:
                return "unretryableFailure"
            case .retryableFailure:
                return "retryableFailure"
            case .emptyQueue:
                return "emptyQueue"
            case .cantProcess:
                return "cantProcess"
            }
        }
    }

    private static func anyEnqueuedGroupRecord(transaction: SDSAnyReadTransaction) -> StorageServiceProtoGroupV2Record? {
        guard let serializedData = groupsFromStorageService_EnqueuedRecordForRestore.anyDataValue(transaction: transaction) else { return nil }
        return try? .init(serializedData: serializedData)
    }

    // Every invocation of this method should remove (up to) one group from the queue.
    //
    // This method should only be called on restoreGroupsOperationQueue.
    private static func tryToRestoreNextGroup() -> Promise<RestoreGroupOutcome> {
        guard canProcessGroupRestore else {
            return Promise.value(.cantProcess)
        }
        return Promise<RestoreGroupOutcome> { future in
            DispatchQueue.global().async {
                let (masterKeyData, groupRecord) = self.databaseStorage.read { transaction -> (Data?, StorageServiceProtoGroupV2Record?) in
                    if let groupRecord = self.anyEnqueuedGroupRecord(transaction: transaction) {
                        return (groupRecord.masterKey, groupRecord)
                    } else {
                        // Make sure we don't have any legacy master key only enqueued groups
                        return (groupsFromStorageService_LegacyEnqueuedForRestore.anyDataValue(transaction: transaction), nil)
                    }
                }

                guard let masterKeyData = masterKeyData else {
                    return future.resolve(.emptyQueue)
                }
                let key = self.restoreGroupKey(forMasterKeyData: masterKeyData)

                // If we have an unrecoverable failure, remove the key
                // from the store so that we stop retrying until the
                // next time that storage service prods us to try.
                let markAsFailed = {
                    databaseStorage.write { transaction in
                        self.groupsFromStorageService_EnqueuedRecordForRestore.removeValue(forKey: key, transaction: transaction)
                        self.groupsFromStorageService_LegacyEnqueuedForRestore.removeValue(forKey: key, transaction: transaction)
                        self.groupsFromStorageService_Failed.setBool(true, key: key, transaction: transaction)
                    }
                }
                let markAsComplete = {
                    databaseStorage.write { transaction in
                        // Now that the thread exists, re-apply the pending group record from storage service.
                        _ = groupRecord?.mergeWithLocalGroup(transaction: transaction)

                        self.groupsFromStorageService_EnqueuedRecordForRestore.removeValue(forKey: key, transaction: transaction)
                        self.groupsFromStorageService_LegacyEnqueuedForRestore.removeValue(forKey: key, transaction: transaction)
                    }
                }

                let groupContextInfo: GroupV2ContextInfo
                do {
                    groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKeyData)
                } catch {
                    owsFailDebug("Error: \(error)")
                    markAsFailed()
                    return future.resolve(.unretryableFailure)
                }

                let isGroupInDatabase = self.databaseStorage.read { transaction in
                    TSGroupThread.fetch(groupId: groupContextInfo.groupId, transaction: transaction) != nil
                }
                guard !isGroupInDatabase else {
                    // No work to be done, group already in database.
                    markAsComplete()
                    return future.resolve(.success)
                }

                // This will try to update the group using incremental "changes" but
                // failover to using a "snapshot".
                let groupUpdateMode = GroupUpdateMode.upToCurrentRevisionAfterMessageProcessWithThrottling
                firstly {
                    self.groupV2Updates.tryToRefreshV2GroupThread(groupId: groupContextInfo.groupId,
                                                                  groupSecretParamsData: groupContextInfo.groupSecretParamsData,
                                                                  groupUpdateMode: groupUpdateMode)
                }.done { _ in
                    Logger.verbose("Update succeeded.")
                    markAsComplete()
                    future.resolve(.success)
                }.catch { error in
                    if error.isNetworkConnectivityFailure {
                        Logger.warn("Error: \(error)")
                        return future.resolve(.retryableFailure)
                    } else {
                        switch error {
                        case GroupsV2Error.localUserNotInGroup:
                            Logger.warn("Error: \(error)")
                        default:
                            owsFailDebug("Error: \(error)")
                        }
                        markAsFailed()
                        return future.resolve(.unretryableFailure)
                    }
                }
            }
        }
    }

    // MARK: -

    private class RestoreGroupOperation: OWSOperation {

        required override init() {
            super.init()
        }

        public override func run() {
            firstly {
                GroupsV2Impl.tryToRestoreNextGroup()
            }.done(on: DispatchQueue.global()) { outcome in
                Logger.verbose("Group restore complete.")

                switch outcome {
                case .success, .unretryableFailure:
                    // Continue draining queue.
                    GroupsV2Impl.enqueueRestoreGroupPass()
                case .retryableFailure:
                    // Pause processing for now.
                    // Presumably network failures are preventing restores.
                    break
                case .emptyQueue, .cantProcess:
                    // Stop processing.
                    break
                }
                self.reportSuccess()
            }.catch(on: DispatchQueue.global()) { (error) in
                // tryToRestoreNextGroup() should never fail.
                owsFailDebug("Group restore failed: \(error)")
                self.reportError(SSKUnretryableError.restoreGroupFailed)
            }
        }

        public override func didFail(error: Error) {
            Logger.error("failed with error: \(error)")
        }
    }
}
