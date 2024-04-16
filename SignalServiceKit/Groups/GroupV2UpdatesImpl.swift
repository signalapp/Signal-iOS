//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class GroupV2UpdatesImpl: Dependencies {

    // This tracks the last time that groups were updated to the current
    // revision.
    private static let groupRefreshStore = SDSKeyValueStore(collection: "groupRefreshStore")

    private let changeCache = LRUCache<Data, ChangeCacheItem>(maxSize: 5)
    private var lastSuccessfulRefreshMap = LRUCache<Data, Date>(maxSize: 256)

    let immediateOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "GroupV2Updates-Immediate"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    let afterMessageProcessingOperationQueue: OperationQueue = {
        let operationQueue = OperationQueue()
        operationQueue.name = "GroupV2Updates-AfterMessageProcessing"
        operationQueue.maxConcurrentOperationCount = 1
        return operationQueue
    }()

    public init() {
        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            self.autoRefreshGroupOnLaunch()
        }
    }

    // MARK: -

    // On launch, we refresh a few randomly-selected groups.
    private func autoRefreshGroupOnLaunch() {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }

        firstly(on: DispatchQueue.global()) { () -> Guarantee<Void> in
            self.messageProcessor.waitForFetchingAndProcessing()
        }.then(on: DispatchQueue.global()) { _ -> Promise<Void> in
            guard let groupInfoToRefresh = Self.findGroupToAutoRefresh() else {
                // We didn't find a group to refresh; abort.
                return Promise.value(())
            }
            let groupId = groupInfoToRefresh.groupId
            let groupSecretParamsData = groupInfoToRefresh.groupSecretParamsData
            if let lastRefreshDate = groupInfoToRefresh.lastRefreshDate {
                Logger.info("Auto-refreshing group: \(groupId.hexadecimalString) which hasn't been refreshed in \(-lastRefreshDate.timeIntervalSinceNow/kDayInterval) days.")
            } else {
                Logger.info("Auto-refreshing group: \(groupId.hexadecimalString) which has never been refreshed.")
            }
            return self.tryToRefreshV2GroupUpToCurrentRevisionImmediately(
                groupId: groupId,
                groupSecretParamsData: groupSecretParamsData
            ).asVoid()
        }.catch(on: DispatchQueue.global()) { error in
            if case GroupsV2Error.localUserNotInGroup = error {
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebugUnlessNetworkFailure(error)
            }
        }
    }

    private func didUpdateGroupToCurrentRevision(groupId: Data) {
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
                    groupInfoToRefresh = GroupInfo(
                        groupId: groupThread.groupId,
                        groupSecretParamsData: groupModel.secretParamsData,
                        lastRefreshDate: nil
                    )
                    stop.pointee = true
                    return
                }

                // Don't auto-refresh groups more than once a week.
                let maxRefreshFrequencyInternal: TimeInterval = kWeekInterval
                guard abs(lastRefreshDate.timeIntervalSinceNow) > maxRefreshFrequencyInternal else {
                    return
                }

                if
                    let otherGroupInfo = groupInfoToRefresh,
                    let otherLastRefreshDate = otherGroupInfo.lastRefreshDate,
                    otherLastRefreshDate < lastRefreshDate
                {
                    // We already found another group with an older refresh
                    // date, so prefer that one.
                    return
                }

                groupInfoToRefresh = GroupInfo(
                    groupId: groupThread.groupId,
                    groupSecretParamsData: groupModel.secretParamsData,
                    lastRefreshDate: lastRefreshDate
                )
            }
            return groupInfoToRefresh
        }
    }
}

// MARK: - GroupV2UpdatesSwift

extension GroupV2UpdatesImpl: GroupV2Updates {

    public func updateGroupWithChangeActions(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
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
        guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
            throw OWSAssertionError("Not registered.")
        }
        let changedGroupModel = try GroupsV2IncomingChanges.applyChangesToGroupModel(
            groupThread: groupThread,
            localIdentifiers: localIdentifiers,
            changeActionsProto: changeActionsProto,
            downloadedAvatars: downloadedAvatars,
            groupModelOptions: []
        )
        guard changedGroupModel.newGroupModel.revision > changedGroupModel.oldGroupModel.revision else {
            throw OWSAssertionError("Invalid groupV2Revision: \(changedGroupModel.newGroupModel.revision).")
        }

