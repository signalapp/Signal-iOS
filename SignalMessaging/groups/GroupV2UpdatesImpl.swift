//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import ZKGroup

@objc
public class GroupV2UpdatesImpl: NSObject, GroupV2Updates, GroupV2UpdatesSwift {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var messageProcessing: MessageProcessing {
        return SSKEnvironment.shared.messageProcessing
    }

    private var groupsV2: GroupsV2 {
        return SSKEnvironment.shared.groupsV2
    }

    // MARK: -

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: -

    private let serialQueue = DispatchQueue(label: "GroupV2UpdatesImpl")

    // This struct should only be accessed on serialQueue.
    private struct RefreshState {
        private var lastSuccessfulRefreshMap = [Data: Date]()

        func lastSuccessfulRefreshDate(forGroupId  groupId: Data) -> Date? {
            return lastSuccessfulRefreshMap[groupId]
        }

        mutating func groupRefreshDidSucceed(forGroupId groupId: Data) {
            lastSuccessfulRefreshMap[groupId] = Date()
        }

        mutating func groupRefreshDidFail(forGroupId groupId: Data, error: Error) {
            // Do nothing.
        }
    }

    // These properties should only be accessed on serialQueue.
    private let upToSpecificRevisionImmediatelyRefreshState = RefreshState()
    private let upToCurrentRevisionAfterMessageProcessWithThrottlingRefreshState = RefreshState()

    private func refreshState(for groupUpdateMode: GroupUpdateMode) -> RefreshState {
        assertOnQueue(serialQueue)

        switch groupUpdateMode {
        case .upToSpecificRevisionImmediately:
            return upToSpecificRevisionImmediatelyRefreshState
        case .upToCurrentRevisionAfterMessageProcessWithThrottling:
            return upToCurrentRevisionAfterMessageProcessWithThrottlingRefreshState
        }
    }

    private func shouldThrottle(for groupUpdateMode: GroupUpdateMode) -> Bool {
        assertOnQueue(serialQueue)

        switch groupUpdateMode {
        case .upToSpecificRevisionImmediately:
            return false
        case .upToCurrentRevisionAfterMessageProcessWithThrottling:
            return true
        }
    }

    // MARK: -

    @objc
    public func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessWithThrottling(_ groupThread: TSGroupThread) {
        let groupUpdateMode = GroupUpdateMode.upToCurrentRevisionAfterMessageProcessWithThrottling
        tryToRefreshV2GroupThreadWithThrottling(groupThread, groupUpdateMode: groupUpdateMode)
            .retainUntilComplete()
    }

    @objc
    public func tryToRefreshV2GroupUpToSpecificRevisionImmediately(_ groupThread: TSGroupThread,
                                                                   upToRevision: UInt32) {
        let groupUpdateMode = GroupUpdateMode.upToSpecificRevisionImmediately(upToRevision: upToRevision)
        tryToRefreshV2GroupThreadWithThrottling(groupThread, groupUpdateMode: groupUpdateMode)
            .retainUntilComplete()
    }

    private func tryToRefreshV2GroupThreadWithThrottling(_ groupThread: TSGroupThread,
                                                         groupUpdateMode: GroupUpdateMode) -> Promise<Void> {
        let groupModel = groupThread.groupModel
        guard groupModel.groupsVersion == .V2 else {
            return Promise.value(())
        }
        let groupId = groupModel.groupId
        guard let groupSecretParamsData = groupModel.groupSecretParamsData,
            groupSecretParamsData.count > 0 else {
                return Promise(error: OWSAssertionError("Missing groupSecretParamsData."))
        }
        return tryToRefreshV2GroupThreadWithThrottling(groupId: groupId,
                                                       groupSecretParamsData: groupSecretParamsData,
                                                       groupUpdateMode: groupUpdateMode)
    }

    public func tryToRefreshV2GroupThreadWithThrottling(groupId: Data,
                                                        groupSecretParamsData: Data,
                                                        groupUpdateMode: GroupUpdateMode) -> Promise<Void> {

        let isThrottled = serialQueue.sync { () -> Bool in
            guard self.shouldThrottle(for: groupUpdateMode) else {
                return false
            }
            let refreshState = self.refreshState(for: groupUpdateMode)
            guard let lastSuccessfulRefreshDate = refreshState.lastSuccessfulRefreshDate(forGroupId: groupId) else {
                return false
            }
            // Don't auto-refresh more often than once every N minutes.
            let refreshFrequency: TimeInterval = kMinuteInterval * 5
            return abs(lastSuccessfulRefreshDate.timeIntervalSinceNow) > refreshFrequency
        }

        guard !isThrottled else {
            Logger.verbose("Skipping redundant v2 group refresh.")
            return Promise.value(())
        }

        let operation = GroupV2UpdateOperation(groupV2Updates: self, groupSecretParamsData: groupSecretParamsData, groupUpdateMode: groupUpdateMode)
        operation.promise.done(on: .global()) { _ in
            Logger.verbose("Group refresh succeeded.")

            self.serialQueue.sync {
                var refreshState = self.refreshState(for: groupUpdateMode)
                refreshState.groupRefreshDidSucceed(forGroupId: groupId)
            }
        }.catch(on: .global()) { error in
            Logger.verbose("Group refresh failed: \(error).")
        }.retainUntilComplete()
        operationQueue.addOperation(operation)
        return operation.promise
    }

