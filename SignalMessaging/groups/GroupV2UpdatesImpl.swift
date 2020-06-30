//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit
import SignalServiceKit
import ZKGroup

@objc
public class GroupV2UpdatesImpl: NSObject, GroupV2UpdatesSwift {

    // MARK: - Dependencies

    private var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    private var messageProcessing: MessageProcessing {
        return SSKEnvironment.shared.messageProcessing
    }

    private var groupsV2: GroupsV2Swift {
        return SSKEnvironment.shared.groupsV2 as! GroupsV2Swift
    }

    private var tsAccountManager: TSAccountManager {
        return TSAccountManager.sharedInstance()
    }

    private var profileManager: OWSProfileManager {
        return OWSProfileManager.shared()
    }

    // MARK: -

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: -

    private let serialQueue = DispatchQueue(label: "GroupV2UpdatesImpl")

    // This property should only be accessed on serialQueue.
    private var lastSuccessfulRefreshMap = [Data: Date]()

    private func lastSuccessfulRefreshDate(forGroupId  groupId: Data) -> Date? {
        assertOnQueue(serialQueue)

        return lastSuccessfulRefreshMap[groupId]
    }

    private func groupRefreshDidSucceed(forGroupId groupId: Data) {
        assertOnQueue(serialQueue)

        lastSuccessfulRefreshMap[groupId] = Date()
    }

    // MARK: -