        let updatedGroupThread = try GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
            newGroupModel: changedGroupModel.newGroupModel,
            newDisappearingMessageToken: changedGroupModel.newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: changedGroupModel.newlyLearnedPniToAciAssociations,
            groupUpdateSource: changedGroupModel.updateSource,
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: spamReportingMetadata,
            transaction: transaction
        )

        let authoritativeProfileKeys = changedGroupModel.profileKeys.filter {
            $0.key == changedGroupModel.updateSource.serviceIdUnsafeForLocalUserComparison()
        }
        GroupManager.storeProfileKeysFromGroupProtos(
            allProfileKeysByAci: changedGroupModel.profileKeys,
            authoritativeProfileKeysByAci: authoritativeProfileKeys
        )

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
                                         spamReportingMetadata: .learnedByLocallyInitatedRefresh,
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
                                         spamReportingMetadata: .learnedByLocallyInitatedRefresh,
                                         groupSecretParamsData: groupSecretParamsData,
                                         groupUpdateMode: groupUpdateMode,
                                         groupModelOptions: groupModelOptions)
    }

    public func tryToRefreshV2GroupThread(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupSecretParamsData: Data,
        groupUpdateMode: GroupUpdateMode
    ) -> Promise<TSGroupThread> {
        tryToRefreshV2GroupThread(groupId: groupId,
                                  spamReportingMetadata: spamReportingMetadata,
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

        firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                return Promise.value(())
            }
            let groupId = groupModel.groupId
            let groupSecretParamsData = groupModel.secretParamsData
            return self.tryToRefreshV2GroupThread(
                groupId: groupId,
                spamReportingMetadata: .learnedByLocallyInitatedRefresh,
                groupSecretParamsData: groupSecretParamsData,
                groupUpdateMode: groupUpdateMode
            ).asVoid()
        }.catch(on: DispatchQueue.global()) { error in
            Logger.warn("Group refresh failed: \(error).")
        }
    }

    private func tryToRefreshV2GroupThread(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
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
                return Promise.value(thread)
            } else {
                return nil
            }
        }

        if let earlyPromise = earlyPromise {
            return earlyPromise
        }

        let operation = GroupV2UpdateOperation(groupId: groupId,
                                               spamReportingMetadata: spamReportingMetadata,
                                               groupSecretParamsData: groupSecretParamsData,
                                               groupUpdateMode: groupUpdateMode,
                                               groupModelOptions: groupModelOptions)
        operation.promise.done(on: DispatchQueue.global()) { _ in
            self.groupRefreshDidSucceed(forGroupId: groupId, groupUpdateMode: groupUpdateMode)
        }.cauterize()
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

    private class GroupV2UpdateOperation: OWSOperation, Dependencies {

        let groupId: Data
        let groupSecretParamsData: Data
        let groupUpdateMode: GroupUpdateMode
        let groupModelOptions: TSGroupModelOptions
        let spamReportingMetadata: GroupUpdateSpamReportingMetadata

        let promise: Promise<TSGroupThread>
        let future: Future<TSGroupThread>

        init(groupId: Data,
             spamReportingMetadata: GroupUpdateSpamReportingMetadata,
             groupSecretParamsData: Data,
             groupUpdateMode: GroupUpdateMode,
             groupModelOptions: TSGroupModelOptions) {
            self.groupId = groupId
            self.spamReportingMetadata = spamReportingMetadata
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
            firstly { () -> Guarantee<Void> in
                if groupUpdateMode.shouldBlockOnMessageProcessing {
                    return self.messageProcessor.waitForFetchingAndProcessing()
                } else {
                    return Guarantee.value(())
                }
            }.then(on: DispatchQueue.global()) { () in
                self.groupV2UpdatesImpl.refreshGroupFromService(groupSecretParamsData: self.groupSecretParamsData,
                                                                groupUpdateMode: self.groupUpdateMode,
                                                                groupModelOptions: self.groupModelOptions,
                                                                spamReportingMetadata: self.spamReportingMetadata)
            }.done(on: DispatchQueue.global()) { (groupThread: TSGroupThread) in
                self.reportSuccess()
                self.future.resolve(groupThread)
            }.catch(on: DispatchQueue.global()) { (error) in
                if error.isNetworkFailureOrTimeout {
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
        groupModelOptions: TSGroupModelOptions,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata
    ) -> Promise<TSGroupThread> {

        return firstly {
            Promise.wrapAsync {
                try await GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
            }
        }.then(on: DispatchQueue.global()) { () throws -> Promise<TSGroupThread> in
            // Try to use individual changes.
            return firstly(on: DispatchQueue.global()) {
                self.fetchAndApplyChangeActionsFromService(groupSecretParamsData: groupSecretParamsData,
                                                           groupUpdateMode: groupUpdateMode,
                                                           groupModelOptions: groupModelOptions,
                                                           spamReportingMetadata: spamReportingMetadata)
                    .timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                             description: "Update via changes") {
                        GroupsV2Error.timeout
                    }
            }.recover { (error) throws -> Promise<TSGroupThread> in
                let shouldTrySnapshot = { () -> Bool in
                    // This should not fail over in the case of networking problems.
                    if error.isNetworkFailureOrTimeout {
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
                    case GroupsV2Error.groupChangeProtoForIncompatibleRevision:
                        // If we got change protos for an incompatible revision,
                        // try and recover using a snapshot.
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
                    groupModelOptions: groupModelOptions,
                    spamReportingMetadata: spamReportingMetadata
                )
            }
        }
    }

    private func fetchAndApplyChangeActionsFromService(
        groupSecretParamsData: Data,
        groupUpdateMode: GroupUpdateMode,
        groupModelOptions: TSGroupModelOptions,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata
    ) -> Promise<TSGroupThread> {

        return firstly { () -> Promise<GroupsV2Impl.GroupChangePage> in
            self.fetchChangeActionsFromService(groupSecretParamsData: groupSecretParamsData,
                                               groupUpdateMode: groupUpdateMode)
        }.then(on: DispatchQueue.global()) { (groupChanges: GroupsV2Impl.GroupChangePage) throws -> Promise<TSGroupThread> in
            let groupId = try self.groupsV2.groupId(forGroupSecretParamsData: groupSecretParamsData)
            let applyPromise = self.tryToApplyGroupChangesFromService(
                groupId: groupId,
                spamReportingMetadata: spamReportingMetadata,
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
                    groupModelOptions: groupModelOptions,
                    spamReportingMetadata: spamReportingMetadata
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

        return firstly(on: DispatchQueue.global()) { () -> [GroupV2Change]? in
            // Try to use group changes from the cache.
            return self.cachedGroupChanges(groupSecretParamsData: groupSecretParamsData,
                                           upToRevision: upToRevision)
        }.then(on: DispatchQueue.global()) { (groupChanges: [GroupV2Change]?) -> Promise<GroupsV2Impl.GroupChangePage> in
            if let groupChanges = groupChanges {
                return Promise.value(GroupsV2Impl.GroupChangePage(changes: groupChanges, earlyEnd: nil))
            }
            return firstly {
                return Promise.wrapAsync {
                    try await self.groupsV2Impl.fetchGroupChangeActions(
                        groupSecretParamsData: groupSecretParamsData,
                        includeCurrentRevision: includeCurrentRevision
                    )
                }
            }.map(on: DispatchQueue.global()) { (groupChanges: GroupsV2Impl.GroupChangePage) -> GroupsV2Impl.GroupChangePage in
                self.addGroupChangesToCache(groupChanges: groupChanges.changes,
                                            groupSecretParamsData: groupSecretParamsData)

                return groupChanges
            }
        }
    }

    private func tryToApplyGroupChangesFromService(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupSecretParamsData: Data,
        groupChanges: [GroupV2Change],
        groupUpdateMode: GroupUpdateMode,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {
        return firstly { () -> Guarantee<Void> in
            if groupUpdateMode.shouldBlockOnMessageProcessing {
                return self.messageProcessor.waitForFetchingAndProcessing()
            } else {
                return Guarantee.value(())
            }
        }.then(on: DispatchQueue.global()) {
            return self.tryToApplyGroupChangesFromServiceNow(
                groupId: groupId,
                spamReportingMetadata: spamReportingMetadata,
                groupSecretParamsData: groupSecretParamsData,
                groupChanges: groupChanges,
                upToRevision: groupUpdateMode.upToRevision,
                groupModelOptions: groupModelOptions
            )
        }
    }

    private func tryToApplyGroupChangesFromServiceNow(
        groupId: Data,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupSecretParamsData: Data,
        groupChanges: [GroupV2Change],
        upToRevision: UInt32?,
        groupModelOptions: TSGroupModelOptions
    ) -> Promise<TSGroupThread> {
        return databaseStorage.write(.promise) { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }

            let groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)

            // See comment on getOrCreateThreadForGroupChanges(...).
            guard var (groupThread, localUserWasAddedBy) = self.getOrCreateThreadForGroupChanges(
                groupId: groupId,
                spamReportingMetadata: spamReportingMetadata,
                groupV2Params: groupV2Params,
                groupChanges: groupChanges,
                groupModelOptions: groupModelOptions,
                localIdentifiers: localIdentifiers,
                transaction: transaction
            ) else {
                throw OWSAssertionError("Missing group thread.")
            }

            if groupChanges.count < 1 {
                return groupThread
            }

            var profileKeysByAci = [Aci: Data]()
            var authoritativeProfileKeysByAci = [Aci: Data]()
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
                        profileKeysByAci: &profileKeysByAci,
                        authoritativeProfileKeysByAci: &authoritativeProfileKeysByAci,
                        localIdentifiers: localIdentifiers,
                        spamReportingMetadata: spamReportingMetadata,
                        transaction: transaction
                    )
                }

                if
                    let applyResult = applyResult,
                    applyResult.wasLocalUserAddedByChange
                {
                    owsAssertDebug(
                        localUserWasAddedBy == .unknown || applyResult.changeAuthor == .unknown || (index == 0 && localUserWasAddedBy == applyResult.changeAuthor),
                        "Multiple change actions added the user to the group"
                    )
                    localUserWasAddedBy = applyResult.changeAuthor
                }
            }

            GroupManager.storeProfileKeysFromGroupProtos(
                allProfileKeysByAci: profileKeysByAci,
                authoritativeProfileKeysByAci: authoritativeProfileKeysByAci
            )

            let localUserWasAddedByBlockedUser: Bool
            switch localUserWasAddedBy {
            case nil, .unknown, .localUser:
                localUserWasAddedByBlockedUser = false
            case .legacyE164(let e164):
                localUserWasAddedByBlockedUser = self.blockingManager.isAddressBlocked(
                    .legacyAddress(serviceId: nil, phoneNumber: e164.stringValue),
                    transaction: transaction
                )
            case .aci(let aci):
                localUserWasAddedByBlockedUser = self.blockingManager.isAddressBlocked(
                    .init(aci),
                    transaction: transaction
                )
            case .rejectedInviteToPni:
                owsFailDebug("Local user added, but group update source was a PNI invite decline?")
                localUserWasAddedByBlockedUser = false
            }

            if localUserWasAddedByBlockedUser {
                // If we have been added to the group by a blocked user, we
                // should automatically leave the group. To that end, enqueue
                // a leave action after we've finished processing messages.
                _ = GroupManager.localLeaveGroupOrDeclineInvite(
                    groupThread: groupThread,
                    waitForMessageProcessing: true,
                    tx: transaction
                )
            } else if
                let profileKey = profileKeysByAci[localIdentifiers.aci],
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
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        groupV2Params: GroupV2Params,
        groupChanges: [GroupV2Change],
        groupModelOptions: TSGroupModelOptions,
        localIdentifiers: LocalIdentifiers,
        transaction: SDSAnyWriteTransaction
    ) -> (TSGroupThread, addedToNewThreadBy: GroupUpdateSource?)? {

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

            let groupUpdateSource = try firstGroupChange.author(
                groupV2Params: groupV2Params,
                localIdentifiers: localIdentifiers
            )

            var builder = try TSGroupModelBuilder.builderForSnapshot(
                groupV2Snapshot: snapshot,
                transaction: transaction
            )
            builder.apply(options: groupModelOptions)

            let newGroupModel = try builder.build()

            let newDisappearingMessageToken = snapshot.disappearingMessageToken
            let didAddLocalUserToV2Group = self.didAddLocalUserToV2Group(
                inGroupChange: firstGroupChange,
                groupV2Params: groupV2Params,
                localIdentifiers: localIdentifiers
            )

            let groupThread = try GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
                newGroupModel: newGroupModel,
                newDisappearingMessageToken: newDisappearingMessageToken,
                newlyLearnedPniToAciAssociations: [:],
                groupUpdateSource: groupUpdateSource,
                didAddLocalUserToV2Group: didAddLocalUserToV2Group,
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                transaction: transaction
            )

            // NOTE: We don't need to worry about profile keys here.  This method is
            // only used by tryToApplyGroupChangesFromServiceNow() which will take
            // care of that.

            return (
                groupThread,
                addedToNewThreadBy: didAddLocalUserToV2Group ? groupUpdateSource : nil
            )
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    private struct ApplySingleChangeFromServiceResult {
        let changeAuthor: GroupUpdateSource
        let wasLocalUserAddedByChange: Bool
    }

    private func tryToApplySingleChangeFromService(
        groupThread: inout TSGroupThread,
        groupV2Params: GroupV2Params,
        groupModelOptions: TSGroupModelOptions,
        groupChange: GroupV2Change,
        isFirstChange: Bool,
        profileKeysByAci: inout [Aci: Data],
        authoritativeProfileKeysByAci: inout [Aci: Data],
        localIdentifiers: LocalIdentifiers,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata,
        transaction: SDSAnyWriteTransaction
    ) throws -> ApplySingleChangeFromServiceResult? {
        guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
            throw OWSAssertionError("Invalid group model.")
        }

        let oldRevision = oldGroupModel.revision
        let changeRevision = groupChange.revision
        let isSingleRevisionUpdate = oldRevision + 1 == changeRevision

        let logger = PrefixedLogger(
            prefix: "ApplySingleChange",
            suffix: "\(oldRevision) -> \(changeRevision)"
        )

        // We should only replace placeholder models using
        // latest snapshots _except_ in the case where the
        // local user is a requesting member and the first
        // change action approves their request to join the
        // group.
        if oldGroupModel.isJoinRequestPlaceholder {
            guard isFirstChange else {
                throw GroupsV2Error.cantApplyChangesToPlaceholder
            }
            guard isSingleRevisionUpdate else {
                throw GroupsV2Error.cantApplyChangesToPlaceholder
            }
            guard groupChange.snapshot != nil else {
                throw GroupsV2Error.cantApplyChangesToPlaceholder
            }
            guard oldGroupModel.groupMembership.isRequestingMember(localIdentifiers.aci) else {
                throw GroupsV2Error.cantApplyChangesToPlaceholder
            }
        }

        let newGroupModel: TSGroupModel
        let newDisappearingMessageToken: DisappearingMessageToken?
        let newProfileKeys: [Aci: Data]
        let newlyLearnedPniToAciAssociations: [Pni: Aci]
        let groupUpdateSource: GroupUpdateSource

        // We should prefer to update models using the change action if we can,
        // since it contains information about the change author.
        if
            isSingleRevisionUpdate,
            let changeActionsProto = groupChange.changeActionsProto
        {
            logger.info("Applying single revision update from change proto.")

            let changedGroupModel = try GroupsV2IncomingChanges.applyChangesToGroupModel(
                groupThread: groupThread,
                localIdentifiers: localIdentifiers,
                changeActionsProto: changeActionsProto,
                downloadedAvatars: groupChange.downloadedAvatars,
                groupModelOptions: groupModelOptions
            )
            newGroupModel = changedGroupModel.newGroupModel
            newDisappearingMessageToken = changedGroupModel.newDisappearingMessageToken
            newProfileKeys = changedGroupModel.profileKeys
            newlyLearnedPniToAciAssociations = changedGroupModel.newlyLearnedPniToAciAssociations
            groupUpdateSource = changedGroupModel.updateSource
        } else if let snapshot = groupChange.snapshot {
            logger.info("Applying snapshot.")

            var builder = try TSGroupModelBuilder.builderForSnapshot(groupV2Snapshot: snapshot,
                                                                     transaction: transaction)
            builder.apply(options: groupModelOptions)
            newGroupModel = try builder.build()
            newDisappearingMessageToken = snapshot.disappearingMessageToken
            newProfileKeys = snapshot.profileKeys
            newlyLearnedPniToAciAssociations = [:]
            // Snapshots don't have a single author, so we don't know the source.
            groupUpdateSource = .unknown
        } else if groupChange.changeActionsProto != nil {
            logger.info("Change action proto was not a single revision update.")

            // We had a group change proto with no snapshot, but the change was
            // not a single revision update.
            throw GroupsV2Error.groupChangeProtoForIncompatibleRevision
        } else {
            owsFailDebug("neither a snapshot nor a change action (should have been validated earlier)")
            return nil
        }

        // We should only replace placeholder models using
        // _latest_ snapshots _except_ in the case where the
        // local user is a requesting member and the first
        // change action approves their request to join the
        // group.
        if oldGroupModel.isJoinRequestPlaceholder {
            guard newGroupModel.groupMembership.isFullMember(localIdentifiers.aci) else {
                throw GroupsV2Error.cantApplyChangesToPlaceholder
            }
        }

        groupThread = try GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(
            newGroupModel: newGroupModel,
            newDisappearingMessageToken: newDisappearingMessageToken,
            newlyLearnedPniToAciAssociations: newlyLearnedPniToAciAssociations,
            groupUpdateSource: groupUpdateSource,
            localIdentifiers: localIdentifiers,
            spamReportingMetadata: spamReportingMetadata,
            transaction: transaction
        )

        switch groupUpdateSource {
        case .unknown, .legacyE164, .rejectedInviteToPni, .localUser:
            break
        case .aci(let groupUpdateSourceAci):
            if let groupUpdateProfileKey = newProfileKeys[groupUpdateSourceAci] {
                authoritativeProfileKeysByAci[groupUpdateSourceAci] = groupUpdateProfileKey
            }
        }

        // Merge known profile keys, always taking latest.
        profileKeysByAci.merge(newProfileKeys) { (_, latest) in latest }

        return ApplySingleChangeFromServiceResult(
            changeAuthor: groupUpdateSource,
            wasLocalUserAddedByChange: didAddLocalUserToV2Group(
                inGroupChange: groupChange,
                groupV2Params: groupV2Params,
                localIdentifiers: localIdentifiers
            )
        )
    }
}

