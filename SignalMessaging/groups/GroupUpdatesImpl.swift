//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import ZKGroup

@objc
public class GroupUpdatesImpl: NSObject, GroupUpdates {

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

    //    public typealias ProfileKeyCredentialMap = [UUID: ProfileKeyCredential]

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: -

    private let serialQueue = DispatchQueue(label: "GroupUpdatesImpl")

    private struct RefreshState {
        private var groupRefreshesInFlightSet = Set<Data>()
        private var lastGroupRefreshMap = [Data: Date]()

        func isRefreshInFlight(forGroupId groupId: Data) -> Bool {
            return groupRefreshesInFlightSet.contains(groupId)
        }

        mutating func markRefreshInFlight(forGroupId groupId: Data) {
            assert(!groupRefreshesInFlightSet.contains(groupId))

            groupRefreshesInFlightSet.insert(groupId)
        }

        func lastGroupRefreshMap(forGroupId  groupId: Data) -> Date? {
            return lastGroupRefreshMap[groupId]
        }

        mutating func lastGroupRefreshSuceeded(forGroupId groupId: Data) {
            lastGroupRefreshMap[groupId] = Date()
        }
    }

    private let upToRevisionImmediatelyRefreshState = RefreshState()
    private let upToLatestAfterMessageProcessRefreshState = RefreshState()

    private func refreshState(for groupUpdateMode: GroupUpdateMode) -> RefreshState {
        switch groupUpdateMode {
        case .upToRevisionImmediately:
            return upToRevisionImmediatelyRefreshState
        case .upToLatestAfterMessageProcess:
            return upToLatestAfterMessageProcessRefreshState
        }
    }

    // MARK: -

    @objc
    public func tryToRefreshGroupThreadToLatestStateWithThrottling(_ thread: TSThread) {
        tryToRefreshGroupThreadWithThrottling(thread, groupUpdateMode: .upToLatestAfterMessageProcess)
    }

    private func tryToRefreshGroupThreadWithThrottling(_ thread: TSThread,
                                                       groupUpdateMode: GroupUpdateMode) {
        guard let groupThread = thread as? TSGroupThread else {
            return
        }
        let groupModel = groupThread.groupModel
        guard groupModel.groupsVersion == .V2 else {
            return
        }
        let groupId = groupModel.groupId
        let shouldUpdate = serialQueue.sync { () -> Bool in
            var refreshState = self.refreshState(for: groupUpdateMode)

            guard !refreshState.isRefreshInFlight(forGroupId: groupId) else {
                // Ignore; group refresh already in flight.
                return false
            }
            if let lastRefreshData = refreshState.lastGroupRefreshMap(forGroupId: groupId) {
                // Don't auto-refresh more often than once every N minutes.
                let refreshFrequency: TimeInterval = kMinuteInterval * 5
                guard abs(lastRefreshData.timeIntervalSinceNow) > refreshFrequency else {
                    return false
                }
            }

            // Mark refresh as in flight.
            refreshState.markRefreshInFlight(forGroupId: groupId)

            return true
        }
        guard shouldUpdate else {
            return
        }
    }

    private func refreshGroupV2SnapshotFromService(groupSecretParamsData: Data,
                                                   groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {
        // GroupsV2 TODO: Try to use individual changes.

        guard let groupsV2Swift = self.groupsV2 as? GroupsV2Swift else {
            return Promise(error: OWSAssertionError("Invalid groupsV2 instance."))
        }
        return groupsV2Swift.fetchCurrentGroupV2Snapshot(groupSecretParamsData: groupSecretParamsData)
            .then(on: .global()) { groupV2Snapshot in
                return self.tryToApplyCurrentGroupV2SnapshotFromService(groupV2Snapshot: groupV2Snapshot,
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
        case .upToRevisionImmediately:
            return tryToApplyGroupChangesFromServiceNow(groupId: groupId,
                                                        groupChanges: groupChanges)
        case .upToLatestAfterMessageProcess:
            return messageProcessing.allMessageFetchingAndProcessingPromise()
                .then(on: .global()) { _ in
                    return self.tryToApplyGroupChangesFromServiceNow(groupId: groupId,
                                                                     groupChanges: groupChanges)
            }
        }
    }

    private func tryToApplyGroupChangesFromServiceNow(groupId: Data,
                                                      groupChanges: [GroupV2Change]) -> Promise<TSGroupThread> {
        return databaseStorage.write(.promise) { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
            guard let oldGroupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                throw OWSAssertionError("Missing group thread.")
            }

            var groupThread = oldGroupThread

            for groupChange in groupChanges {
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

    // MARK: - Current State

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
        case .upToRevisionImmediately:
            return tryToApplyCurrentGroupV2SnapshotFromServiceNow(groupV2Snapshot: groupV2Snapshot)
        case .upToLatestAfterMessageProcess:
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