    let operationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "GroupV2UpdatesImpl"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    private class GroupV2UpdateOperation: OWSOperation {
        let groupV2Updates: GroupV2UpdatesImpl
        let groupSecretParamsData: Data
        let groupUpdateMode: GroupUpdateMode

        let promise: Promise<Void>
        let resolver: Resolver<Void>

        // MARK: -

        required init(groupV2Updates: GroupV2UpdatesImpl,
                      groupSecretParamsData: Data,
                      groupUpdateMode: GroupUpdateMode) {
            self.groupV2Updates = groupV2Updates
            self.groupSecretParamsData = groupSecretParamsData
            self.groupUpdateMode = groupUpdateMode

            let (promise, resolver) = Promise<Void>.pending()
            self.promise = promise
            self.resolver = resolver

            super.init()

            self.remainingRetries = 3
        }

        // MARK: -

        public override func run() {
            firstly {
                groupV2Updates.refreshGroupFromService(groupSecretParamsData: groupSecretParamsData,
                                                       groupUpdateMode: groupUpdateMode)
            }.done(on: .global()) { _ in
                Logger.verbose("Group refresh succeeded.")

                self.reportSuccess()
            }.catch(on: .global()) { (error) in
                // GroupsV2 TODO: Only fail if non-network error.
                owsFailDebug("Group refresh failed: \(error)")

                self.reportError(withUndefinedRetry: error)
            }.retainUntilComplete()
        }

        public override func didSucceed() {
            resolver.fulfill(())
        }

        public override func didReportError(_ error: Error) {
            Logger.debug("remainingRetries: \(self.remainingRetries)")
        }

        public override func didFail(error: Error) {
            Logger.error("failed with error: \(error)")

            resolver.reject(error)
        }
    }

