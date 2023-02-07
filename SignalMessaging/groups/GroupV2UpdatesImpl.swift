//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import LibSignalClient

@objc
public class GroupV2UpdatesImpl: NSObject {

    // This tracks the last time that groups were updated to the current
    // revision.
    private static let groupRefreshStore = SDSKeyValueStore(collection: "groupRefreshStore")

    private let changeCache = LRUCache<Data, ChangeCacheItem>(maxSize: 5)
    private var lastSuccessfulRefreshMap = LRUCache<Data, Date>(maxSize: 256)

    let immediateOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "GroupV2UpdatesImpl.immediateOperationQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    let afterMessageProcessingOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "GroupV2UpdatesImpl.afterMessageProcessingOperationQueue"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.autoRefreshGroupOnLaunch()
        }
    }

    // MARK: -

    // On launch, we refresh a few randomly-selected groups.
    private func autoRefreshGroupOnLaunch() {
        guard CurrentAppContext().isMainApp,
              tsAccountManager.isRegisteredAndReady,
              reachabilityManager.isReachable,
              !CurrentAppContext().isRunningTests else {
            return
        }

        firstly(on: .global()) { () -> Promise<Void> in
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.then(on: .global()) { _ -> Promise<Void> in
            guard let groupInfoToRefresh = Self.findGroupToAutoRefresh() else {
                // We didn't find a group to refresh; abort.
                return Promise.value(())
            }
            let groupId = groupInfoToRefresh.groupId
            let groupSecretParamsData = groupInfoToRefresh.groupSecretParamsData
            if let lastRefreshDate = groupInfoToRefresh.lastRefreshDate {
                let duration = OWSFormat.formatDurationSeconds(Int(abs(lastRefreshDate.timeIntervalSinceNow)))
                Logger.info("Auto-refreshing group: \(groupId.hexadecimalString) which hasn't been refreshed in \(duration).")
            } else {
                Logger.info("Auto-refreshing group: \(groupId.hexadecimalString) which has never been refreshed.")
            }
            return self.tryToRefreshV2GroupUpToCurrentRevisionImmediately(
                groupId: groupId,
                groupSecretParamsData: groupSecretParamsData
            ).asVoid()
        }.done(on: .global()) { _ in
            Logger.verbose("Complete.")
        }.catch(on: .global()) { error in
            if case GroupsV2Error.localUserNotInGroup = error {
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebugUnlessNetworkFailure(error)
            }
        }
    }

    private func didUpdateGroupToCurrentRevision(groupId: Data) {
        Logger.verbose("Refreshed group to current revision: \(groupId.hexadecimalString).")
        let storeKey = groupId.hexadecimalString
        Self.databaseStorage.write { transaction in
            Self.groupRefreshStore.setDate(Date(), key: storeKey, transaction: transaction)
        }
    }

    private struct GroupInfo {
        let groupId: Data
        let groupSecretParamsData: Data
        let lastRefreshDate: Date?
    }

    private static func findGroupToAutoRefresh() -> GroupInfo? {
        // Enumerate the all v2 groups, trying to find the "best" one to refresh.
        // The "best" is the group that hasn't been refreshed in the longest
        // time.
        Self.databaseStorage.read { transaction in
            var groupInfoToRefresh: GroupInfo?
            TSGroupThread.anyEnumerate(
                transaction: transaction,
                batched: true
            ) { (thread, stop) in
                guard
                    let groupThread = thread as? TSGroupThread,
                    let groupModel = groupThread.groupModel as? TSGroupModelV2,
                    groupModel.groupMembership.isLocalUserFullOrInvitedMember
                else {
                    // Refreshing a group we're not a member of will throw errors
                    return
                }

                let storeKey = groupThread.groupId.hexadecimalString
                guard let lastRefreshDate: Date = Self.groupRefreshStore.getDate(
                    storeKey,
                    transaction: transaction
                ) else {
                    // If we find a group that we have no record of refreshing,
                    // pick that one immediately.
                    groupInfoToRefresh = GroupInfo(groupId: groupThread.groupId,
                                                   groupSecretParamsData: groupModel.secretParamsData,
                                                   lastRefreshDate: nil)
                    stop.pointee = true
                    return
                }

                // Don't auto-refresh groups more than once a week.
                let maxRefreshFrequencyInternal: TimeInterval = kWeekInterval * 1
                guard abs(lastRefreshDate.timeIntervalSinceNow) > maxRefreshFrequencyInternal else {
                    return
                }

                if let otherGroupInfo = groupInfoToRefresh,
                   let otherLastRefreshDate = otherGroupInfo.lastRefreshDate,
                   otherLastRefreshDate < lastRefreshDate {
                    // We already found another group with an older refresh
                    // date, so prefer that one.
                    return
                }

                groupInfoToRefresh = GroupInfo(groupId: groupThread.groupId,
                                               groupSecretParamsData: groupModel.secretParamsData,
                                               lastRefreshDate: lastRefreshDate)
            }
            return groupInfoToRefresh
        }
    }
}

// MARK: - GroupV2UpdatesSwift

extension GroupV2UpdatesImpl: GroupV2UpdatesSwift {

