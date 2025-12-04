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

    public func updateLocalProfileKeyInGroup(groupId: Data, transaction: DBWriteTransaction) {
        guard let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) else {
            owsFailDebug("Missing groupThread.")
            return
        }
        self.tryToScheduleGroupForProfileKeyUpdate(groupThread: groupThread, transaction: transaction)

        transaction.addSyncCompletion {
            self.setNeedsUpdate()
        }
    }

    public func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: DBWriteTransaction) {
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

    private func tryToScheduleGroupForProfileKeyUpdate(groupThread: TSGroupThread, transaction: DBWriteTransaction) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationState(tx: transaction).isRegisteredPrimaryDevice else {
            return
        }
        guard let localAddress = tsAccountManager.localIdentifiers(tx: transaction)?.aciAddress else {
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
        self.keyValueStore.setData(groupId, key: key, transaction: transaction)
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
                let groupIdKeys = databaseStorage.read(block: { self.keyValueStore.allKeys(transaction: $0) })
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
                try? await Task.sleep(nanoseconds: OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount, maxAverageBackoff: 6 * .hour).clampedNanoseconds)
            }
        }
    }

    private func _tryToUpdateNext(groupIdKey: String) async throws {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        guard let groupId = databaseStorage.read(block: { tx in keyValueStore.getData(groupIdKey, transaction: tx) }) else {
            return
        }
        let sendPromises: [Promise<Void>]
        do {
            sendPromises = try await self.tryToUpdate(groupId: groupId)
        } catch {
            Logger.warn("\(error)")
            switch error {
            case GroupsV2Error.localUserNotInGroup:
                // If the update is no longer necessary, skip it.
                sendPromises = []
            case let httpError as OWSHTTPError where (400...499).contains(httpError.responseStatusCode):
                // If a non-recoverable error occurs (e.g. we've been kicked out of the
                // group), give up.
                sendPromises = []
            case is CancellationError:
                throw error
            case URLError.cancelled:
                throw error
            case is OWSHTTPError:
                throw error
            case is AppExpiredError:
                throw error
            case _ where error.isNetworkFailureOrTimeout:
                throw error
            case GroupsV2Error.timeout:
                throw error
            default:
                // This should never occur. If it does, we don't want to get stuck in a
                // retry loop.
                owsFailDebug("unexpected error: \(error)")
                sendPromises = []
            }
        }

        // Mark it as complete immediately; we don't need to check this group again
        // if we get interrupted before sending the group update messages.
        await markAsComplete(groupIdKey: groupIdKey)

        // Make a best-effort attempt to wait for group update messages to be sent;
        // this adds back pressure and avoids overwhelming MessageSenderJobQueue.
        for sendPromise in sendPromises {
            try? await sendPromise.awaitableWithUncooperativeCancellationHandling()
            try Task.checkCancellation()
        }
    }

    private func markAsComplete(groupIdKey: String) async {
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            self.keyValueStore.removeValue(forKey: groupIdKey, transaction: transaction)
        }
    }

    /// - Returns: A list of Promises for sending the group update message(s).
    /// Each Promise represents sending a message to one or more recipients.
    private func tryToUpdate(groupId: Data) async throws -> [Promise<Void>] {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard let localAci = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aci else {
            throw OWSGenericError("missing local address")
        }

        try await SSKEnvironment.shared.messageProcessorRef.waitForFetchingAndProcessing()

        let groupModel = SSKEnvironment.shared.databaseStorageRef.read { tx in
            return TSGroupThread.fetch(groupId: groupId, transaction: tx)?.groupModel as? TSGroupModelV2
        }
        guard let groupModel, let secretParams = try? groupModel.secretParams() else {
            throw OWSGenericError("missing secret params")
        }

        // Get latest group state from service and verify that this update is still necessary.
        try Task.checkCancellation()
        // Collect the avatar state to avoid an unnecessary download in the case
        // where we've already fetched the latest avatar.
        let snapshotResponse = try await SSKEnvironment.shared.groupsV2Ref.fetchLatestSnapshot(
            secretParams: secretParams,
            justUploadedAvatars: GroupAvatarStateMap.from(groupModel: groupModel)
        )
        guard snapshotResponse.groupSnapshot.groupMembership.isFullMember(localAci) else {
            // We're not a full member, no need to update profile key.
            return []
        }
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let profileKey = databaseStorage.read(block: profileManager.localUserProfile(tx:))?.profileKey
        guard let profileKey else {
            throw OWSGenericError("missing local profile key")
        }
        guard snapshotResponse.groupSnapshot.profileKeys[localAci] != profileKey.keyData else {
            // Group state already has our current key.
            return []
        }

        Logger.info("Updating profile key for group.")
        try Task.checkCancellation()
        return try await GroupManager.updateLocalProfileKey(groupModel: groupModel)
    }
}