    public func tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: Data,
                                                                  groupSecretParamsData: Data) -> Promise<Void> {
        let groupUpdateMode = GroupUpdateMode.upToCurrentRevisionImmediately
        return tryToRefreshV2GroupThread(groupId: groupId,
                                         groupSecretParamsData: groupSecretParamsData,
                                         groupUpdateMode: groupUpdateMode)
    }

    @objc
    public func tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(_ groupThread: TSGroupThread) {
        let groupUpdateMode = GroupUpdateMode.upToCurrentRevisionAfterMessageProcessWithThrottling
        tryToRefreshV2GroupThread(groupThread, groupUpdateMode: groupUpdateMode)
    }

    @objc
    public func tryToRefreshV2GroupUpToSpecificRevisionImmediately(_ groupThread: TSGroupThread,
                                                                   upToRevision: UInt32) {
        let groupUpdateMode = GroupUpdateMode.upToSpecificRevisionImmediately(upToRevision: upToRevision)
        tryToRefreshV2GroupThread(groupThread, groupUpdateMode: groupUpdateMode)
    }

    private func tryToRefreshV2GroupThread(_ groupThread: TSGroupThread,
                                           groupUpdateMode: GroupUpdateMode) {
        firstly { () -> Promise<Void> in
            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                return Promise.value(())
            }
            let groupId = groupModel.groupId
            let groupSecretParamsData = groupModel.secretParamsData
            return tryToRefreshV2GroupThread(groupId: groupId,
                                             groupSecretParamsData: groupSecretParamsData,
                                             groupUpdateMode: groupUpdateMode)
        }.catch(on: .global()) { error in
            Logger.warn("Group refresh failed: \(error).")
        }
    }

    public func tryToRefreshV2GroupThread(groupId: Data,
                                          groupSecretParamsData: Data,
                                          groupUpdateMode: GroupUpdateMode) -> Promise<Void> {

        let isThrottled = serialQueue.sync { () -> Bool in
            guard groupUpdateMode.shouldThrottle else {
                return false
            }
            guard let lastSuccessfulRefreshDate = self.lastSuccessfulRefreshDate(forGroupId: groupId) else {
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

        let operation = GroupV2UpdateOperation(groupV2Updates: self,
                                               groupId: groupId,
                                               groupSecretParamsData: groupSecretParamsData,
                                               groupUpdateMode: groupUpdateMode)
        operation.promise.done(on: .global()) { _ in
            Logger.verbose("Group refresh succeeded.")

            self.serialQueue.sync {
                self.groupRefreshDidSucceed(forGroupId: groupId)
            }
        }.catch(on: .global()) { error in
            Logger.verbose("Group refresh failed: \(error).")
        }
        let operationQueue = self.operationQueue(forGroupUpdateMode: groupUpdateMode)
        operationQueue.addOperation(operation)
        return operation.promise
    }

    public func operationQueue(forGroupUpdateMode groupUpdateMode: GroupUpdateMode) -> OperationQueue {
        if groupUpdateMode.shouldBlockOnMessageProcessing {
            return afterMessageProcessingOperationQueue
        } else {
            return immediateOperationQueue
        }
    }

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

    private class GroupV2UpdateOperation: OWSOperation {

        // MARK: - Dependencies

        private var databaseStorage: SDSDatabaseStorage {
            return SDSDatabaseStorage.shared
        }

        private var tsAccountManager: TSAccountManager {
            return TSAccountManager.sharedInstance()
        }

        private var messageProcessing: MessageProcessing {
            return SSKEnvironment.shared.messageProcessing
        }

        // MARK: -

        let groupV2Updates: GroupV2UpdatesImpl
        let groupId: Data
        let groupSecretParamsData: Data
        let groupUpdateMode: GroupUpdateMode

        let promise: Promise<Void>
        let resolver: Resolver<Void>

        // MARK: -

        required init(groupV2Updates: GroupV2UpdatesImpl,
                      groupId: Data,
                      groupSecretParamsData: Data,
                      groupUpdateMode: GroupUpdateMode) {
            self.groupV2Updates = groupV2Updates
            self.groupId = groupId
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
            firstly { () -> Promise<Void> in
                if groupUpdateMode.shouldBlockOnMessageProcessing {
                    return self.messageProcessing.allMessageFetchingAndProcessingPromise()
                } else {
                    return Promise.value(())
                }
            }.then(on: .global()) { _ in
                self.groupV2Updates.refreshGroupFromService(groupSecretParamsData: self.groupSecretParamsData,
                                                            groupUpdateMode: self.groupUpdateMode)
            }.done(on: .global()) { _ in
                Logger.verbose("Group refresh succeeded.")

                self.reportSuccess()
            }.catch(on: .global()) { (error) in

                let nsError: NSError = error as NSError
                if case GroupsV2Error.unauthorized = error {
                    if self.shouldIgnoreAuthFailures {
                        Logger.warn("Group refresh failed: \(error)")
                        nsError.isRetryable = false
                    } else {
                        owsFailDebug("Group refresh failed: \(error)")
                        nsError.isRetryable = true
                    }
                } else if case GroupsV2Error.localUserNotInGroup = error {
                    Logger.warn("Local user not in group: \(error)")
                    nsError.isRetryable = false
                } else if IsNetworkConnectivityFailure(error) {
                    Logger.warn("Group refresh failed: \(error)")
                    nsError.isRetryable = true
                } else if case GroupsV2Error.timeout = error {
                    Logger.warn("Group refresh timed out: \(error)")
                    nsError.isRetryable = true
                } else {
                    owsFailDebug("Group refresh failed: \(error)")
                    nsError.isRetryable = true
                }

                self.reportError(nsError)
            }
        }

        private var shouldIgnoreAuthFailures: Bool {
            return self.databaseStorage.read { transaction in
                guard let groupThread = TSGroupThread.fetch(groupId: self.groupId, transaction: transaction) else {
                    // The thread may have been deleted while the refresh was in flight.
                    Logger.warn("Missing group thread.")
                    return true
                }
                guard let localAddress = self.tsAccountManager.localAddress else {
                    owsFailDebug("Missing localAddress.")
                    return false
                }
                let isLocalUserInGroup = groupThread.groupModel.groupMembership.isPendingOrNonPendingMember(localAddress)
                // Auth errors are expected if we've left the group,
                // but we should still try to refresh so we can learn
                // if we've been re-added.
                return !isLocalUserInGroup
            }
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
    private func refreshGroupFromService(groupSecretParamsData: Data,
                                         groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {

        return firstly {
            return GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
        }.then(on: DispatchQueue.global()) { () throws -> Promise<TSGroupThread> in
            // Try to use individual changes.
            return self.fetchAndApplyChangeActionsFromService(groupSecretParamsData: groupSecretParamsData,
                                                              groupUpdateMode: groupUpdateMode)
                .recover { (error) throws -> Promise<TSGroupThread> in
                    let shouldTrySnapshot = { () -> Bool in
                        // This should not fail over in the case of networking problems.
                        if IsNetworkConnectivityFailure(error) {
                            Logger.warn("Error: \(error)")
                            return false
                        }

                        switch error {
                        case GroupsV2Error.groupNotInDatabase:
                            // Unknown groups are handled by snapshot.
                            return true
                        case GroupsV2Error.unauthorized,
                             GroupsV2Error.localUserNotInGroup:
                            // We can recover from some auth edge cases
                            // using a snapshot.
                            return true
                        default:
                            owsFailDebug("Error: \(error)")
                            return false
                        }
                    }()

                    guard shouldTrySnapshot else {
                        throw error
                    }

                    // Failover to applying latest snapshot.
                    return self.fetchAndApplyCurrentGroupV2SnapshotFromService(groupSecretParamsData: groupSecretParamsData,
                                                                               groupUpdateMode: groupUpdateMode)
            }
        }.map(on: DispatchQueue.global()) { (groupThread: TSGroupThread) -> TSGroupThread in
            GroupManager.updateProfileWhitelist(withGroupThread: groupThread)
            return groupThread
        }
    }

    // MARK: - Group Changes

    public func updateGroupWithChangeActions(groupId: Data,
                                             changeActionsProto: GroupsProtoGroupChangeActions,
                                             downloadedAvatars: GroupV2DownloadedAvatars,
                                             transaction: SDSAnyWriteTransaction) throws -> TSGroupThread {

        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            throw OWSAssertionError("Missing groupThread.")
        }
        guard groupThread.groupModel.groupsVersion == .V2 else {
            throw OWSAssertionError("Invalid groupsVersion.")
        }
        let changedGroupModel = try GroupsV2Changes.applyChangesToGroupModel(groupThread: groupThread,
                                                                             changeActionsProto: changeActionsProto,
                                                                             downloadedAvatars: downloadedAvatars,
                                                                             transaction: transaction)
        guard changedGroupModel.newGroupModel.revision > changedGroupModel.oldGroupModel.revision else {
            throw OWSAssertionError("Invalid groupV2Revision: \(changedGroupModel.newGroupModel.revision).")
        }

        let groupUpdateSourceAddress = SignalServiceAddress(uuid: changedGroupModel.changeAuthorUuid)
        let newGroupModel = changedGroupModel.newGroupModel
        let newDisappearingMessageToken = changedGroupModel.newDisappearingMessageToken
        let updatedGroupThread = try GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                                          newDisappearingMessageToken: newDisappearingMessageToken,
                                                                                                          groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                          transaction: transaction).groupThread

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

    private func fetchAndApplyChangeActionsFromService(groupSecretParamsData: Data,
                                                       groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {
        return firstly { () -> Promise<[GroupV2Change]> in
            self.fetchChangeActionsFromService(groupSecretParamsData: groupSecretParamsData,
                                               groupUpdateMode: groupUpdateMode)
        }.then(on: DispatchQueue.global()) { (groupChanges: [GroupV2Change]) throws -> Promise<TSGroupThread> in
            let groupId = try self.groupsV2.groupId(forGroupSecretParamsData: groupSecretParamsData)
            return self.tryToApplyGroupChangesFromService(groupId: groupId,
                                                          groupSecretParamsData: groupSecretParamsData,
                                                          groupChanges: groupChanges,
                                                          groupUpdateMode: groupUpdateMode)
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: "Update via changes") {
                    GroupsV2Error.timeout
        }
    }

    private let changeCache = NSCache<NSString, ChangeCacheItem>()

    private class ChangeCacheItem: NSObject {
        let groupChanges: [GroupV2Change]

        init(groupChanges: [GroupV2Change]) {
            self.groupChanges = groupChanges
        }
    }

    private func addGroupChangesToCache(groupChanges: [GroupV2Change],
                                        cacheKey: NSString) {
        guard !groupChanges.isEmpty else {
            if FeatureFlags.groupsV2reapplyCurrentRevision {
                owsFailDebug("Invalid group changes.")
            }
            changeCache.removeObject(forKey: cacheKey)
            return
        }

        let revisions = groupChanges.map { $0.revision }
        Logger.verbose("Caching revisions: \(revisions)")
        changeCache.setObject(ChangeCacheItem(groupChanges: groupChanges),
                              forKey: cacheKey)
    }

    private func cachedGroupChanges(forCacheKey cacheKey: NSString,
                                    groupSecretParamsData: Data,
                                    upToRevision: UInt32?) -> [GroupV2Change]? {
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
            changeCache.removeObject(forKey: cacheKey)
            return nil
        }
        guard let cacheItem = changeCache.object(forKey: cacheKey) else {
            return nil
        }
        let cachedChanges = cacheItem.groupChanges.filter { groupChange in
            let revision = groupChange.revision
            guard revision <= upToRevision else {
                return false
            }
            if FeatureFlags.groupsV2reapplyCurrentRevision {
                return revision >= dbRevision
            } else {
                return revision > dbRevision
            }
        }
        let revisions = cachedChanges.map { $0.revision }
        guard Set(revisions).contains(upToRevision) else {
            changeCache.removeObject(forKey: cacheKey)
            return nil
        }
        Logger.verbose("Using cached revisions: \(revisions), dbRevision: \(dbRevision), upToRevision: \(upToRevision)")
        return cachedChanges
    }

    private func fetchChangeActionsFromService(groupSecretParamsData: Data,
                                               groupUpdateMode: GroupUpdateMode) -> Promise<[GroupV2Change]> {

        let upToRevision: UInt32? = {
            switch groupUpdateMode {
            case .upToSpecificRevisionImmediately(let upToRevision):
                return upToRevision
            default:
                return nil
            }
        }()

        let cacheKey = groupSecretParamsData.hexadecimalString as NSString

        return DispatchQueue.global().async(.promise) { () -> [GroupV2Change]? in
            guard let groupChanges = self.cachedGroupChanges(forCacheKey: cacheKey,
                                                             groupSecretParamsData: groupSecretParamsData,
                                                             upToRevision: upToRevision) else {
                                                                return nil
            }
            return groupChanges
        }.then(on: DispatchQueue.global()) { (groupChanges: [GroupV2Change]?) -> Promise<[GroupV2Change]> in
            if let groupChanges = groupChanges {
                return Promise.value(groupChanges)
            }
            return firstly {
                return self.groupsV2.fetchGroupChangeActions(groupSecretParamsData: groupSecretParamsData,
                                                             firstKnownRevision: upToRevision)
            }.map(on: DispatchQueue.global()) { (groupChanges: [GroupV2Change]) -> [GroupV2Change] in
                self.addGroupChangesToCache(groupChanges: groupChanges, cacheKey: cacheKey)

                return groupChanges
            }
        }
    }

    private func tryToApplyGroupChangesFromService(groupId: Data,
                                                   groupSecretParamsData: Data,
                                                   groupChanges: [GroupV2Change],
                                                   groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {
        return firstly { () -> Promise<Void> in
            if groupUpdateMode.shouldBlockOnMessageProcessing {
                return self.messageProcessing.allMessageFetchingAndProcessingPromise()
            } else {
                return Promise.value(())
            }
        }.then(on: .global()) {
            return self.tryToApplyGroupChangesFromServiceNow(groupId: groupId,
                                                             groupSecretParamsData: groupSecretParamsData,
                                                             groupChanges: groupChanges,
                                                             upToRevision: groupUpdateMode.upToRevision)
        }
    }

    private func tryToApplyGroupChangesFromServiceNow(groupId: Data,
                                                      groupSecretParamsData: Data,
                                                      groupChanges: [GroupV2Change],
                                                      upToRevision: UInt32?) -> Promise<TSGroupThread> {

        let localProfileKey = profileManager.localProfileKey()
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }

        return databaseStorage.write(.promise) { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
            // See comment on getOrCreateThreadForGroupChanges(...).
            guard let oldGroupThread = self.getOrCreateThreadForGroupChanges(groupId: groupId,
                                                                             groupSecretParamsData: groupSecretParamsData,
                                                                             groupChanges: groupChanges,
                                                                             transaction: transaction) else {
                throw OWSAssertionError("Missing group thread.")
            }
            guard let oldGroupModel = oldGroupThread.groupModel as? TSGroupModelV2 else {
                throw OWSAssertionError("Invalid group model.")
            }
            let groupV2Params = try oldGroupModel.groupV2Params()

            var groupThread = oldGroupThread

            if groupChanges.count < 1 {
                if FeatureFlags.groupsV2reapplyCurrentRevision {
                    owsFailDebug("No group changes.")
                }
                return groupThread
            }

            var shouldUpdateProfileKeyInGroup = false
            var profileKeysByUuid = [UUID: Data]()
            for groupChange in groupChanges {
                let changeRevision = groupChange.revision
                if let upToRevision = upToRevision {
                    guard upToRevision >= changeRevision else {
                        Logger.info("Ignoring group change: \(changeRevision); only updating to revision: \(upToRevision)")

                        // Enqueue an update to latest.
                        self.tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithThrottling(groupThread)

                        break
                    }
                }

                let diff = groupChange.diff
                let changeActionsProto = diff.changeActionsProto
                // Many change actions have author info, e.g. addedByUserID. But we can
                // safely assume that all actions in the "change actions" have the same author.
                guard let changeAuthorUuidData = changeActionsProto.sourceUuid else {
                    throw OWSAssertionError("Missing changeAuthorUuid.")
                }

                guard let oldGroupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid group model.")
                }

                let isSingleRevisionUpdate = oldGroupModel.revision + 1 == changeRevision
                var groupUpdateSourceAddress: SignalServiceAddress?
                if isSingleRevisionUpdate {
                    // The "group update" info message should only reflect
                    // the "change author" if the change/diff reflects a
                    // single revision.  Eventually there will be gaps in
                    // the returned changes.
                    //
                    // Some userIds/uuidCiphertexts can be validated by
                    // the service. This is one.
                    let changeAuthorUuid = try groupV2Params.uuid(forUserId: changeAuthorUuidData)
                    groupUpdateSourceAddress = SignalServiceAddress(uuid: changeAuthorUuid)
                }

                let newGroupModel: TSGroupModel
                let newDisappearingMessageToken: DisappearingMessageToken?
                let newProfileKeys: [UUID: Data]
                if let snapshot = groupChange.snapshot {
                    let builder = try TSGroupModelBuilder(groupV2Snapshot: snapshot)
                    newGroupModel = try builder.build(transaction: transaction)
                    newDisappearingMessageToken = snapshot.disappearingMessageToken
                    newProfileKeys = snapshot.profileKeys
                } else {
                    let changedGroupModel = try GroupsV2Changes.applyChangesToGroupModel(groupThread: groupThread,
                                                                                         changeActionsProto: changeActionsProto,
                                                                                         downloadedAvatars: diff.downloadedAvatars,
                                                                                         transaction: transaction)
                    newGroupModel = changedGroupModel.newGroupModel
                    newDisappearingMessageToken = changedGroupModel.newDisappearingMessageToken
                    newProfileKeys = changedGroupModel.profileKeys
                }

                if changeRevision == oldGroupModel.revision {
                    if !oldGroupModel.isEqual(to: newGroupModel, ignoreRevision: false) {
                        // Sometimes we re-apply the snapshot corresponding to the
                        // current revision when refreshing the group from the service.
                        // This should match the state in the database.  If it doesn't,
                        // this reflects a bug, perhaps a deviation in how the service
                        // and client apply the "group changes" to the local model.
                        Logger.verbose("oldGroupModel: \(oldGroupModel.debugDescription)")
                        Logger.verbose("newGroupModel: \(newGroupModel.debugDescription)")
                        owsFailDebug("Group models don't match.")
                    }
                }

                groupThread = try GroupManager.updateExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                                       newDisappearingMessageToken: newDisappearingMessageToken,
                                                                                                       groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                       transaction: transaction).groupThread

                // If the group state includes a stale profile key for the
                // local user, schedule an update to fix that.
                if let profileKey = newProfileKeys[localUuid],
                    profileKey != localProfileKey.keyData {
                    shouldUpdateProfileKeyInGroup = true
                }

                // Merge known profile keys, always taking latest.
                profileKeysByUuid = profileKeysByUuid.merging(newProfileKeys) { (_, latest) in latest }
            }

            if shouldUpdateProfileKeyInGroup {
                self.groupsV2.updateLocalProfileKeyInGroup(groupId: groupId, transaction: transaction)
            }

            GroupManager.storeProfileKeysFromGroupProtos(profileKeysByUuid)

            return groupThread
        }
    }

    // When learning about v2 groups for the first time, we can always
    // insert them into the database using a snapshot.  However we prefer
    // to create them from group changes if possible, because group
    // changes have more information.  Critically, we can usually determine
    // who create the group or who added or invited us to the group.
    //
    // Therefore, before starting to apply group changes we use this
    // method to insert the group into the database if necessary.
    private func getOrCreateThreadForGroupChanges(groupId: Data,
                                                  groupSecretParamsData: Data,
                                                  groupChanges: [GroupV2Change],
                                                  transaction: SDSAnyWriteTransaction) -> TSGroupThread? {
        if let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            return groupThread
        }

        do {
            let groupV2Params = try GroupV2Params(groupSecretParamsData: groupSecretParamsData)

            guard let groupChange = groupChanges.first else {
                return nil
            }
            guard let snapshot = groupChange.snapshot else {
                throw OWSAssertionError("Missing snapshot.")
            }
            let builder = try TSGroupModelBuilder(groupV2Snapshot: snapshot)
            let newGroupModel = try builder.build(transaction: transaction)

            // Many change actions have author info, e.g. addedByUserID. But we can
            // safely assume that all actions in the "change actions" have the same author.
            guard let changeAuthorUuidData = groupChange.diff.changeActionsProto.sourceUuid else {
                throw OWSAssertionError("Missing changeAuthorUuid.")
            }
            // Some userIds/uuidCiphertexts can be validated by
            // the service. This is one.
            let changeAuthorUuid = try groupV2Params.uuid(forUserId: changeAuthorUuidData)
            let groupUpdateSourceAddress = SignalServiceAddress(uuid: changeAuthorUuid)
            let newDisappearingMessageToken = snapshot.disappearingMessageToken

            let result = try GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                                       newDisappearingMessageToken: newDisappearingMessageToken,
                                                                                                       groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                       canInsert: true,
                                                                                                       transaction: transaction)

            // NOTE: We don't need to worry about profile keys here.  This method is
            // only used by tryToApplyGroupChangesFromServiceNow() which will take
            // care of that.

            return result.groupThread
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    // MARK: - Current Snapshot

    private func fetchAndApplyCurrentGroupV2SnapshotFromService(groupSecretParamsData: Data,
                                                                groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {
        return firstly {
            self.groupsV2.fetchCurrentGroupV2Snapshot(groupSecretParamsData: groupSecretParamsData)
        }.then(on: .global()) { groupV2Snapshot in
            return self.tryToApplyCurrentGroupV2SnapshotFromService(groupV2Snapshot: groupV2Snapshot,
                                                                    groupUpdateMode: groupUpdateMode)
        }.timeout(seconds: GroupManager.groupUpdateTimeoutDuration,
                  description: "Update via snapshot") {
            GroupsV2Error.timeout
        }
    }

    private func tryToApplyCurrentGroupV2SnapshotFromService(groupV2Snapshot: GroupV2Snapshot,
                                                             groupUpdateMode: GroupUpdateMode) -> Promise<TSGroupThread> {
        return firstly { () -> Promise<Void> in
            if groupUpdateMode.shouldBlockOnMessageProcessing {
                return self.messageProcessing.allMessageFetchingAndProcessingPromise()
            } else {
                return Promise.value(())
            }
        }.then(on: .global()) { _ in
            return self.tryToApplyCurrentGroupV2SnapshotFromServiceNow(groupV2Snapshot: groupV2Snapshot)
        }
    }

    private func tryToApplyCurrentGroupV2SnapshotFromServiceNow(groupV2Snapshot: GroupV2Snapshot) -> Promise<TSGroupThread> {
        let localProfileKey = profileManager.localProfileKey()
        guard let localUuid = tsAccountManager.localUuid else {
            return Promise(error: OWSAssertionError("Missing localUuid."))
        }

        return databaseStorage.write(.promise) { (transaction: SDSAnyWriteTransaction) throws -> TSGroupThread in
            let builder = try TSGroupModelBuilder(groupV2Snapshot: groupV2Snapshot)
            let newGroupModel = try builder.build(transaction: transaction)
            let newDisappearingMessageToken = groupV2Snapshot.disappearingMessageToken
            // groupUpdateSourceAddress is nil because we don't know the
            // author(s) of changes reflected in the snapshot.
            let groupUpdateSourceAddress: SignalServiceAddress? = nil
            let result = try GroupManager.tryToUpsertExistingGroupThreadInDatabaseAndCreateInfoMessage(newGroupModel: newGroupModel,
                                                                                                       newDisappearingMessageToken: newDisappearingMessageToken,
                                                                                                       groupUpdateSourceAddress: groupUpdateSourceAddress,
                                                                                                       canInsert: true,
                                                                                                       transaction: transaction)

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
}