    public func updateGroupWithChangeActions(
        groupId: Data,
        changeActionsProto: GroupsProtoGroupChangeActions,
        downloadedAvatars: GroupV2DownloadedAvatars,
        transaction: SDSAnyWriteTransaction
    ) throws -> TSGroupThread {

        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Missing groupThread.")
        }
        guard groupThread.groupModel.groupsVersion == .V2 else {
            throw OWSAssertionError("Invalid groupsVersion.")
        }
        let changedGroupModel = try GroupsV2IncomingChanges.applyChangesToGroupModel(
            groupThread: groupThread,
            changeActionsProto: changeActionsProto,
            downloadedAvatars: downloadedAvatars,
            groupModelOptions: []
        )
        guard changedGroupModel.newGroupModel.revision > changedGroupModel.oldGroupModel.revision else {
            throw OWSAssertionError("Invalid groupV2Revision: \(changedGroupModel.newGroupModel.revision).")
        }

        let groupUpdateSourceAddress = SignalServiceAddress(uuid: changedGroupModel.changeAuthorUuid)
        let newGroupModel = changedGroupModel.newGroupModel
        let newDisappearingMessageToken = changedGroupModel.newDisappearingMessageToken
        let updatedGroupThread = try GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
            newGroupModel: newGroupModel,
            newDisappearingMessageToken: newDisappearingMessageToken,
            groupUpdateSourceAddress: groupUpdateSourceAddress,
            transaction: transaction
        ).groupThread

        GroupManager.storeProfileKeysFromGroupProtos(changedGroupModel.profileKeys)

        guard let updatedGroupModel = updatedGroupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group model.")
        }
        guard updatedGroupModel.revision > changedGroupModel.oldGroupModel.revision else {
            throw OWSAssertionError("Invalid groupV2Revision: \(updatedGroupModel.revision) <= \(changedGroupModel.oldGroupModel.revision).")
        }
        guard updatedGroupModel.revision >= changedGroupModel.newGroupModel.revision else {
            throw OWSAssertionError("Invalid groupV2Revision: \(updatedGroupModel.revision) < \(changedGroupModel.newGroupModel.revision).")
        }
        return updatedGroupThread
    }

    public func tryToRefreshV2GroupUpToCurrentRevisionImmediately(
        groupId: Data,
        groupSecretParamsData: Data
    ) -> Promise<TSGroupThread> {
        let groupUpdateMode = GroupUpdateMode.upToCurrentRevisionImmediately
        return tryToRefreshV2GroupThread(groupId: groupId,
                                         groupSecretParamsData: groupSecretParamsData,
                                         groupUpdateMode: groupUpdateMode)
    }

    public func tryToRefreshV2GroupUpToCurrentRevisionImmediately(
        groupId: Data,
        groupSecretParamsData: Data,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {
        let groupUpdateMode = GroupUpdateMode.upToCurrentRevisionImmediately
        return tryToRefreshV2GroupThread(groupId: groupId,
                                         groupSecretParamsData: groupSecretParamsData,
                                         groupUpdateMode: groupUpdateMode,
                                         groupModelOptions: groupModelOptions)
    }

    public func tryToRefreshV2GroupThread(
        groupId: Data,
        groupSecretParamsData: Data,
        groupUpdateMode: GroupUpdateMode
    ) -> Promise<TSGroupThread> {
        tryToRefreshV2GroupThread(groupId: groupId,
                                  groupSecretParamsData: groupSecretParamsData,
                                  groupUpdateMode: groupUpdateMode,
                                  groupModelOptions: [])
    }

    public func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(_ groupThread: TSGroupThread) {
        let groupUpdateMode = GroupUpdateMode.upToCurrentRevisionAfterMessageProcessWithThrottling
        tryToRefreshV2GroupThread(groupThread, groupUpdateMode: groupUpdateMode)
    }

    public func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithoutThrottling(_ groupThread: TSGroupThread) {
        let groupUpdateMode = GroupUpdateMode.upToCurrentRevisionAfterMessageProcessWithoutThrottling
        tryToRefreshV2GroupThread(groupThread, groupUpdateMode: groupUpdateMode)
    }

    private func tryToRefreshV2GroupThread(
        _ groupThread: TSGroupThread,
        groupUpdateMode: GroupUpdateMode
    ) {

        firstly(on: .global()) { () -> Promise<Void> in
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                return Promise.value(())
            }
            let groupId = groupModel.groupId
            let groupSecretParamsData = groupModel.secretParamsData
            return self.tryToRefreshV2GroupThread(groupId: groupId,
                                                  groupSecretParamsData: groupSecretParamsData,
                                                  groupUpdateMode: groupUpdateMode).asVoid()
        }.catch(on: .global()) { error in
            Logger.warn("Group refresh failed: \(error).")
        }
    }

    private func tryToRefreshV2GroupThread(
        groupId: Data,
        groupSecretParamsData: Data,
        groupUpdateMode: GroupUpdateMode,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {

        let isThrottled = { () -> Bool in
            guard groupUpdateMode.shouldThrottle else {
                return false
            }
            guard let lastSuccessfulRefreshDate = self.lastSuccessfulRefreshDate(forGroupId: groupId) else {
                return false
            }
            // Don't auto-refresh more often than once every N minutes.
            let refreshFrequency: TimeInterval = kMinuteInterval * 5
            return abs(lastSuccessfulRefreshDate.timeIntervalSinceNow) < refreshFrequency
        }()

        let earlyPromise: Promise<TSGroupThread>? = databaseStorage.read {
            // - If we're blocked, it's an immediate error
            // - If we're throttled, return the current thread state if we have it
            // - Otherwise, we want to proceed with group update
            if blockingManager.isGroupIdBlocked(groupId, transaction: $0) {
                return Promise(error: GroupsV2Error.groupBlocked)
            } else if isThrottled, let thread = TSGroupThread.fetch(groupId: groupId, transaction: $0) {
                Logger.verbose("Skipping redundant v2 group refresh.")
                return Promise.value(thread)
            } else {
                return nil
            }
        }

        if let earlyPromise = earlyPromise {
            return earlyPromise
        }

        let operation = GroupV2UpdateOperation(groupId: groupId,
                                               groupSecretParamsData: groupSecretParamsData,
                                               groupUpdateMode: groupUpdateMode,
                                               groupModelOptions: groupModelOptions)
        operation.promise.done(on: .global()) { _ in
            Logger.verbose("Group refresh succeeded.")

            self.groupRefreshDidSucceed(forGroupId: groupId, groupUpdateMode: groupUpdateMode)
        }.catch(on: .global()) { error in
            Logger.verbose("Group refresh failed: \(error).")
        }
        let operationQueue = self.operationQueue(forGroupUpdateMode: groupUpdateMode)
        operationQueue.addOperation(operation)
        return operation.promise
    }

    private func lastSuccessfulRefreshDate(forGroupId groupId: Data) -> Date? {
        lastSuccessfulRefreshMap[groupId]
    }

    private func groupRefreshDidSucceed(
        forGroupId groupId: Data,
        groupUpdateMode: GroupUpdateMode
    ) {
        lastSuccessfulRefreshMap[groupId] = Date()

        if groupUpdateMode.shouldUpdateToCurrentRevision {
            didUpdateGroupToCurrentRevision(groupId: groupId)
        }
    }

    private func operationQueue(forGroupUpdateMode groupUpdateMode: GroupUpdateMode) -> OperationQueue {
        if groupUpdateMode.shouldBlockOnMessageProcessing {
            return afterMessageProcessingOperationQueue
        } else {
            return immediateOperationQueue
        }
    }

    private class GroupV2UpdateOperation: OWSOperation {

        let groupId: Data
        let groupSecretParamsData: Data
        let groupUpdateMode: GroupUpdateMode
        let groupModelOptions: TSGroupModelOptions

        let promise: Promise<TSGroupThread>
        let future: Future<TSGroupThread>

        required init(groupId: Data,
                      groupSecretParamsData: Data,
                      groupUpdateMode: GroupUpdateMode,
                      groupModelOptions: TSGroupModelOptions) {
            self.groupId = groupId
            self.groupSecretParamsData = groupSecretParamsData
            self.groupUpdateMode = groupUpdateMode
            self.groupModelOptions = groupModelOptions

            let (promise, future) = Promise<TSGroupThread>.pending()
            self.promise = promise
            self.future = future

            super.init()

            self.remainingRetries = 3
        }

        // MARK: Run

        public override func run() {
            firstly { () -> Promise<Void> in
                if groupUpdateMode.shouldBlockOnMessageProcessing {
                    return self.messageProcessor.fetchingAndProcessingCompletePromise()
                } else {
                    return Promise.value(())
                }
            }.then(on: .global()) { _ in
                self.groupV2UpdatesImpl.refreshGroupFromService(groupSecretParamsData: self.groupSecretParamsData,
                                                                groupUpdateMode: self.groupUpdateMode,
                                                                groupModelOptions: self.groupModelOptions)
            }.done(on: .global()) { (groupThread: TSGroupThread) in
                Logger.verbose("Group refresh succeeded.")

                self.reportSuccess()
                self.future.resolve(groupThread)
            }.catch(on: .global()) { (error) in
                if error.isNetworkConnectivityFailure {
                    Logger.warn("Group update failed: \(error)")
                } else {
                    switch error {
                    case GroupsV2Error.localUserNotInGroup,
                         GroupsV2Error.timeout,
                         GroupsV2Error.missingGroupChangeProtos:
                    Logger.warn("Group update failed: \(error)")
                    default:
                        owsFailDebug("Group update failed: \(error)")
                    }
                }

                self.reportError(error)
            }
        }

        private var shouldRetryAuthFailures: Bool {
            return self.databaseStorage.read { transaction in
                guard let groupThread = TSGroupThread.fetch(groupId: self.groupId, transaction: transaction) else {
                    // The thread may have been deleted while the refresh was in flight.
                    Logger.warn("Missing group thread.")
                    return false
                }
                let isLocalUserInGroup = groupThread.isLocalUserFullOrInvitedMember
                // Auth errors are expected if we've left the group,
                // but we should still try to refresh so we can learn
                // if we've been re-added.
                return isLocalUserInGroup
            }
        }

        public override func didSucceed() {
            // Do nothing.
        }

        public override func didReportError(_ error: Error) {
            Logger.debug("remainingRetries: \(self.remainingRetries)")
        }

        public override func didFail(error: Error) {
            Logger.error("failed with error: \(error)")

            future.reject(error)
        }
    }
}

