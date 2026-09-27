//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// Whenever we rotate our profile key, we need to update all
// v2 groups of which we are a non-pending member.

// This is laborious, but important. It is too expensive to
// do unless necessary (e.g. we don't want to check every
// group on launch), but important enough to do durably.
//
// This class has responsibility for tracking which groups
// need to be updated and for updating them.
class GroupsV2ProfileKeyUpdater {

    init() {
    }

    // Stores the list of v2 groups that we need to update with our latest profile key.
    private let keyValueStore = NewKeyValueStore(collection: "GroupsV2ProfileKeyUpdater")

    private func key(for groupId: Data) -> String {
        return groupId.hexadecimalString
    }

    func updateLocalProfileKeyInGroup(groupId: GroupIdentifier, tx: DBWriteTransaction) {
        guard let groupThread = TSGroupThread.fetchThread(forGroupId: groupId, tx: tx) else {
            owsFailDebug("Missing groupThread.")
            return
        }
        let didSchedule = self.tryToScheduleGroupForProfileKeyUpdate(groupThread: groupThread, transaction: tx)
        guard didSchedule else {
            return
        }
        tx.addSyncCompletion {
            Task {
                do {
                    try await self.updateIfNeeded()
                } catch {
                    Logger.warn("couldn't update profile key in group: \(error)")
                }
            }
        }
    }

    func scheduleAllGroupsV2ForProfileKeyUpdate(transaction: DBWriteTransaction) {
        TSThread.anyEnumerate(transaction: transaction) { thread, _ in
            guard let groupThread = thread as? TSGroupThread else {
                return
            }
            _ = self.tryToScheduleGroupForProfileKeyUpdate(groupThread: groupThread, transaction: transaction)
        }

        // Note that we don't kick off updates yet (don't schedule tryToUpdateNext
        // for the end of the transaction) because we want to make sure that any
        // profile key update is committed to the server first. This isn't a
        // guarantee because there could *already* be a series of updates going,
        // but it helps in the common case.
    }

    private func tryToScheduleGroupForProfileKeyUpdate(groupThread: TSGroupThread, transaction: DBWriteTransaction) -> Bool {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard
            let registeredState = try? tsAccountManager.registeredState(tx: transaction),
            registeredState.isPrimary
        else {
            return false
        }
        let localAddress = registeredState.localIdentifiers.aciAddress

        let groupMembership = groupThread.groupModel.groupMembership
        // We only need to update v2 groups of which we are a full member.
        guard groupThread.isGroupV2Thread, groupMembership.isFullMember(localAddress), !groupThread.isTerminatedGroup else {
            return false
        }
        let groupId = groupThread.groupModel.groupId
        let key = self.key(for: groupId)
        self.keyValueStore.writeValue(groupId, forKey: key, tx: transaction)
        return true
    }

    private let taskQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    func updateIfNeeded() async throws {
        try await taskQueue.runWithThrowingTask { try await _updateIfNeeded() }
    }

    private func _updateIfNeeded() async throws {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let groupIdKeys = databaseStorage.read(block: { tx in self.keyValueStore.fetchKeys(tx: tx) })
        let taskQueue = ConcurrentTaskQueue(concurrentLimit: 16)
        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for groupIdKey in groupIdKeys {
                _ = taskGroup.addTaskUnlessCancelled {
                    try await taskQueue.runWithThrowingTask {
                        try Task.checkCancellation()
                        try await self._tryToUpdateNext(groupIdKey: groupIdKey)
                    }
                }
            }
            try await taskGroup.waitForAll()
        }
    }

    private func _tryToUpdateNext(groupIdKey: String) async throws {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        guard let groupIdData = databaseStorage.read(block: { tx in keyValueStore.fetchValue(Data.self, forKey: groupIdKey, tx: tx) }) else {
            return
        }
        let sendPromises: [Promise<Void>]
        do {
            let groupId = try GroupIdentifier(contents: groupIdData)
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
            case is NotRegisteredError:
                // If we're not registered, we can't rotate our profile key. We'll schedule
                // another rotation after re-registering.
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
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        await databaseStorage.awaitableWrite { transaction in
            self.keyValueStore.removeValue(forKey: groupIdKey, tx: transaction)
        }
    }

    /// - Returns: A list of Promises for sending the group update message(s).
    /// Each Promise represents sending a message to one or more recipients.
    private func tryToUpdate(groupId: GroupIdentifier) async throws -> [Promise<Void>] {
        let databaseStorage = SSKEnvironment.shared.databaseStorageRef
        let groupsV2 = SSKEnvironment.shared.groupsV2Ref
        let messageProcessor = SSKEnvironment.shared.messageProcessorRef
        let profileManager = SSKEnvironment.shared.profileManagerRef
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager

        // Check if we're a registered primary & wait until we're connected.
        guard try tsAccountManager.registeredStateWithMaybeSneakyTransaction().isPrimary else {
            throw OWSGenericError("not primary")
        }
        try await messageProcessor.waitForFetchingAndProcessing()

        let groupModel = databaseStorage.read { tx in
            return TSGroupThread.fetchThread(forGroupId: groupId, tx: tx)?.groupModel as? TSGroupModelV2
        }
        guard let groupModel, let secretParams = try? groupModel.secretParams() else {
            throw OWSGenericError("missing secret params")
        }

        // Get latest group state from service and verify that this update is still necessary.
        try Task.checkCancellation()
        // Collect the avatar state to avoid an unnecessary download in the case
        // where we've already fetched the latest avatar.
        let snapshotResponse = try await groupsV2.fetchLatestSnapshot(
            secretParams: secretParams,
            justUploadedAvatars: GroupAvatarStateMap.from(groupModel: groupModel),
        )
        // Intentionally fetch this again because substantial time may have elapsed.
        let localAci = try tsAccountManager.registeredStateWithMaybeSneakyTransaction().localIdentifiers.aci
        guard snapshotResponse.groupSnapshot.groupMembership.isFullMember(localAci) else {
            // We're not a full member, no need to update profile key.
            return []
        }
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
        return try await GroupManager.updateLocalProfileKey(secretParams: secretParams)
    }
}
