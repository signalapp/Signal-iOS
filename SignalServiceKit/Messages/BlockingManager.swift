//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum BlockMode {
    case remote
    case restoreFromBackup
    case localShouldLeaveGroups
    case localShouldNotLeaveGroups

    var locallyInitiated: Bool {
        switch self {
        case .remote, .restoreFromBackup:
            return false
        case .localShouldLeaveGroups, .localShouldNotLeaveGroups:
            return true
        }
    }
}

// MARK: -

public class BlockingManager {
    private let blockedGroupStore: BlockedGroupStore
    private let blockedRecipientStore: BlockedRecipientStore

    private let syncQueue = SerialTaskQueue()

#if TESTABLE_BUILD
    func flushSyncQueueTask() -> Task<Void, any Error> {
        return self.syncQueue.enqueue {}
    }
#endif

    init(
        blockedGroupStore: BlockedGroupStore,
        blockedRecipientStore: BlockedRecipientStore,
    ) {
        self.blockedGroupStore = blockedGroupStore
        self.blockedRecipientStore = blockedRecipientStore
    }

    private func didUpdate(wasLocallyInitiated: Bool, tx: DBWriteTransaction) {
        if wasLocallyInitiated {
            setNeedsSync(tx: tx)
        } else {
            clearNeedsSync(tx: tx)
        }
        tx.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: Self.blockListDidChange, object: nil)
        }
    }

    private func setNeedsSync(tx: DBWriteTransaction) {
        setChangeToken(fetchChangeToken(tx: tx) + 1, tx: tx)
        tx.addSyncCompletion {
            self.syncQueue.enqueue { [self] in
                do {
                    try await syncBlockListIfNecessary(force: false)
                } catch {
                    Logger.warn("Failed to sync block list! \(error)")
                }
            }
        }
    }

    private func clearNeedsSync(tx: DBWriteTransaction) {
        setLastSyncedChangeToken(fetchChangeToken(tx: tx), transaction: tx)
    }

    public func isAddressBlocked(_ address: SignalServiceAddress, transaction: DBReadTransaction) -> Bool {
        guard !address.isLocalAddress else {
            return false
        }
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        guard let recipientId = recipientDatabaseTable.fetchRecipient(address: address, tx: transaction)?.id else {
            return false
        }
        return isRecipientBlocked(recipientId: recipientId, tx: transaction)
    }

    public func isRecipientBlocked(recipientId: SignalRecipient.RowId, tx: DBReadTransaction) -> Bool {
        return blockedRecipientStore.isBlocked(recipientId: recipientId, tx: tx)
    }

    public func isGroupIdBlocked(_ groupId: GroupIdentifier, transaction tx: DBReadTransaction) -> Bool {
        return _isGroupIdBlocked(groupId.serialize(), tx: tx)
    }

    public func isGroupIdBlocked_deprecated(_ groupId: Data, tx: DBReadTransaction) -> Bool {
        return _isGroupIdBlocked(groupId, tx: tx)
    }

    private func _isGroupIdBlocked(_ groupId: Data, tx: DBReadTransaction) -> Bool {
        return blockedGroupStore.isBlocked(groupId: groupId, tx: tx)
    }

    public func blockedRecipientIds(tx: DBReadTransaction) -> Set<SignalRecipient.RowId> {
        return Set(blockedRecipientStore.blockedRecipientIds(tx: tx))
    }

    public func blockedAddresses(transaction: DBReadTransaction) -> Set<SignalServiceAddress> {
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable

        let blockedRecipientIds = self.blockedRecipientIds(tx: transaction)
        return Set(blockedRecipientIds.compactMap {
            return recipientDatabaseTable.fetchRecipient(rowId: $0, tx: transaction)?.address
        })
    }

    public func blockedGroupIds(transaction: DBReadTransaction) -> [Data] {
        return blockedGroupStore.blockedGroupIds(tx: transaction)
    }

    public func addBlockedAci(_ aci: Aci, blockMode: BlockMode, tx: DBWriteTransaction) {
        self.addBlockedAddress(SignalServiceAddress(aci), blockMode: blockMode, transaction: tx)
    }

    public func addBlockedAddress(
        _ address: SignalServiceAddress,
        blockMode: BlockMode,
        transaction tx: DBWriteTransaction,
    ) {
        guard !address.isLocalAddress else {
            owsFailDebug("Cannot block the local address")
            return
        }

        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipient: SignalRecipient
        if let serviceId = address.serviceId {
            recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx)
        } else if let phoneNumber = E164(address.phoneNumber) {
            recipient = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx)
        } else {
            owsFailDebug("Invalid address: \(address).")
            return
        }

        let isBlocked = blockedRecipientStore.isBlocked(recipientId: recipient.id, tx: tx)
        guard !isBlocked else {
            return
        }
        blockedRecipientStore.setBlocked(true, recipientId: recipient.id, tx: tx)

        Logger.info("Added blocked address: \(address)")

        if blockMode.locallyInitiated {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedAddresses: [address])
        }

        // We will start dropping new stories from the blocked address;
        // delete any existing ones we already have.
        if let aci = address.aci {
            StoryManager.deleteAllStories(forSender: aci, tx: tx)
        }
        let storyRecipientManager = DependenciesBridge.shared.storyRecipientManager
        storyRecipientManager.removeRecipientIdFromAllPrivateStoryThreads(
            recipient.id,
            shouldUpdateStorageService: true,
            tx: tx,
        )

        switch blockMode {
        case .restoreFromBackup:
            // If we're restoring from a Backup, avoid the side effect of
            // inserting a message. One either existed in the backup or not.
            break
        case .remote, .localShouldLeaveGroups, .localShouldNotLeaveGroups:
            // Insert an info message that we blocked this user.
            let threadStore = DependenciesBridge.shared.threadStore
            let interactionStore = DependenciesBridge.shared.interactionStore
            if let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx) {
                interactionStore.insertInteraction(
                    TSInfoMessage(thread: contactThread, messageType: .blockedOtherUser),
                    tx: tx,
                )
            }
        }

        didUpdate(wasLocallyInitiated: blockMode.locallyInitiated, tx: tx)
    }

    public func removeBlockedAddress(
        _ address: SignalServiceAddress,
        wasLocallyInitiated: Bool,
        transaction tx: DBWriteTransaction,
    ) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }

        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        guard let recipient = recipientDatabaseTable.fetchRecipient(address: address, tx: tx) else {
            // No need to unblock non-existent recipients. They can't possibly be blocked.
            return
        }

        let isBlocked = blockedRecipientStore.isBlocked(recipientId: recipient.id, tx: tx)
        guard isBlocked else {
            return
        }
        blockedRecipientStore.setBlocked(false, recipientId: recipient.id, tx: tx)

        Logger.info("Removed blocked address: \(address)")

        if wasLocallyInitiated {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedAddresses: [address])
        }

        // Insert an info message that we unblocked this user.
        let threadStore = DependenciesBridge.shared.threadStore
        let interactionStore = DependenciesBridge.shared.interactionStore
        if let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx) {
            interactionStore.insertInteraction(
                TSInfoMessage(thread: contactThread, messageType: .unblockedOtherUser),
                tx: tx,
            )
        }

        didUpdate(wasLocallyInitiated: wasLocallyInitiated, tx: tx)
    }

    public func addBlockedGroupId(_ groupId: Data, blockMode: BlockMode, transaction: DBWriteTransaction) {
        guard GroupManager.isValidGroupIdOfAnyKind(groupId) else {
            owsFailDebug("Can't block invalid groupId: \(groupId.toHex())")
            return
        }

        let isBlocked = blockedGroupStore.isBlocked(groupId: groupId, tx: transaction)
        guard !isBlocked else {
            return
        }
        blockedGroupStore.setBlocked(true, groupId: groupId, tx: transaction)

        Logger.info("Added blocked groupId: \(groupId.toHex())")

        let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction)
        owsAssertDebug(groupThread != nil, "Must have TSGroupThread in order to block it.")

        if blockMode.locallyInitiated, let masterKey = try? (groupThread?.groupModel as? TSGroupModelV2)?.masterKey() {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedGroupV2MasterKeys: [masterKey])
        }

        if let groupThread {
            // Quit the group if we're a member.
            if
                blockMode == .localShouldLeaveGroups,
                groupThread.groupModel.groupMembership.isLocalUserMemberOfAnyKind
            {
                GroupManager.leaveGroupOrDeclineInviteAsyncWithoutUI(
                    groupThread: groupThread,
                    tx: transaction,
                )
            }

            switch blockMode {
            case .restoreFromBackup:
                // If we're restoring from a Backup, avoid the side effect of
                // inserting a message. One either existed in the backup or not.
                break
            case .remote, .localShouldLeaveGroups, .localShouldNotLeaveGroups:
                // Insert an info message that we blocked this group.
                DependenciesBridge.shared.interactionStore.insertInteraction(
                    TSInfoMessage(thread: groupThread, messageType: .blockedGroup),
                    tx: transaction,
                )
            }
        }

        didUpdate(wasLocallyInitiated: blockMode.locallyInitiated, tx: transaction)
    }

    public func removeBlockedGroup(groupId: Data, wasLocallyInitiated: Bool, transaction: DBWriteTransaction) {
        let isBlocked = blockedGroupStore.isBlocked(groupId: groupId, tx: transaction)
        guard isBlocked else {
            return
        }
        blockedGroupStore.setBlocked(false, groupId: groupId, tx: transaction)

        Logger.info("Removed blocked groupId: \(groupId.toHex())")

        let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction)

        if wasLocallyInitiated {
            let masterKey = { () -> GroupMasterKey? in
                if let groupThread {
                    return try? (groupThread.groupModel as? TSGroupModelV2)?.masterKey()
                }
                if GroupManager.isV2GroupId(groupId) {
                    // TODO: Check groups we're still trying to restore from Storage Service.
                }
                return nil
            }()
            if let masterKey {
                SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedGroupV2MasterKeys: [masterKey])
            }
        }

        if let groupThread {
            // Insert an info message that we unblocked.
            DependenciesBridge.shared.interactionStore.insertInteraction(
                TSInfoMessage(thread: groupThread, messageType: .unblockedGroup),
                tx: transaction,
            )

            // Refresh unblocked group.
            transaction.addSyncCompletion {
                SSKEnvironment.shared.groupV2UpdatesRef.refreshGroupUpThroughCurrentRevision(groupThread: groupThread, throttle: false)
            }
        }

        didUpdate(wasLocallyInitiated: wasLocallyInitiated, tx: transaction)
    }

    // MARK: Other convenience access

    public func isThreadBlocked(_ thread: TSThread, transaction: DBReadTransaction) -> Bool {
        if let contactThread = thread as? TSContactThread {
            return isAddressBlocked(contactThread.contactAddress, transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            return _isGroupIdBlocked(groupThread.groupModel.groupId, tx: transaction)
        } else if thread is TSPrivateStoryThread {
            return false
        } else {
            owsFailDebug("Invalid thread: \(type(of: thread))")
            return false
        }
    }

    public func addBlockedThread(_ thread: TSThread, blockMode: BlockMode, transaction: DBWriteTransaction) {
        if let contactThread = thread as? TSContactThread {
            addBlockedAddress(contactThread.contactAddress, blockMode: blockMode, transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            addBlockedGroupId(groupThread.groupId, blockMode: blockMode, transaction: transaction)
        } else {
            owsFailDebug("Invalid thread: \(type(of: thread))")
        }
    }

    public func removeBlockedThread(_ thread: TSThread, wasLocallyInitiated: Bool, transaction: DBWriteTransaction) {
        if let contactThread = thread as? TSContactThread {
            removeBlockedAddress(contactThread.contactAddress, wasLocallyInitiated: wasLocallyInitiated, transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            removeBlockedGroup(groupId: groupThread.groupId, wasLocallyInitiated: wasLocallyInitiated, transaction: transaction)
        } else {
            owsFailDebug("Invalid thread: \(type(of: thread))")
        }
    }

    // MARK: - Syncing

    public func processIncomingSync(
        blockedPhoneNumbers: Set<String>,
        blockedAcis: Set<Aci>,
        blockedGroupIds: Set<Data>,
        tx transaction: DBWriteTransaction,
    ) {
        Logger.info("")
        transaction.addSyncCompletion {
            NotificationCenter.default.postOnMainThread(name: Self.blockedSyncDidComplete, object: nil)
        }

        var didChange = false

        let oldBlockedGroupIds = Set(blockedGroupStore.blockedGroupIds(tx: transaction))
        let newBlockedGroupIds = blockedGroupIds
        oldBlockedGroupIds.subtracting(newBlockedGroupIds).forEach {
            didChange = true
            blockedGroupStore.setBlocked(false, groupId: $0, tx: transaction)
        }
        newBlockedGroupIds.subtracting(oldBlockedGroupIds).forEach {
            didChange = true
            blockedGroupStore.setBlocked(true, groupId: $0, tx: transaction)
        }

        var blockedRecipientIds = Set<SignalRecipient.RowId>()
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        for blockedAci in blockedAcis {
            blockedRecipientIds.insert(recipientFetcher.fetchOrCreate(serviceId: blockedAci, tx: transaction).id)
        }
        for blockedPhoneNumber in blockedPhoneNumbers.compactMap(E164.init) {
            blockedRecipientIds.insert(recipientFetcher.fetchOrCreate(phoneNumber: blockedPhoneNumber, tx: transaction).id)
        }

        let oldBlockedRecipientIds = Set(blockedRecipientStore.blockedRecipientIds(tx: transaction))
        let newBlockedRecipientIds = blockedRecipientIds
        oldBlockedRecipientIds.subtracting(newBlockedRecipientIds).forEach {
            didChange = true
            blockedRecipientStore.setBlocked(false, recipientId: $0, tx: transaction)
        }
        newBlockedRecipientIds.subtracting(oldBlockedRecipientIds).forEach {
            didChange = true
            blockedRecipientStore.setBlocked(true, recipientId: $0, tx: transaction)
        }

        if didChange {
            didUpdate(wasLocallyInitiated: false, tx: transaction)
        }
    }

    public func syncBlockListIfNecessary(force: Bool) async throws {
        let sendResult = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx -> (sendPromise: Promise<Void>, changeToken: UInt64)? in
            // If we're not forcing a sync, then we only sync if our last synced token is stale
            // and we're not in the NSE. We'll leaving syncing to the main app.
            let changeToken = fetchChangeToken(tx: tx)
            if !force {
                guard shouldSync(changeToken: changeToken, tx: tx) else {
                    return nil
                }
                guard !CurrentAppContext().isNSE else {
                    throw OWSGenericError("Can't send in the NSE.")
                }
            }

            let tsAccountManager = DependenciesBridge.shared.tsAccountManager
            let registeredState = try tsAccountManager.registeredState(tx: tx)

            let localThread = TSContactThread.getOrCreateThread(
                withContactAddress: registeredState.localIdentifiers.aciAddress,
                transaction: tx,
            )

            let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
            let blockedRecipients = blockedRecipientStore.blockedRecipientIds(tx: tx).compactMap {
                return recipientDatabaseTable.fetchRecipient(rowId: $0, tx: tx)
            }

            let blockedGroupIds = blockedGroupStore.blockedGroupIds(tx: tx)

            let message = OWSBlockedPhoneNumbersMessage(
                localThread: localThread,
                phoneNumbers: blockedRecipients.compactMap { $0.phoneNumber?.stringValue },
                aciStrings: blockedRecipients.compactMap { $0.aci?.serviceIdString },
                groupIds: Array(blockedGroupIds),
                transaction: tx,
            )

            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: message,
            )

            let sendPromise = SSKEnvironment.shared.messageSenderJobQueueRef.add(
                .promise,
                message: preparedMessage,
                transaction: tx,
            )

            return (sendPromise, changeToken)
        }

        guard let sendResult else {
            return
        }

        try await sendResult.sendPromise.awaitable()

        // Record the last block list which we successfully synced..
        await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
            setLastSyncedChangeToken(sendResult.changeToken, transaction: transaction)
        }
    }

    private func shouldSync(changeToken: UInt64, tx: DBReadTransaction) -> Bool {
        // If we've ever sync'd with this mechanism, we need only sync again if the
        // token has changed.
        if let lastSyncedChangeToken = fetchLastSyncedChangeToken(tx: tx) {
            return changeToken != lastSyncedChangeToken
        }
        // Otherwise, if we've made any change, we must sync.
        if changeToken > Constants.initialChangeToken {
            return true
        }
        // If we don't have a last synced change token, we can use the existence of
        // one of our old KVS keys as a hint that we may need to sync. If they
        // don't exist this is probably a fresh install and we don't need to sync.
        return PersistenceKey.Legacy.allCases.contains { key in
            return keyValueStore.hasValue(key.rawValue, transaction: tx)
        }
    }

    // MARK: - Notifications

    public static let blockListDidChange = Notification.Name("blockListDidChange")
    public static let blockedSyncDidComplete = Notification.Name("blockedSyncDidComplete")

    // MARK: - Persistence

    private enum Constants {
        static let initialChangeToken: UInt64 = 1
    }

    private let keyValueStore = KeyValueStore(collection: "kOWSBlockingManager_BlockedPhoneNumbersCollection")

    enum PersistenceKey: String {
        case changeTokenKey = "kOWSBlockingManager_ChangeTokenKey"
        case lastSyncedChangeTokenKey = "kOWSBlockingManager_LastSyncedChangeTokenKey"

        // No longer in use
        enum Legacy: String, CaseIterable {
            case syncedBlockedPhoneNumbersKey = "kOWSBlockingManager_SyncedBlockedPhoneNumbersKey"
            case syncedBlockedUUIDsKey = "kOWSBlockingManager_SyncedBlockedUUIDsKey"
            case syncedBlockedGroupIdsKey = "kOWSBlockingManager_SyncedBlockedGroupIdsKey"
        }
    }

    func fetchChangeToken(tx: DBReadTransaction) -> UInt64 {
        keyValueStore.getUInt64(PersistenceKey.changeTokenKey.rawValue, defaultValue: Constants.initialChangeToken, transaction: tx)
    }

    func setChangeToken(_ newValue: UInt64, tx: DBWriteTransaction) {
        keyValueStore.setUInt64(newValue, key: PersistenceKey.changeTokenKey.rawValue, transaction: tx)
    }

    func fetchLastSyncedChangeToken(tx: DBReadTransaction) -> UInt64? {
        keyValueStore.getUInt64(PersistenceKey.lastSyncedChangeTokenKey.rawValue, transaction: tx)
    }

    func setLastSyncedChangeToken(_ newValue: UInt64, transaction writeTx: DBWriteTransaction) {
        keyValueStore.setUInt64(newValue, key: PersistenceKey.lastSyncedChangeTokenKey.rawValue, transaction: writeTx)
    }
}