    // Fetch group state from service and apply.
    //
    // * Try to fetch and apply incremental "changes" -
    //   if the group already existing in the database.
    // * Failover to fetching and applying latest snapshot.
    // * We need to distinguish between retryable (network) errors
    //   and non-retryable errors.
    // * In the case of networking errors, we should do exponential
    //   backoff.
    // * If reachability changes, we should retry network errors
    //   immediately.
    //
    // It should upsert the group thread if it does not exist.
    //
    // GroupsV2 TODO: Implement properly.
    private func refreshGroupFromService(groupSecretParamsData: Data,
                                         groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {

        // Try to use individual changes.
        return fetchAndApplyChangeActionsFromService(groupSecretParamsData: groupSecretParamsData,
                                                     groupUpdateMode: groupUpdateMode)
            .recover { (error) throws -> Promise<TSGroupThread> in
                switch error {
                case GroupsV2Error.unknownGroup:
                    // Unknown groups are handled by snapshot.
                    break
                case GroupsV2Error.todo:
                    Logger.warn("Error: \(error)")
                default:
                    owsFailDebug("Error: \(error)")
                }

                // GroupsV2 TODO: This should not fail over in the case of networking problems.

                // Failover to applying latest snapshot.
                return self.fetchAndApplyCurrentGroupV2SnapshotFromService(groupSecretParamsData: groupSecretParamsData,
                                                                           groupUpdateMode: groupUpdateMode)
        }
    }

    // MARK: - Group Changes

    public func updateGroupWithChangeActions(groupId: Data,
                                             changeActionsProto: GroupsProtoGroupChangeActions,
                                             transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {
        // GroupsV2 TODO: Instead of loading the group model from the database,
        // we should use exactly the same group model that was used to construct
        // the update request - which should reflect pre-update service state.

        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Missing groupThread.")
        }
        // GroupsV2 TODO: Can we eliminate ChangedGroupModel?
        let changedGroupModel = try GroupsV2Changes.applyChangesToGroupModel(groupThread: groupThread,
                                                                             changeActionsProto: changeActionsProto,
                                                                             transaction: transaction)
        guard changedGroupModel.newGroupModel.groupV2Revision > changedGroupModel.oldGroupModel.groupV2Revision else {
            throw OWSAssertionError("Invalid groupV2Revision: \(changedGroupModel.newGroupModel.groupV2Revision).")
        }

        // GroupsV2 TODO: Set groupUpdateSourceAddress.
        let updatedGroupThread = try GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(groupThread: groupThread,
                                                                                                          newGroupModel: changedGroupModel.newGroupModel,
                                                                                                          groupUpdateSourceAddress: nil,
                                                                                                          transaction: transaction)

        guard updatedGroupThread.groupModel.groupV2Revision > changedGroupModel.oldGroupModel.groupV2Revision else {
            throw OWSAssertionError("Invalid groupV2Revision: \(changedGroupModel.newGroupModel.groupV2Revision).")
        }
        guard updatedGroupThread.groupModel.groupV2Revision >= changedGroupModel.newGroupModel.groupV2Revision else {
            throw OWSAssertionError("Invalid groupV2Revision: \(changedGroupModel.newGroupModel.groupV2Revision).")
        }
        return updatedGroupThread
    }

    private func fetchAndApplyChangeActionsFromService(groupSecretParamsData: Data,
                                                       groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {
        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            return Promise(error: OWSAssertionError("Invalid groupsV2 instance."))
        }
        return groupsV2Swift.fetchGroupChangeActions(groupSecretParamsData: groupSecretParamsData)
            .then(on: DispatchQueue.global()) { (groupChanges) throws -> Promise<TSGroupThread> in
                let groupId = try self.groupsV2.groupId(forGroupSecretParamsData: groupSecretParamsData)
                return self.tryToApplyGroupChangesFromService(groupId: groupId,
                                                              groupChanges: groupChanges,
                                                              groupUpdateMode: groupUpdateMode)
        }
    }

    private func tryToApplyGroupChangesFromService(groupId: Data,
                                                   groupChanges: [GroupV2Change],
                                                   groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {
        switch groupUpdateMode {
        case .upToSpecificRevisionImmediately(let upToRevision):
            return tryToApplyGroupChangesFromServiceNow(groupId: groupId,
                                                        groupChanges: groupChanges,
                                                        upToRevision: upToRevision)
        case .upToCurrentRevisionAfterMessageProcessWithThrottling:
            return messageProcessing.allMessageFetchingAndProcessingPromise()
                .then(on: .global()) { _ in
                    return self.tryToApplyGroupChangesFromServiceNow(groupId: groupId,
                                                                     groupChanges: groupChanges,
                                                                     upToRevision: nil)
            }
        }
    }

    private func tryToApplyGroupChangesFromServiceNow(groupId: Data,
                                                      groupChanges: [GroupV2Change],
                                                      upToRevision: UInt32?) -> Promise<TSGroupThread> {
        return databaseStorage.write(.promise) { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
            guard let oldGroupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing group thread.")
            }

            var groupThread = oldGroupThread

            for groupChange in groupChanges {
                let changeRevision = groupChange.snapshot.revision
                if let upToRevision = upToRevision {
                    guard upToRevision >= changeRevision else {
                        Logger.info("Ignoring group change: \(changeRevision); only updating to revision: \(upToRevision)")
                        return groupThread
                    }
                }
                let newGroupModel = try GroupManager.buildGroupModel(groupV2Snapshot: groupChange.snapshot,
                                                                     transaction: transaction)
                // GroupsV2 TODO: Set groupUpdateSourceAddress.
                let groupUpdateSourceAddress: SignalServiceAddress? = nil
                groupThread = try GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(groupThread: groupThread,
                                                                                                       newGroupModel: newGroupModel,
                                                                                                       groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                       transaction: transaction)

            }
            return groupThread
        }
    }

    // MARK: - Current Snapshot

    private func fetchAndApplyCurrentGroupV2SnapshotFromService(groupSecretParamsData: Data,
                                                                groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {
        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            return Promise(error: OWSAssertionError("Invalid groupsV2 instance."))
        }
        return groupsV2Swift.fetchCurrentGroupV2Snapshot(groupSecretParamsData: groupSecretParamsData)
            .then(on: .global()) { groupV2Snapshot in
                return self.tryToApplyCurrentGroupV2SnapshotFromService(groupV2Snapshot: groupV2Snapshot,
                                                                        groupUpdateMode: groupUpdateMode)
        }
    }

    private func tryToApplyCurrentGroupV2SnapshotFromService(groupV2Snapshot: GroupV2Snapshot,
                                                             groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {
        switch groupUpdateMode {
        case .upToSpecificRevisionImmediately:
            return tryToApplyCurrentGroupV2SnapshotFromServiceNow(groupV2Snapshot: groupV2Snapshot)
        case .upToCurrentRevisionAfterMessageProcessWithThrottling:
            return messageProcessing.allMessageFetchingAndProcessingPromise()
                .then(on: .global()) { _ in
                    return self.tryToApplyCurrentGroupV2SnapshotFromServiceNow(groupV2Snapshot: groupV2Snapshot)
            }
        }
    }

    private func tryToApplyCurrentGroupV2SnapshotFromServiceNow(groupV2Snapshot: GroupV2Snapshot) -> Promise<TSGroupThread> {
        return databaseStorage.write(.promise) { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
            let newGroupModel = try GroupManager.buildGroupModel(groupV2Snapshot: groupV2Snapshot,
                                                                 transaction: transaction)
            // GroupsV2 TODO: Set groupUpdateSourceAddress.
            let groupUpdateSourceAddress: SignalServiceAddress? = nil
            return try GroupManager.tryToUpdateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                                 groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                 canInsert: true,
                                                                                                 transaction: transaction)
        }
    }
}