// MARK: - Current Snapshot

private extension GroupV2UpdatesImpl {

    func fetchAndApplyCurrentGroupV2SnapshotFromService(
        groupSecretParamsData: Data,
        groupUpdateMode: GroupUpdateMode,
        groupModelOptions: TSGroupModelOptions,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata
    ) -> Promise<TSGroupThread> {

        return firstly {
            Promise.wrapAsync {
                try await self.groupsV2Impl.fetchCurrentGroupV2Snapshot(groupSecretParamsData: groupSecretParamsData)
            }
        }.then(on: DispatchQueue.global()) { groupV2Snapshot in
            return self.tryToApplyCurrentGroupV2SnapshotFromService(
                groupV2Snapshot: groupV2Snapshot,
                groupUpdateMode: groupUpdateMode,
                groupModelOptions: groupModelOptions,
                spamReportingMetadata: spamReportingMetadata
            )
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: "Update via snapshot") {
            GroupsV2Error.timeout
        }
    }

    private func tryToApplyCurrentGroupV2SnapshotFromService(
        groupV2Snapshot: GroupV2Snapshot,
        groupUpdateMode: GroupUpdateMode,
        groupModelOptions: TSGroupModelOptions,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata
    ) -> Promise<TSGroupThread> {

        return firstly { () -> Guarantee<Void> in
            if groupUpdateMode.shouldBlockOnMessageProcessing {
                return self.messageProcessor.waitForFetchingAndProcessing()
            } else {
                return Guarantee.value(())
            }
        }.then(on: DispatchQueue.global()) { () in
            self.tryToApplyCurrentGroupV2SnapshotFromServiceNow(
                groupV2Snapshot: groupV2Snapshot,
                groupModelOptions: groupModelOptions,
                spamReportingMetadata: spamReportingMetadata
            )
        }
    }