// MARK: - Refresh group from service

private extension GroupV2UpdatesImpl {

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
    func refreshGroupFromService(
        groupSecretParamsData: Data,
        groupUpdateMode: GroupUpdateMode,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {

        return firstly {
            return GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: DispatchQueue.global()) { () throws -> Promise<TSGroupThread> in
            // Try to use individual changes.
            return firstly(on: .global()) {
                self.fetchAndApplyChangeActionsFromService(groupSecretParamsData: groupSecretParamsData,
                                                           groupUpdateMode: groupUpdateMode,
                                                           groupModelOptions: groupModelOptions)
                    .timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                             description: "Update via changes") {
                        GroupsV2Error.timeout
                    }
            }.recover { (error) throws -> Promise<TSGroupThread> in
                let shouldTrySnapshot = { () -> Bool in
                    // This should not fail over in the case of networking problems.
                    if error.isNetworkConnectivityFailure {
                        Logger.warn("Error: \(error)")
                        return false
                    }

                    switch error {
                    case GroupsV2Error.localUserNotInGroup:
                        // We can recover from some auth edge cases using a
                        // snapshot. For example, if we are joining via an
                        // invite link we will be unable to fetch change
                        // actions.
                        return true
                    case GroupsV2Error.cantApplyChangesToPlaceholder:
                        // We can only update placeholder groups using a snapshot.
                        return true
                    case GroupsV2Error.missingGroupChangeProtos:
                        // If the service returns a group state without change protos,
                        // fail over to the snapshot.
                        return true
                    default:
                        owsFailDebugUnlessNetworkFailure(error)
                        return false
                    }
                }()

                guard shouldTrySnapshot else {
                    throw error
                }

                // Failover to applying latest snapshot.
                return self.fetchAndApplyCurrentGroupV2SnapshotFromService(
                    groupSecretParamsData: groupSecretParamsData,
                    groupUpdateMode: groupUpdateMode,
                    groupModelOptions: groupModelOptions
                )
            }
        }
    }

