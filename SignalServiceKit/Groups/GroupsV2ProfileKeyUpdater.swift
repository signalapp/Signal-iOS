//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// Whenever we rotate our profile key, we need to update all
// v2 groups of which we are a non-pending member.

// This is laborious, but important. It is too expensive to
// do unless necessary (e.g. we don't want to check every
// group on launch), but important enough to do durably.
//
// This class has responsibility for tracking which groups
// need to be updated and for updating them.
class GroupsV2ProfileKeyUpdater {

    private let appReadiness: AppReadiness

    public init(appReadiness: AppReadiness) {
        self.appReadiness = appReadiness
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reachabilityChanged),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
    }

    // MARK: -

    @objc
    private func didBecomeActive() {
        AssertIsOnMainThread()

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.setNeedsUpdate()
        }
    }

    @objc
    private func reachabilityChanged() {
        AssertIsOnMainThread()

        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            self.setNeedsUpdate()
        }
    }

    // MARK: -

    // Stores the list of v2 groups that we need to update with our latest profile key.
    private let keyValueStore = KeyValueStore(collection: "GroupsV2ProfileKeyUpdater")

    private func key(for groupId: Data) -> String {
        return groupId.hexadecimalString
    }

    public func updateLocalProfileKeyInGroup(groupId: Data, transaction: SDSAnyWriteTransaction) {
        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            owsFailDebug("Missing groupThread.")
            return
        }
        self.tryToScheduleGroupForProfileKeyUpdate(groupThread: groupThread, transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            self.setNeedsUpdate()
        }
    }

    public func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: SDSAnyWriteTransaction) {
        TSGroupThread.anyEnumerate(transaction: transaction) { (thread, _) in
            guard let groupThread = thread as? TSGroupThread else {
                return
            }
            self.tryToScheduleGroupForProfileKeyUpdate(groupThread: groupThread, transaction: transaction)
        }

        // Note that we don't kick off updates yet (don't schedule tryToUpdateNext
        // for the end of the transaction) because we want to make sure that any
        // profile key update is committed to the server first. This isn't a
        // guarantee because there could *already* be a series of updates going,
        // but it helps in the common case.
    }

    private func tryToScheduleGroupForProfileKeyUpdate(groupThread: TSGroupThread, transaction: SDSAnyWriteTransaction) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationState(tx: transaction.asV2Read).isRegisteredPrimaryDevice else {
            return
        }
        guard let localAddress = tsAccountManager.localIdentifiers(tx: transaction.asV2Read)?.aciAddress else {
            owsFailDebug("missing local address")
            return
        }

        let groupMembership = groupThread.groupModel.groupMembership
        // We only need to update v2 groups of which we are a full member.
        guard groupThread.isGroupV2Thread, groupMembership.isFullMember(localAddress) else {
            return
        }
        let groupId = groupThread.groupModel.groupId
        let key = self.key(for: groupId)
        self.keyValueStore.setData(groupId, key: key, transaction: transaction.asV2Write)
    }

    public func processProfileKeyUpdates() {
        setNeedsUpdate()
    }

    private struct State {
        var isUpdating = false
        var needsUpdate = false
    }
    private let state = AtomicValue<State>(State(), lock: .init())

    private func setNeedsUpdate() {
        self.state.update { $0.needsUpdate = true }
        startUpdatingIfNeeded()
    }

    private func startUpdatingIfNeeded() {
        Task { await self._startUpdatingIfNeeded() }
    }

    private func _startUpdatingIfNeeded() async {
        let shouldStart = self.state.update {
            if $0.isUpdating || !$0.needsUpdate {
                return false
            }
            $0.isUpdating = true
            $0.needsUpdate = false
            return true
        }
        guard shouldStart else {
            // Only one update should be in flight at a time.
            return
        }
        defer {
            self.state.update { $0.isUpdating = false }
            // An external trigger might have called setNeedsUpdate while we were
            // running, after we checked for runnable jobs, but before we cleared
            // isUpdating. Check again since there might now be runnable jobs.
            startUpdatingIfNeeded()
        }
        var failureCount = 0
        while true {
            // If an external trigger called setNeedsUpdate, we'll observe anything it
            // wants us to observe during this iteration because we haven't checked
            // anything yet. (If we'd already checked, eg, isReachable, then we'd risk
            // missing the latest reachability update.)
            self.state.update { $0.needsUpdate = false }

            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            guard
                await CurrentAppContext().isMainAppAndActiveIsolated,
                !CurrentAppContext().isRunningTests,
                tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegisteredPrimaryDevice,
                SSKEnvironment.shared.reachabilityManagerRef.isReachable
            else {
                return
            }

            do {
                let databaseStorage = SSKEnvironment.shared.databaseStorageRef
                let groupIdKeys = databaseStorage.read(block: { self.keyValueStore.allKeys(transaction: $0.asV2Read) })
                let taskQueue = ConcurrentTaskQueue(concurrentLimit: 16)
                try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                    for groupIdKey in groupIdKeys {
                        _ = taskGroup.addTaskUnlessCancelled {
                            try await taskQueue.run {
                                try Task.checkCancellation()
                                try await self._tryToUpdateNext(groupIdKey: groupIdKey)
                            }
                        }
                    }
                    try await taskGroup.waitForAll()
                }
                return
            } catch {
                failureCount += 1
                try? await Task.sleep(nanoseconds: OWSOperation.retryIntervalForExponentialBackoffNs(failureCount: failureCount, maxBackoff: 6*kHourInterval))
            }
        }
    }

    private func _tryToUpdateNext(groupIdKey: String) async throws {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        guard let groupId = databaseStorage.read(block: { tx in keyValueStore.getData(groupIdKey, transaction: tx.asV2Read) }) else {
            return
        }
        do {
            try await self.tryToUpdate(groupId: groupId)
        } catch {
            Logger.warn("\(error)")
            switch error {
            case GroupsV2Error.shouldDiscard:
                // If a non-recoverable error occurs (e.g. we've deleted the thread from the
                // database), give up.
                break
            case GroupsV2Error.redundantChange:
                // If the update is no longer necessary, skip it.
                break
            case GroupsV2Error.localUserNotInGroup:
                // If the update is no longer necessary, skip it.
                break
            case let httpError as OWSHTTPError where (400...499).contains(httpError.responseStatusCode):
                // If a non-recoverable error occurs (e.g. we've been kicked out of the
                // group), give up.
                break
            case is OWSHTTPError:
                throw error
            case _ where error.isNetworkFailureOrTimeout:
                throw error
            case GroupsV2Error.timeout:
                throw error
            default:
                // This should never occur. If it does, we don't want to get stuck in a
                // retry loop.
                owsFailDebug("Unexpected error: \(error)")
            }
        }
        await markAsComplete(groupIdKey: groupIdKey)
    }

    private func markAsComplete(groupIdKey: String) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            self.keyValueStore.removeValue(forKey: groupIdKey, transaction: transaction.asV2Write)
        }
    }

    private func tryToUpdate(groupId: Data) async throws {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localAci = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            owsFailDebug("missing local address")
            throw GroupsV2Error.shouldDiscard
        }

        await SSKEnvironment.shared.messageProcessorRef.waitForFetchingAndProcessing().awaitable()

        let groupModel = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return TSGroupThread.fetch(groupId: groupId, transaction: tx)?.groupModel as? TSGroupModelV2
        }
        guard let groupModel else {
            throw GroupsV2Error.shouldDiscard
        }

        // Get latest group state from service and verify that this update is still necessary.
        try Task.checkCancellation()
        let snapshotResponse = try await SSKEnvironment.shared.groupsV2Ref.fetchLatestSnapshot(groupModel: groupModel)
        guard snapshotResponse.groupSnapshot.groupMembership.isFullMember(localAci) else {
            // We're not a full member, no need to update profile key.
            throw GroupsV2Error.redundantChange
        }
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let profileKeyData = profileManager.localProfileKey.keyData
        guard snapshotResponse.groupSnapshot.profileKeys[localAci] != profileKeyData else {
            // Group state already has our current key.
            throw GroupsV2Error.redundantChange
        }

        Logger.info("Updating profile key for group.")
        try Task.checkCancellation()
        _ = try await GroupManager.updateLocalProfileKey(groupModel: groupModel)
    }
}