    private func tryToApplyCurrentGroupV2SnapshotFromServiceNow(
        groupV2Snapshot: GroupV2Snapshot,
        groupModelOptions: TSGroupModelOptions,
        spamReportingMetadata: GroupUpdateSpamReportingMetadata
    ) -> Promise<TSGroupThread> {

        let localProfileKey = profileManager.localProfileKey()

        return databaseStorage.write(.promise) { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
            guard let localIdentifiers = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read) else {
                throw OWSAssertionError("Missing localIdentifiers.")
            }
            let localAci = localIdentifiers.aci

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
            // groupUpdateSource is unknown because we don't know the
            // author(s) of changes reflected in the snapshot.
            let groupUpdateSource: GroupUpdateSource = .unknown
            let groupThread = try GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(
                newGroupModel: newGroupModel,
                newDisappearingMessageToken: newDisappearingMessageToken,
                newlyLearnedPniToAciAssociations: [:], // Not available from snapshots
                groupUpdateSource: groupUpdateSource,
                didAddLocalUserToV2Group: false,
                localIdentifiers: localIdentifiers,
                spamReportingMetadata: spamReportingMetadata,
                transaction: transaction
            )

            GroupManager.storeProfileKeysFromGroupProtos(
                allProfileKeysByAci: groupV2Snapshot.profileKeys,
                authoritativeProfileKeysByAci: nil
            )

            // If the group state includes a stale profile key for the
            // local user, schedule an update to fix that.
            if let profileKey = groupV2Snapshot.profileKeys[localAci], profileKey != localProfileKey.keyData {
                self.groupsV2.updateLocalProfileKeyInGroup(groupId: newGroupModel.groupId, transaction: transaction)
            }

            return groupThread
        }
    }

    private func didAddLocalUserToV2Group(
        inGroupChange groupChange: GroupV2Change,
        groupV2Params: GroupV2Params,
        localIdentifiers: LocalIdentifiers
    ) -> Bool {
        let localAci = localIdentifiers.aci
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
                let aci = try groupV2Params.aci(for: userId)
                if aci == localAci {
                    return true
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in changeActionsProto.promotePendingMembers {
            do {
                let uuidCiphertext: UuidCiphertext
                if let userId = action.userID {
                    uuidCiphertext = try UuidCiphertext(contents: [UInt8](userId))
                } else if let presentationData = action.presentation {
                    let presentation = try ProfileKeyCredentialPresentation(contents: [UInt8](presentationData))
                    uuidCiphertext = try presentation.getUuidCiphertext()
                } else {
                    throw OWSAssertionError("Missing userId.")
                }

                let aci = try groupV2Params.serviceId(for: uuidCiphertext)
                if aci == localAci {
                    return true
                }
            } catch {
                owsFailDebug("Error: \(error)")
            }
        }
        for action in changeActionsProto.promotePniPendingMembers {
            do {
                guard let userId = action.userID else {
                    throw OWSAssertionError("Missing userID.")
                }
                let aci = try groupV2Params.aci(for: userId)
                if aci == localAci {
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
                let aci = try groupV2Params.aci(for: userId)
                if aci == localAci {
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
            changeCache.removeObject(forKey: groupSecretParamsData)
            return
        }

        changeCache.setObject(ChangeCacheItem(groupChanges: groupChanges), forKey: groupSecretParamsData)
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
        return cachedChanges
    }
}

// MARK: -

extension GroupsV2Error: IsRetryableProvider {
    public var isRetryableProvider: Bool {
        if self.isNetworkFailureOrTimeout {
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
                .localUserBlockedFromJoining,
                .groupChangeProtoForIncompatibleRevision,
                .serviceRequestHitRecoverable400:
            return false
        }
    }
}

private extension GroupV2Change {
    func author(
        groupV2Params: GroupV2Params,
        localIdentifiers: LocalIdentifiers
    ) throws -> GroupUpdateSource {
        if let changeActionsProto = changeActionsProto {
            return try changeActionsProto.updateSource(
                groupV2Params: groupV2Params,
                localIdentifiers: localIdentifiers
            ).0
        }
        return .unknown
    }
}

public extension GroupsProtoGroupChangeActions {

    func updateSource(
        groupV2Params: GroupV2Params,
        localIdentifiers: LocalIdentifiers
    ) throws -> (GroupUpdateSource, ServiceId?) {
        func compareToLocal(
            source: GroupUpdateSource,
            serviceId: ServiceId
        ) -> (GroupUpdateSource, ServiceId) {
            if localIdentifiers.contains(serviceId: serviceId) {
                return (.localUser(originalSource: source), serviceId)
            }

            return (source, serviceId)
        }

        guard let changeAuthorUserId: Data = self.sourceUserID else {
            owsFailDebug("Explicit changes should always have authors")
            return (.unknown, nil)
        }

        let serviceId = try groupV2Params.serviceId(for: changeAuthorUserId)
        switch serviceId.concreteType {
        case .aci(let aci):
            return compareToLocal(
                source: .aci(aci),
                serviceId: aci
            )
        case .pni(let pni):
            /// At the time of writing, the only change actions with a PNI
            /// author are accepting or declining a PNI invite.
            ///
            /// If future updates to change actions introduce more actions with
            /// PNI authors, differentiate them here. The best time to
            /// differentiate is when we have access to the raw change actions.
            if
                self.deletePendingMembers.count == 1,
                let firstDeletePendingMember = self.deletePendingMembers.first,
                let firstDeletePendingMemberUserId = firstDeletePendingMember.deletedUserID,
                let firstDeletePendingMemberPni = try? groupV2Params.serviceId(for: firstDeletePendingMemberUserId) as? Pni
            {
                guard firstDeletePendingMemberPni == pni else {
                    owsFailDebug("Canary: PNI from change author doesn't match service ID in delete pending member change action!")
                    return (.unknown, nil)
                }

                return compareToLocal(
                    source: .rejectedInviteToPni(pni),
                    serviceId: pni
                )
            } else if
                self.promotePniPendingMembers.count == 1,
                let firstPromotePniPendingMember = self.promotePniPendingMembers.first,
                let firstPromotePniPendingMemberAciUserId = firstPromotePniPendingMember.userID,
                let firstPromotePniPendingMemberAci = try? groupV2Params.serviceId(for: firstPromotePniPendingMemberAciUserId) as? Aci,
                let firstPromotePniPendingMemberPniUserId = firstPromotePniPendingMember.pni,
                let firstPromotePniPendingMemberPni = try? groupV2Params.serviceId(for: firstPromotePniPendingMemberPniUserId) as? Pni
            {
                guard firstPromotePniPendingMemberPni == pni else {
                    owsFailDebug("Canary: PNI from change author doesn't match service ID in promote PNI pending member change action!")
                    return (.unknown, nil)
                }

                /// While the service ID we received as the group update source
                /// from the server was a PNI, we know (thanks to the change
                /// action itself) the associated ACI. Since the ACI is how
                /// we're going to address this user going forward, we'll
                /// claim starting now that's who authored the change action.
                return compareToLocal(
                    source: .aci(firstPromotePniPendingMemberAci),
                    serviceId: firstPromotePniPendingMemberAci
                )
            } else {
                owsFailDebug("Canary: unknown type of PNI-authored group update!")
                return (.unknown, nil)
            }
        }
    }
}