    private func fetchAndApplyChangeActionsFromService(
        groupSecretParamsData: Data,
        groupUpdateMode: GroupUpdateMode,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {

        return firstly { () -> Promise<GroupsV2Impl.GroupChangePage> in
            self.fetchChangeActionsFromService(groupSecretParamsData: groupSecretParamsData,
                                               groupUpdateMode: groupUpdateMode)
        }.then(on: .global()) { (groupChanges: GroupsV2Impl.GroupChangePage) throws -> Promise<TSGroupThread> in
            let groupId = try self.groupsV2.groupId(forGroupSecretParamsData: groupSecretParamsData)
            let applyPromise = self.tryToApplyGroupChangesFromService(
                groupId: groupId,
                groupSecretParamsData: groupSecretParamsData,
                groupChanges: groupChanges.changes,
                groupUpdateMode: groupUpdateMode,
                groupModelOptions: groupModelOptions
            )
            guard let earlyEnd = groupChanges.earlyEnd else {
                // We fetched all possible updates (or got a cached set of updates).
                return applyPromise
            }
            if case .upToSpecificRevisionImmediately(upToRevision: let upToRevision) = groupUpdateMode {
                if upToRevision <= earlyEnd {
                    // We didn't fetch everything but we did fetch enough.
                    return applyPromise
                }
            }

            // Recurse to process more updates.
            return applyPromise.then { _ in
                return self.fetchAndApplyChangeActionsFromService(
                    groupSecretParamsData: groupSecretParamsData,
                    groupUpdateMode: groupUpdateMode,
                    groupModelOptions: groupModelOptions
                )
            }
        }
    }

    private func fetchChangeActionsFromService(
        groupSecretParamsData: Data,
        groupUpdateMode: GroupUpdateMode
    ) -> Promise<GroupsV2Impl.GroupChangePage> {

        let upToRevision: UInt32? = {
            switch groupUpdateMode {
            case .upToSpecificRevisionImmediately(let upToRevision):
                return upToRevision
            default:
                return nil
            }
        }()
        let includeCurrentRevision: Bool = {
            switch groupUpdateMode {
            case .upToSpecificRevisionImmediately:
                return false
            case .upToCurrentRevisionAfterMessageProcessWithThrottling,
                 .upToCurrentRevisionAfterMessageProcessWithoutThrottling,
                 .upToCurrentRevisionImmediately:
                return true
            }
        }()

        return firstly(on: .global()) { () -> [GroupV2Change]? in
            // Try to use group changes from the cache.
            return self.cachedGroupChanges(groupSecretParamsData: groupSecretParamsData,
                                           upToRevision: upToRevision)
        }.then(on: .global()) { (groupChanges: [GroupV2Change]?) -> Promise<GroupsV2Impl.GroupChangePage> in
            if let groupChanges = groupChanges {
                return Promise.value(GroupsV2Impl.GroupChangePage(changes: groupChanges, earlyEnd: nil))
            }
            return firstly {
                return self.groupsV2Impl.fetchGroupChangeActions(
                    groupSecretParamsData: groupSecretParamsData,
                    includeCurrentRevision: includeCurrentRevision
                )
            }.map(on: .global()) { (groupChanges: GroupsV2Impl.GroupChangePage) -> GroupsV2Impl.GroupChangePage in
                self.addGroupChangesToCache(groupChanges: groupChanges.changes,
                                            groupSecretParamsData: groupSecretParamsData)

                return groupChanges
            }
        }
    }

    private func tryToApplyGroupChangesFromService(
        groupId: Data,
        groupSecretParamsData: Data,
        groupChanges: [GroupV2Change],
        groupUpdateMode: GroupUpdateMode,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {
        return firstly { () -> Promise<Void> in
            if groupUpdateMode.shouldBlockOnMessageProcessing {
                return self.messageProcessor.fetchingAndProcessingCompletePromise()
            } else {
                return Promise.value(())
            }
        }.then(on: .global()) {
            return self.tryToApplyGroupChangesFromServiceNow(
                groupId: groupId,
                groupSecretParamsData: groupSecretParamsData,
                groupChanges: groupChanges,
                upToRevision: groupUpdateMode.upToRevision,
                groupModelOptions: groupModelOptions
            )
        }
    }

    private func tryToApplyGroupChangesFromServiceNow(
        groupId: Data,
        groupSecretParamsData: Data,
        groupChanges: [GroupV2Change],
        upToRevision: UInt32?,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {

        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }

        return databaseStorage.write(.promise) { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
            let groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)

            // See comment on getOrCreateThreadForGroupChanges(...).
            guard var (groupThread, localUserWasAddedBy) = self.getOrCreateThreadForGroupChanges(
                groupId: groupId,
                groupV2Params: groupV2Params,
                groupChanges: groupChanges,
                transaction: transaction
            ) else {
                throw OWSAssertionError("Missing group thread.")
            }

            if groupChanges.count < 1 {
                Logger.verbose("No group changes.")
                return groupThread
            }

            var profileKeysByUuid = [UUID: Data]()
            for (index, groupChange) in groupChanges.enumerated() {
                if let upToRevision = upToRevision {
                    let changeRevision = groupChange.revision
                    guard upToRevision >= changeRevision else {
                        Logger.info("Ignoring group change: \(changeRevision); only updating to revision: \(upToRevision)")

                        // Enqueue an update to latest.
                        self.tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(groupThread)

                        break
                    }
                }

                let applyResult = try autoreleasepool {
                    try self.tryToApplySingleChangeFromService(
                        groupThread: &groupThread,
                        groupV2Params: groupV2Params,
                        groupModelOptions: groupModelOptions,
                        groupChange: groupChange,
                        isFirstChange: index == 0,
                        profileKeysByUuid: &profileKeysByUuid,
                        transaction: transaction
                    )
                }

                if
                    let applyResult = applyResult,
                    let changeAuthor = applyResult.changeAuthor,
                    applyResult.wasLocalUserAddedByChange
                {
                    owsAssertDebug(
                        localUserWasAddedBy == nil || (index == 0 && localUserWasAddedBy == changeAuthor),
                        "Multiple change actions added the user to the group"
                    )
                    localUserWasAddedBy = changeAuthor
                }
            }

            GroupManager.storeProfileKeysFromGroupProtos(profileKeysByUuid)

            if
                let localUserWasAddedBy = localUserWasAddedBy,
                self.blockingManager.isAddressBlocked(localUserWasAddedBy, transaction: transaction)
            {
                // If we have been added to the group by a blocked user, we
                // should automatically leave the group. To that end, enqueue
                // a leave action after we've finished processing messages.
                _ = GroupManager.localLeaveGroupOrDeclineInvite(
                    groupThread: groupThread,
                    waitForMessageProcessing: true,
                    transaction: transaction
                )
            } else if
                let profileKey = profileKeysByUuid[localUuid],
                profileKey != self.profileManager.localProfileKey().keyData
            {
                // If the final group state includes a stale profile key for the
                // local user, schedule an update to fix that. Note that we skip
                // this step if we are planning to leave the group via the block
                // above, as it's redundant.
                self.groupsV2.updateLocalProfileKeyInGroup(
                    groupId: groupId,
                    transaction: transaction
                )
            }

            return groupThread
        }
    }

    // When learning about a v2 group for the first time, we need a snapshot of
    // the group's current state to get us started. From then on we prefer to
    // update the group using change actions, since those have more information.
    // Specifically, change actions record who performed the action, e.g. who
    // created the group or added us.
    //
    // We use this method to insert a thread if need be, so we can use change
    // actions going forward to keep the group up-to-date.
    private func getOrCreateThreadForGroupChanges(
        groupId: Data,
        groupV2Params: GroupV2Params,
        groupChanges: [GroupV2Change],
        transaction: SDSAnyWriteTransaction
    ) -> (TSGroupThread, addedToNewThreadBy: SignalServiceAddress?)? {

        if let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            return (groupThread, addedToNewThreadBy: nil)
        }

        do {
            guard
                let firstGroupChange = groupChanges.first,
                let snapshot = firstGroupChange.snapshot
            else {
                throw OWSAssertionError("Missing first group change with snapshot")
            }

            let groupUpdateSourceAddress = try firstGroupChange.author(groupV2Params: groupV2Params)

            var builder = try TSGroupModelBuilder.builderForSnapshot(
                groupV2Snapshot: snapshot,
                transaction: transaction
            )
            if snapshot.revision == 0, groupUpdateSourceAddress?.isLocalAddress == true {
                builder.wasJustCreatedByLocalUser = true
            }

            let newGroupModel = try builder.build()

            let newDisappearingMessageToken = snapshot.disappearingMessageToken
            let didAddLocalUserToV2Group = self.didAddLocalUserToV2Group(
                inGroupChange: firstGroupChange,
                groupV2Params: groupV2Params
            )

            let result = try GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
                newGroupModel: newGroupModel,
                newDisappearingMessageToken: newDisappearingMessageToken,
                groupUpdateSourceAddress: groupUpdateSourceAddress,
                canInsert: true,
                didAddLocalUserToV2Group: didAddLocalUserToV2Group,
                transaction: transaction
            )

            // NOTE: We don't need to worry about profile keys here.  This method is
            // only used by tryToApplyGroupChangesFromServiceNow() which will take
            // care of that.

            return (
                result.groupThread,
                addedToNewThreadBy: didAddLocalUserToV2Group ? groupUpdateSourceAddress : nil
            )
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private struct ApplySingleChangeFromServiceResult {
        let changeAuthor: SignalServiceAddress?
        let wasLocalUserAddedByChange: Bool
    }

    private func tryToApplySingleChangeFromService(
        groupThread: inout TSGroupThread,
        groupV2Params: GroupV2Params,
        groupModelOptions: TSGroupModelOptions,
        groupChange: GroupV2Change,
        isFirstChange: Bool,
        profileKeysByUuid: inout [UUID: Data],
        transaction: SDSAnyWriteTransaction
    ) throws -> ApplySingleChangeFromServiceResult? {

        guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group model.")
        }
        let changeRevision = groupChange.revision

        let isSingleRevisionUpdate = oldGroupModel.revision + 1 == changeRevision

        // We should only replace placeholder models using
        // latest snapshots _except_ in the case where the
        // local user is a requesting member and the first
        // change action approves their request to join the
        // group.
        if oldGroupModel.isPlaceholderModel {
            guard isFirstChange else {
                throw GroupsV2Error.cantApplyChangesToPlaceholder
            }
            guard isSingleRevisionUpdate else {
                throw GroupsV2Error.cantApplyChangesToPlaceholder
            }
            guard groupChange.snapshot != nil else {
                throw GroupsV2Error.cantApplyChangesToPlaceholder
            }
            guard let localUuid = tsAccountManager.localUuid,
                  oldGroupModel.groupMembership.isRequestingMember(localUuid) else {
                throw GroupsV2Error.cantApplyChangesToPlaceholder
            }
        }

        let newGroupModel: TSGroupModel
        let newDisappearingMessageToken: DisappearingMessageToken?
        let newProfileKeys: [UUID: Data]

        // We should prefer to update models using the change action if we can,
        // since it contains information about the change author.
        if
            isSingleRevisionUpdate,
            let changeActionsProto = groupChange.changeActionsProto
        {
            let changedGroupModel = try GroupsV2IncomingChanges.applyChangesToGroupModel(
                groupThread: groupThread,
                changeActionsProto: changeActionsProto,
                downloadedAvatars: groupChange.downloadedAvatars,
                groupModelOptions: groupModelOptions)
            newGroupModel = changedGroupModel.newGroupModel
            newDisappearingMessageToken = changedGroupModel.newDisappearingMessageToken
            newProfileKeys = changedGroupModel.profileKeys
        } else if let snapshot = groupChange.snapshot {
            var builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: snapshot,
                                                                     transaction: transaction)
            builder.apply(options: groupModelOptions)
            newGroupModel = try builder.build()
            newDisappearingMessageToken = snapshot.disappearingMessageToken
            newProfileKeys = snapshot.profileKeys
        } else {
            owsFailDebug("neither a snapshot nor a change action (should have been validated earlier)")
            return nil
        }

