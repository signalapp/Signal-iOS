//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit

public extension GroupsV2Impl {

    // MARK: - Dependencies

    private static var tsAccountManager: TSAccountManager {
        return TSAccountManager.shared()
    }

    private static var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private static var groupV2Updates: GroupV2UpdatesSwift {
        return SSKEnvironment.shared.groupV2Updates as! GroupV2UpdatesSwift
    }

    private static var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    private static var reachabilityManager: SSKReachabilityManager {
        return SSKEnvironment.shared.reachabilityManager
    }

    // MARK: - Restore Groups

    // A list of all groups we've learned of from the storage service.
    //
    // Values are irrelevant (bools).
    private static let groupsFromStorageService_All = SDSKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_All")

    // A list of the groups we need to try to restore.
    //
    // Values are master keys.
    private static let groupsFromStorageService_EnqueuedForRestore = SDSKeyValueStore(collection: "GroupsV2Impl.groupsFromStorageService_EnqueuedForRestore")

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

    static func enqueueGroupRestore(masterKeyData: Data,
                                    transaction: SDSAnyWriteTransaction) {

        guard groupsV2.isValidGroupV2MasterKey(masterKeyData) else {
            owsFailDebug("Invalid master key.")
            return
        }

        let key = restoreGroupKey(forMasterKeyData: masterKeyData)

        if !groupsFromStorageService_All.hasValue(forKey: key, transaction: transaction) {
            groupsFromStorageService_All.setBool(true, key: key, transaction: transaction)
        }

        guard !groupsFromStorageService_Failed.hasValue(forKey: key, transaction: transaction) else {
            // Past restore attempts failed in an unrecoverable way.
            return
        }
        guard !groupsFromStorageService_EnqueuedForRestore.hasValue(forKey: key, transaction: transaction) else {
            // Already enqueued for restore.
            return
        }

        // Mark as needing restore.
        groupsFromStorageService_EnqueuedForRestore.setData(masterKeyData, key: key, transaction: transaction)

        transaction.addAsyncCompletion {
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

    // Every invocation of this method should remove (up to) one group from the queue.
    //
    // This method should only be called on restoreGroupsOperationQueue.
    private static func tryToRestoreNextGroup() -> Promise<RestoreGroupOutcome> {
        guard canProcessGroupRestore else {
            return Promise.value(.cantProcess)
        }
        return Promise<RestoreGroupOutcome> { resolver in
            DispatchQueue.global().async {
                guard let masterKeyData = (self.databaseStorage.read { transaction in
                    groupsFromStorageService_EnqueuedForRestore.anyDataValue(transaction: transaction)
                }) else {
                    return resolver.fulfill(.emptyQueue)
                }
                let key = self.restoreGroupKey(forMasterKeyData: masterKeyData)

                // If we have an unrecoverable failure, remove the key
                // from the store so that we stop retrying until the
                // next time that storage service prods us to try.
                let markAsFailed = {
                    databaseStorage.write { transaction in
                        self.groupsFromStorageService_EnqueuedForRestore.removeValue(forKey: key, transaction: transaction)
                        self.groupsFromStorageService_Failed.setBool(true, key: key, transaction: transaction)
                    }
                }
                let markAsComplete = {
                    databaseStorage.write { transaction in
                        self.groupsFromStorageService_EnqueuedForRestore.removeValue(forKey: key, transaction: transaction)
                    }
                }

                let groupContextInfo: GroupV2ContextInfo
                do {
                    groupContextInfo = try groupsV2.groupV2ContextInfo(forMasterKeyData: masterKeyData)
                } catch {
                    owsFailDebug("Error: \(error)")
                    markAsFailed()
                    return resolver.fulfill(.unretryableFailure)
                }

                let isGroupInDatabase = self.databaseStorage.read { transaction in
                    TSGroupThread.fetch(groupId: groupContextInfo.groupId, transaction: transaction) != nil
                }
                guard !isGroupInDatabase else {
                    // No work to be done, group already in database.
                    markAsComplete()
                    return resolver.fulfill(.success)
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
                    resolver.fulfill(.success)
                }.catch { error in
                    if IsNetworkConnectivityFailure(error) {
                        Logger.warn("Error: \(error)")
                        return resolver.fulfill(.retryableFailure)
                    } else {
                        switch error {
                        case GroupsV2Error.localUserNotInGroup:
                            Logger.warn("Error: \(error)")
                        default:
                            owsFailDebug("Error: \(error)")
                        }
                        markAsFailed()
                        return resolver.fulfill(.unretryableFailure)
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
            }.done(on: .global()) { outcome in
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
            }.catch(on: .global()) { (error) in
                // tryToRestoreNextGroup() should never fail.
                owsFailDebug("Group restore failed: \(error)")
                self.reportError(error.asUnretryableError)
            }
        }

        public override func didFail(error: Error) {
            Logger.error("failed with error: \(error)")
        }
    }
}
