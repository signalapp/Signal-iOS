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
    func didBecomeActive() {
        AssertIsOnMainThread()

        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.tryToUpdateNext()
        }
    }

    @objc
    func reachabilityChanged() {
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

    @objc
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
        guard !CurrentAppContext().isRunningTests,
              tsAccountManager.isRegisteredAndReady,
              tsAccountManager.isPrimaryDevice else {
            return
        }
        guard let localAddress = tsAccountManager.localAddress else {
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

    @objc
    public func processProfileKeyUpdates() {
        tryToUpdateNext()
    }

    private let serialQueue = DispatchQueue(label: "GroupsV2ProfileKeyUpdater", qos: .background)

    // This property should only be accessed on serialQueue.
    private var isUpdating = false

    private func tryToUpdateNext(retryDelay: TimeInterval = 1) {
        guard CurrentAppContext().isMainAppAndActive,
              !CurrentAppContext().isRunningTests,
              tsAccountManager.isRegisteredAndReady,
              tsAccountManager.isPrimaryDevice else {
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

            firstly(on: .global()) { () -> Promise<Void> in
                self.tryToUpdate(groupId: groupId)
            }.done(on: .global() ) { _ in
                Logger.verbose("Updated profile key in group.")

                self.didSucceed(groupId: groupId)
            }.catch(on: .global() ) { error in
                Logger.warn("Failed: \(error).")

                guard !error.isNetworkConnectivityFailure else {
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
                    if let statusCode = error.httpStatusCode,
                       400 <= statusCode && statusCode <= 599 {
                        // If a non-recoverable error occurs (e.g. we've been kicked
                        // out of the group), give up.
                        Logger.info("Failed: \(statusCode)")
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
        guard let localAddress = tsAccountManager.localAddress,
              let localUuid = tsAccountManager.localUuid else {
            owsFailDebug("missing local address")
            return Promise(error: GroupsV2Error.shouldDiscard)
        }

        return firstly {
            self.messageProcessor.fetchingAndProcessingCompletePromise()
        }.map(on: .global()) { () throws -> TSGroupThread in
            try self.databaseStorage.read { transaction throws in
                guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
                    throw GroupsV2Error.shouldDiscard
                }
                return groupThread
            }
        }.then(on: .global()) { (groupThread: TSGroupThread) throws -> Promise<(TSGroupThread, UInt32)> in
            // Get latest group state from service and verify that this update is still necessary.
            firstly { () throws -> Promise<GroupV2Snapshot> in
                guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                    throw OWSAssertionError("Invalid group model.")
                }
                return self.groupsV2Impl.fetchCurrentGroupV2Snapshot(groupModel: groupModel)
            }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> (TSGroupThread, UInt32) in
                guard groupV2Snapshot.groupMembership.isFullMember(localAddress) else {
                    // We're not a full member, no need to update profile key.
                    throw GroupsV2Error.redundantChange
                }
                guard !groupV2Snapshot.profileKeys.values.contains(profileKeyData) else {
                    // Group state already has our current key.
                    throw GroupsV2Error.redundantChange
                }
                if DebugFlags.internalLogging {
                    for (uuid, profileKey) in groupV2Snapshot.profileKeys {
                        Logger.info("Existing profile key: \(profileKey.hexadecimalString), for uuid: \(uuid), is local: \(uuid == localUuid)")
                    }
                }
                let checkedRevision = groupV2Snapshot.revision
                return (groupThread, checkedRevision)
            }
        }.then(on: .global()) { (groupThread: TSGroupThread, checkedRevision: UInt32) throws -> Promise<Void> in
            if DebugFlags.internalLogging {
                Logger.info("Updating profile key for group: \(groupThread.groupId.hexadecimalString), profileKey: \(profileKeyData.hexadecimalString), localUuid: \(localUuid), checkedRevision: \(checkedRevision)")
            } else {
                Logger.info("Updating profile key for group.")
            }

            guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                owsFailDebug("Invalid group model.")
                throw GroupsV2Error.shouldDiscard
            }

            return firstly {
                GroupManager.ensureLocalProfileHasCommitmentIfNecessary()
            }.then(on: .global()) { () throws -> Promise<Void> in
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
                return Self.groupV2Updates.tryToRefreshV2GroupUpToCurrentRevisionImmediately(groupId: groupId,
                                                                                             groupSecretParamsData: groupSecretParamsData).asVoid()
            }.then(on: .global()) { () throws -> Promise<TSGroupThread> in
                return GroupManager.updateLocalProfileKey(
                    groupModel: groupModel
                )
            }.then(on: .global()) { (groupThread: TSGroupThread) -> Promise<TSGroupThread> in
                // Confirm that the updated snapshot has the new profile key.
                firstly(on: .global()) { () -> Promise<GroupV2Snapshot> in
                    guard let groupModel = groupThread.groupModel as? TSGroupModelV2 else {
                        throw OWSAssertionError("Invalid group model.")
                    }
                    return self.groupsV2Impl.fetchCurrentGroupV2Snapshot(groupModel: groupModel)
                }.map(on: .global()) { (groupV2Snapshot: GroupV2Snapshot) throws -> Void in
                    if DebugFlags.internalLogging {
                        Logger.info("updated revision: \(groupV2Snapshot.revision)")
                        for (uuid, profileKey) in groupV2Snapshot.profileKeys {
                            Logger.info("Existing profile key: \(profileKey.hexadecimalString), for uuid: \(uuid), is local: \(uuid == localUuid)")
                        }
                    }
                    guard groupV2Snapshot.groupMembership.isFullMember(localAddress) else {
                        owsFailDebug("Not a full member.")
                        return
                    }
                    guard groupV2Snapshot.profileKeys.values.contains(profileKeyData) else {
                        owsFailDebug("Update failed.")
                        self.databaseStorage.write { transaction in
                            self.versionedProfiles.clearProfileKeyCredential(for: localAddress,
                                                                             transaction: transaction)
                        }
                        return
                    }
                }.map(on: .global()) { () -> TSGroupThread in
                    groupThread
                }
            }.asVoid()
        }
    }
}
