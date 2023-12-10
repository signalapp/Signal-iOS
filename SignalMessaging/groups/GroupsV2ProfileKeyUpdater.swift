//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

// Whenever we rotate our profile key, we need to update all
// v2 groups of which we are a non-pending member.

// This is laborious, but important. It is too expensive to
// do unless necessary (e.g. we don't want to check every
// group on launch), but important enough to do durably.
//
// This class has responsibility for tracking which groups
// need to be updated and for updating them.
class GroupsV2ProfileKeyUpdater: Dependencies {

    public required init() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reachabilityChanged),
                                               name: SSKReachability.owsReachabilityDidChange,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    // MARK: -

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.tryToUpdateNext()
        }
    }

    @objc
    private func reachabilityChanged() {
        AssertIsOnMainThread()

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.tryToUpdateNext()
        }
    }

    // MARK: -

    // Stores the list of v2 groups that we need to update with our latest profile key.
    private let keyValueStore = SDSKeyValueStore(collection: "GroupsV2ProfileKeyUpdater")

    private func key(for groupId: Data) -> String {
        return groupId.hexadecimalString
    }

    public func updateLocalProfileKeyInGroup(groupId: Data, transaction: SDSAnyWriteTransaction) {
        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            owsFailDebug("Missing groupThread.")
            return
        }
        self.tryToScheduleGroupForProfileKeyUpdate(groupThread: groupThread,
                                                   transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            self.tryToUpdateNext()
        }
    }

    public func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: SDSAnyWriteTransaction) {
        TSGroupThread.anyEnumerate(transaction: transaction) { (thread, _) in
            guard let groupThread = thread as? TSGroupThread,
                  groupThread.isGroupV2Thread else {
                return
            }
            self.tryToScheduleGroupForProfileKeyUpdate(groupThread: groupThread,
                                                       transaction: transaction)
        }

        // Note that we don't kick off updates yet (don't schedule tryToUpdateNext for the end of the transaction)
        // because we want to make sure that any profile key update is committed to the server first.
        // This isn't a guarantee because there could *already* be a series of updates going,
        // but it helps in the common case.
    }

    private func tryToScheduleGroupForProfileKeyUpdate(groupThread: TSGroupThread,
                                                       transaction: SDSAnyWriteTransaction) {
        guard
            !CurrentAppContext().isRunningTests,
            DependenciesBridge.shared.tsAccountManager.registrationState(tx: transaction.asV2Read).isRegisteredPrimaryDevice
        else {
            return
        }
        guard let localAddress = DependenciesBridge.shared.tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aciAddress else {
            owsFailDebug("missing local address")
            return
        }

        let groupMembership = groupThread.groupModel.groupMembership
        // We only need to update v2 groups of which we are a full member.
        guard groupThread.isGroupV2Thread,
              groupMembership.isFullMember(localAddress) else {
            return
        }
        let groupId = groupThread.groupModel.groupId
        let key = self.key(for: groupId)
        self.keyValueStore.setData(groupId, key: key, transaction: transaction)
    }

    public func processProfileKeyUpdates() {
        tryToUpdateNext()
    }

    private let serialQueue = DispatchQueue(label: "org.signal.groups.profile-key-updater", qos: .utility)

    // This property should only be accessed on serialQueue.
    private var isUpdating = false

    private func tryToUpdateNext(retryDelay: TimeInterval = 1) {
        guard
            CurrentAppContext().isMainAppAndActive,
            !CurrentAppContext().isRunningTests,
            DependenciesBridge.shared.tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice
        else {
            return
        }
        guard reachabilityManager.isReachable else {
            return
        }

        serialQueue.async {
            guard !self.isUpdating else {
                // Only one update should be in flight at a time.
                return
            }
            guard let groupId = (self.databaseStorage.read { transaction in
                return self.keyValueStore.anyDataValue(transaction: transaction)
            }) else {
                return
            }

            self.isUpdating = true

            firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
                self.tryToUpdate(groupId: groupId)
            }.done(on: DispatchQueue.global() ) { _ in
                self.didSucceed(groupId: groupId)
            }.catch(on: DispatchQueue.global() ) { error in
                Logger.warn("Failed: \(error).")

                guard !error.isNetworkFailureOrTimeout else {
                    // Retry later.
                    return self.didFail(groupId: groupId, retryDelay: retryDelay)
                }

                switch error {
                case GroupsV2Error.shouldDiscard:
                    // If a non-recoverable error occurs (e.g. we've
                    // delete the thread from the database), give up.
                    self.markAsComplete(groupId: groupId)
                case GroupsV2Error.redundantChange:
                    // If the update is no longer necessary, skip it.
                    self.markAsComplete(groupId: groupId)
                case GroupsV2Error.localUserNotInGroup:
                    // If the update is no longer necessary, skip it.
                    self.markAsComplete(groupId: groupId)
                case is OWSHTTPError:
                    if let statusCode = error.httpStatusCode, 400 <= statusCode && statusCode <= 599 {
                        // If a non-recoverable error occurs (e.g. we've been kicked
                        // out of the group), give up.
                        Logger.warn("Failed: \(statusCode)")
                        self.markAsComplete(groupId: groupId)
                    } else {
                        // Retry later.
                        self.didFail(groupId: groupId, retryDelay: retryDelay)
                    }
                default:
                    // This should never occur. If it does, we don't want
                    // to get stuck in a retry loop.
                    owsFailDebug("Unexpected error: \(error)")
                    self.markAsComplete(groupId: groupId)
                }
            }
        }
    }

    private func didSucceed(groupId: Data) {
        markAsComplete(groupId: groupId)
    }

    private func markAsComplete(groupId: Data) {
        serialQueue.async {
            self.databaseStorage.write { transaction in
                let key = self.key(for: groupId)
                self.keyValueStore.removeValue(forKey: key, transaction: transaction)
            }

            self.isUpdating = false

            self.tryToUpdateNext()
        }
    }

    private func didFail(groupId: Data, retryDelay: TimeInterval) {
        serialQueue.asyncAfter(deadline: DispatchTime.now() + retryDelay) {
            self.isUpdating = false

            // Retry with exponential backoff.
            self.tryToUpdateNext(retryDelay: retryDelay * 2)
        }
    }

    private func tryToUpdate(groupId: Data) -> Promise<Void> {
        let profileKeyData = profileManager.localProfileKey().keyData
        guard let localAci = DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            owsFailDebug("missing local address")
            return Promise(error: GroupsV2Error.shouldDiscard)
        }

        return firstly {
            if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] fetchingAndProcessingCompletePromise") }
            return self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.map(on: DispatchQueue.global()) { () throws -> TSGroupThread in
            if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] getting group thread") }
            return try self.databaseStorage.read { transaction throws in
                guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                    throw GroupsV2Error.shouldDiscard
                }
                return groupThread
            }
        }.then(on: DispatchQueue.global()) { (groupThread: TSGroupThread) throws -> Promise<(TSGroupThread, UInt32)> in
            // Get latest group state from service and verify that this update is still necessary.
            if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] about to return promise for getting snapshot") }
            return firstly { () throws -> Promise<GroupV2Snapshot> in
                guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid group model.")
                }
                if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] fetch snapshot") }
                return self.groupsV2Impl.fetchCurrentGroupV2Snapshot(groupModel: groupModel)
            }.map(on: DispatchQueue.global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> (TSGroupThread, UInt32) in
                guard groupV2Snapshot.groupMembership.isFullMember(localAci) else {
                    // We're not a full member, no need to update profile key.
                    if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] redundant change A") }
                    throw GroupsV2Error.redundantChange
                }
                guard groupV2Snapshot.profileKeys[localAci] != profileKeyData else {
                    // Group state already has our current key.
                    if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] redundant change B") }
                    throw GroupsV2Error.redundantChange
                }
                let checkedRevision = groupV2Snapshot.revision
                return (groupThread, checkedRevision)
            }
        }.then(on: DispatchQueue.global()) { (groupThread: TSGroupThread, checkedRevision: UInt32) throws -> Promise<Void> in
            if DebugFlags.internalLogging {
                Logger.info("Updating profile key for group: \(groupThread.groupId.hexadecimalString), profileKey: \(profileKeyData.hexadecimalString), localAci: \(localAci), checkedRevision: \(checkedRevision)")
            } else {
                Logger.info("Updating profile key for group.")
            }

            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                owsFailDebug("Invalid group model.")
                throw GroupsV2Error.shouldDiscard
            }

            return firstly {
                if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] ensure local profile has commitment if necessary") }
                return GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
            }.then(on: DispatchQueue.global()) { () throws -> Promise<Void> in
                // Before we can update the group state on the service,
                // we need to ensure that the group state in the local
                // database reflects the latest group state on the service.
                let dbRevision = groupModel.revision
                guard dbRevision != checkedRevision else {
                    // Revisions match, so we can proceed immediately with
                    // the profile update.
                    return Promise.value(())
                }
                // If the revisions don't match, we want to update the group
                // state in the local database before proceeding.  It's not
                // safe to do so until we've finished message processing,
                // but we've already blocked on fetchingAndProcessingCompletePromise
                // above.
                let groupId = groupModel.groupId
                let groupSecretParamsData = groupModel.secretParamsData
                if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] try to refresh v2 group up to curr revision immed") }
                return Self.groupV2Updates.tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: groupId,
                                                                                             groupSecretParamsData: groupSecretParamsData).asVoid()
            }.then(on: DispatchQueue.global()) { () throws -> Promise<TSGroupThread> in
                if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] update profile key") }
                return GroupManager.updateLocalProfileKey(
                    groupModel: groupModel
                )
            }.then(on: DispatchQueue.global()) { (groupThread: TSGroupThread) -> Promise<TSGroupThread> in
                if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] check update really worked") }
                // Confirm that the updated snapshot has the new profile key.
                return firstly(on: DispatchQueue.global()) { () -> Promise<GroupV2Snapshot> in
                    guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                        throw OWSAssertionError("Invalid group model.")
                    }
                    if DebugFlags.internalLogging { Logger.info("[Scroll Perf Debug] fetch snapshot again") }
                    return self.groupsV2Impl.fetchCurrentGroupV2Snapshot(groupModel: groupModel)
                }.map(on: DispatchQueue.global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> Void in
                    guard groupV2Snapshot.groupMembership.isFullMember(localAci) else {
                        owsFailDebug("Not a full member.")
                        return
                    }
                    guard groupV2Snapshot.profileKeys[localAci] == profileKeyData else {
                        owsFailDebug("Update failed.")
                        self.databaseStorage.write { tx in
                            self.versionedProfiles.clearProfileKeyCredential(for: AciObjC(localAci), transaction: tx)
                        }
                        return
                    }
                }.map(on: DispatchQueue.global()) { () -> TSGroupThread in
                    groupThread
                }
            }.asVoid()
        }
    }
}