        // We should only replace placeholder models using
        // _latest_ snapshots _except_ in the case where the
        // local user is a requesting member and the first
        // change action approves their request to join the
        // group.
        if oldGroupModel.isPlaceholderModel {
            guard let localUuid = tsAccountManager.localUuid,
                  newGroupModel.groupMembership.isFullMember(localUuid) else {
                throw GroupsV2Error.cantApplyChangesToPlaceholder
            }
        }

        if changeRevision == oldGroupModel.revision {
            if !oldGroupModel.isEqual(to: newGroupModel, comparisonMode: .compareAll) {
                // Sometimes we re-apply the snapshot corresponding to the
                // current revision when refreshing the group from the service.
                // This should match the state in the database.  If it doesn't,
                // this reflects a bug, perhaps a deviation in how the service
                // and client apply the "group changes" to the local model.
                //
                // The one known exception is that if we know locally that a
                // member joined via invite link, that state will not be present
                // on the membership from the snapshot (as it is not stored in a
                // group proto's membership). However, as differences only in
                // "joined via invite link" are ignored when comparing
                // memberships, getting here is a bug.
                Logger.verbose("oldGroupModel: \(oldGroupModel.debugDescription)")
                Logger.verbose("newGroupModel: \(newGroupModel.debugDescription)")
                Logger.warn("Local and server group models don't match.")
            }
        }

        let groupUpdateSourceAddress = try groupChange.author(groupV2Params: groupV2Params)

        // We determine the "author" of the update based on the change action,
        // so if we are applying multiple revisions (i.e., are applying a
        // snapshot) we cannot be sure of the author of each revision, and so
        // should not attribute it.
        var groupUpdateSourceAddressForAttribution: SignalServiceAddress?
        if isSingleRevisionUpdate {
            groupUpdateSourceAddressForAttribution = groupUpdateSourceAddress
        }

        groupThread = try GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
            newGroupModel: newGroupModel,
            newDisappearingMessageToken: newDisappearingMessageToken,
            groupUpdateSourceAddress: groupUpdateSourceAddressForAttribution,
            transaction: transaction).groupThread

        // Merge known profile keys, always taking latest.
        profileKeysByUuid.merge(newProfileKeys) { (_, latest) in latest }

        return ApplySingleChangeFromServiceResult(
            changeAuthor: groupUpdateSourceAddress,
            wasLocalUserAddedByChange: didAddLocalUserToV2Group(
                inGroupChange: groupChange,
                groupV2Params: groupV2Params
            )
        )
    }
}

// MARK: - Current Snapshot

private extension GroupV2UpdatesImpl {

    func fetchAndApplyCurrentGroupV2SnapshotFromService(
        groupSecretParamsData: Data,
        groupUpdateMode: GroupUpdateMode,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {

        return firstly {
            self.groupsV2Impl.fetchCurrentGroupV2Snapshot(groupSecretParamsData: groupSecretParamsData)
        }.then(on: .global()) { groupV2Snapshot in
            return self.tryToApplyCurrentGroupV2SnapshotFromService(
                groupV2Snapshot: groupV2Snapshot,
                groupUpdateMode: groupUpdateMode,
                groupModelOptions: groupModelOptions
            )
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: "Update via snapshot") {
            GroupsV2Error.timeout
        }
    }

    private func tryToApplyCurrentGroupV2SnapshotFromService(
        groupV2Snapshot: GroupV2Snapshot,
        groupUpdateMode: GroupUpdateMode,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {

        return firstly { () -> Promise<Void> in
            if groupUpdateMode.shouldBlockOnMessageProcessing {
                return self.messageProcessor.fetchingAndProcessingCompletePromise()
            } else {
                return Promise.value(())
            }
        }.then(on: .global()) { _ in
            self.tryToApplyCurrentGroupV2SnapshotFromServiceNow(
                groupV2Snapshot: groupV2Snapshot,
                groupModelOptions: groupModelOptions
            )
        }
    }

    private func tryToApplyCurrentGroupV2SnapshotFromServiceNow(
        groupV2Snapshot: GroupV2Snapshot,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {

        let localProfileKey = profileManager.localProfileKey()
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }

        return databaseStorage.write(.promise) { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
            var builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: groupV2Snapshot,
                                                                     transaction: transaction)
            builder.apply(options: groupModelOptions)

            if let groupId = builder.groupId,
               let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction),
               let oldGroupModel = groupThread.groupModel as? TSGroupModelV2,
               oldGroupModel.revision == builder.groupV2Revision {
                // Preserve certain transient properties if overwriting a model
                // at the same revision.
                if oldGroupModel.didJustAddSelfViaGroupLink {
                    builder.didJustAddSelfViaGroupLink = true
                }
            }

            let newGroupModel = try builder.buildAsV2()
            let newDisappearingMessageToken = groupV2Snapshot.disappearingMessageToken
            // groupUpdateSourceAddress is nil because we don't know the
            // author(s) of changes reflected in the snapshot.
            let groupUpdateSourceAddress: SignalServiceAddress? = nil
            let result = try GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
                newGroupModel: newGroupModel,
                newDisappearingMessageToken: newDisappearingMessageToken,
                groupUpdateSourceAddress: groupUpdateSourceAddress,
                canInsert: true,
                didAddLocalUserToV2Group: false,
                transaction: transaction
            )

            GroupManager.storeProfileKeysFromGroupProtos(groupV2Snapshot.profileKeys)

            // If the group state includes a stale profile key for the
            // local user, schedule an update to fix that.
            if let profileKey = groupV2Snapshot.profileKeys[localUuid],
               profileKey != localProfileKey.keyData {
                self.groupsV2.updateLocalProfileKeyInGroup(groupId: newGroupModel.groupId, transaction: transaction)
            }

            return result.groupThread
        }
    }

    private func didAddLocalUserToV2Group(
        inGroupChange groupChange: GroupV2Change,
        groupV2Params: GroupV2Params
    ) -> Bool {
        guard let localUuid = tsAccountManager.localUuid else {
            return false
        }
        if groupChange.revision == 0 {
            // Revision 0 is a special case and won't have actions to
            // reflect the initial membership.
            return true
        }
        guard let changeActionsProto = groupChange.changeActionsProto else {
            // We're missing a change here, so we can't assume this is how we got into the group.
            return false
        }

        for action in changeActionsProto.addMembers {
            do {
                guard let member = action.added else {
                    continue
                }
                guard let userId = member.userID else {
                    continue
                }
                // Some userIds/uuidCiphertexts can be validated by
                // the service. This is one.
                let uuid = try groupV2Params.uuid(forUserId: userId)
                if uuid == localUuid {
                    return true
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in changeActionsProto.promotePendingMembers {
            do {
                guard let presentationData = action.presentation else {
                    throw OWSAssertionError("Missing presentation.")
                }
                let presentation = try ProfileKeyCredentialPresentation(contents: [UInt8](presentationData))
                let uuidCiphertext = try presentation.getUuidCiphertext()
                let uuid = try groupV2Params.uuid(forUuidCiphertext: uuidCiphertext)
                if uuid == localUuid {
                    return true
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in changeActionsProto.promoteRequestingMembers {
            do {
                guard let userId = action.userID else {
                    throw OWSAssertionError("Missing userID.")
                }
                // Some userIds/uuidCiphertexts can be validated by
                // the service. This is one.
                let uuid = try groupV2Params.uuid(forUserId: userId)

                if uuid == localUuid {
                    return true
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        return false
    }
}

// MARK: - Change Cache

private extension GroupV2UpdatesImpl {

    private class ChangeCacheItem: NSObject {
        let groupChanges: [GroupV2Change]

        init(groupChanges: [GroupV2Change]) {
            self.groupChanges = groupChanges
        }
    }

    private func addGroupChangesToCache(groupChanges: [GroupV2Change], groupSecretParamsData: Data) {
        guard !groupChanges.isEmpty else {
            Logger.verbose("No group changes.")
            changeCache.removeObject(forKey: groupSecretParamsData)
            return
        }

        let revisions = groupChanges.map { $0.revision }
        Logger.verbose("Caching revisions: \(revisions)")
        changeCache.setObject(ChangeCacheItem(groupChanges: groupChanges),
                              forKey: groupSecretParamsData)
    }

    private func cachedGroupChanges(
        groupSecretParamsData: Data,
        upToRevision: UInt32?
    ) -> [GroupV2Change]? {
        guard let upToRevision = upToRevision else {
            return nil
        }
        let groupId: Data
        do {
            groupId = try groupsV2.groupId(forGroupSecretParamsData: groupSecretParamsData)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
        guard let dbRevision = (databaseStorage.read { (transaction) -> UInt32? in
            guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                return nil
            }
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                return nil
            }
            return groupModel.revision
        }) else {
            return nil
        }
        guard dbRevision < upToRevision else {
            changeCache.removeObject(forKey: groupSecretParamsData)
            return nil
        }
        guard let cacheItem = changeCache.object(forKey: groupSecretParamsData) else {
            return nil
        }
        let cachedChanges = cacheItem.groupChanges.filter { groupChange in
            let revision = groupChange.revision
            guard revision <= upToRevision else {
                return false
            }
            return revision >= dbRevision
        }
        let revisions = cachedChanges.map { $0.revision }
        guard Set(revisions).contains(upToRevision) else {
            changeCache.removeObject(forKey: groupSecretParamsData)
            return nil
        }
        Logger.verbose("Using cached revisions: \(revisions), dbRevision: \(dbRevision), upToRevision: \(upToRevision)")
        return cachedChanges
    }
}

// MARK: -

extension GroupsV2Error: IsRetryableProvider {
    public var isRetryableProvider: Bool {
        if self.isNetworkConnectivityFailure {
            return true
        }

        switch self {
        case
                .conflictingChangeOnService,
                .shouldRetry,
                .timeout,
                .newMemberMissingAnnouncementOnlyCapability:
            return true
        case
                .redundantChange,
                .shouldDiscard,
                .localUserNotInGroup,
                .cannotBuildGroupChangeProto_conflictingChange,
                .cannotBuildGroupChangeProto_lastAdminCantLeaveGroup,
                .cannotBuildGroupChangeProto_tooManyMembers,
                .gv2NotEnabled,
                .localUserIsAlreadyRequestingMember,
                .localUserIsNotARequestingMember,
                .requestingMemberCantLoadGroupState,
                .cantApplyChangesToPlaceholder,
                .expiredGroupInviteLink,
                .groupDoesNotExistOnService,
                .groupNeedsToBeMigrated,
                .groupCannotBeMigrated,
                .groupDowngradeNotAllowed,
                .missingGroupChangeProtos,
                .groupBlocked,
                .localUserBlockedFromJoining:
            return false
        case .serviceRequestHitRecoverable400:
            return false
        }
    }
}

private extension GroupV2Change {
    func author(groupV2Params: GroupV2Params) throws -> SignalServiceAddress? {
        if let changeActionsProto = changeActionsProto {
            guard let changeAuthorUuidData = changeActionsProto.sourceUuid else {
                owsFailDebug("Explicit changes should always have authors")
                return nil
            }

            let changeAuthorUuid = try groupV2Params.uuid(forUserId: changeAuthorUuidData)
            return SignalServiceAddress(uuid: changeAuthorUuid)
        }

        return nil
    }
}
