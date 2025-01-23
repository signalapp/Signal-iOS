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
    private let appReadiness: AppReadiness
    private let blockedGroupStore: any BlockedGroupStore
    private let blockedRecipientStore: any BlockedRecipientStore

    init(
        appReadiness: AppReadiness,
        blockedGroupStore: any BlockedGroupStore,
        blockedRecipientStore: any BlockedRecipientStore
    ) {
        self.appReadiness = appReadiness
        self.blockedGroupStore = blockedGroupStore
        self.blockedRecipientStore = blockedRecipientStore

        SwiftSingletons.register(self)
        appReadiness.runNowOrWhenAppWillBecomeReady {
            self.observeNotifications()
        }
        // Once we're ready to send a message, check to see if we need to sync.
        syncIfNeeded()
    }

    private func syncIfNeeded() {
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            Task { await self.sendBlockListSyncMessage(force: false) }
        }
    }

    private func didUpdate(wasLocallyInitiated: Bool, tx: SDSAnyWriteTransaction) {
        if wasLocallyInitiated {
            setNeedsSync(tx: tx)
        } else {
            clearNeedsSync(tx: tx)
        }
        tx.addSyncCompletion {
            NotificationCenter.default.postNotificationNameAsync(Self.blockListDidChange, object: nil)
        }
    }

    private func setNeedsSync(tx: SDSAnyWriteTransaction) {
        setChangeToken(fetchChangeToken(tx: tx) + 1, tx: tx)
        tx.addSyncCompletion {
            Task { await self.sendBlockListSyncMessage(force: false) }
        }
    }

    private func clearNeedsSync(tx: SDSAnyWriteTransaction) {
        setLastSyncedChangeToken(fetchChangeToken(tx: tx), transaction: tx)
    }

    public func isAddressBlocked(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        guard !address.isLocalAddress else {
            return false
        }
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        guard let recipientId = recipientDatabaseTable.fetchRecipient(address: address, tx: transaction.asV2Read)?.id else {
            return false
        }
        return (try? blockedRecipientStore.isBlocked(recipientId: recipientId, tx: transaction.asV2Read)) ?? false
    }

    public func isGroupIdBlocked(_ groupId: Data, transaction: SDSAnyReadTransaction) -> Bool {
        return (try? blockedGroupStore.isBlocked(groupId: groupId, tx: transaction.asV2Read)) ?? false
    }

    public func blockedAddresses(transaction: SDSAnyReadTransaction) -> Set<SignalServiceAddress> {
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable

        let blockedRecipientIds = (try? blockedRecipientStore.blockedRecipientIds(tx: transaction.asV2Read)) ?? []
        return Set(blockedRecipientIds.compactMap {
            return recipientDatabaseTable.fetchRecipient(rowId: $0, tx: transaction.asV2Read)?.address
        })
    }

    public func blockedGroupIds(transaction: SDSAnyReadTransaction) throws -> [Data] {
        return try blockedGroupStore.blockedGroupIds(tx: transaction.asV2Read)
    }

    public func addBlockedAci(_ aci: Aci, blockMode: BlockMode, tx: DBWriteTransaction) {
        self.addBlockedAddress(SignalServiceAddress(aci), blockMode: blockMode, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func addBlockedAddress(
        _ address: SignalServiceAddress,
        blockMode: BlockMode,
        transaction tx: SDSAnyWriteTransaction
    ) {
        guard !address.isLocalAddress else {
            owsFailDebug("Cannot block the local address")
            return
        }

        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        let recipient: SignalRecipient
        if let serviceId = address.serviceId {
            recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx.asV2Write)
        } else if let phoneNumber = E164(address.phoneNumber) {
            recipient = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx.asV2Write)
        } else {
            owsFailDebug("Invalid address: \(address).")
            return
        }

        let isBlocked = failIfThrows { try blockedRecipientStore.isBlocked(recipientId: recipient.id!, tx: tx.asV2Read) }
        guard !isBlocked else {
            return
        }
        failIfThrows {
            try blockedRecipientStore.setBlocked(true, recipientId: recipient.id!, tx: tx.asV2Write)
        }

        Logger.info("Added blocked address: \(address)")

        if blockMode.locallyInitiated {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedAddresses: [address])
        }

        // We will start dropping new stories from the blocked address;
        // delete any existing ones we already have.
        if let aci = address.aci {
            StoryManager.deleteAllStories(forSender: aci, tx: tx)
        }
        StoryManager.removeAddressFromAllPrivateStoryThreads(address, tx: tx)

        // Insert an info message that we blocked this user.
        let threadStore = DependenciesBridge.shared.threadStore
        let interactionStore = DependenciesBridge.shared.interactionStore
        if let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx.asV2Read) {
            interactionStore.insertInteraction(
                TSInfoMessage(thread: contactThread, messageType: .blockedOtherUser),
                tx: tx.asV2Write
            )
        }

        didUpdate(wasLocallyInitiated: blockMode.locallyInitiated, tx: tx)
    }

    public func removeBlockedAddress(
        _ address: SignalServiceAddress,
        wasLocallyInitiated: Bool,
        transaction tx: SDSAnyWriteTransaction
    ) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }

        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        guard let recipient = recipientDatabaseTable.fetchRecipient(address: address, tx: tx.asV2Read) else {
            // No need to unblock non-existent recipients. They can't possibly be blocked.
            return
        }

        let isBlocked = failIfThrows { try blockedRecipientStore.isBlocked(recipientId: recipient.id!, tx: tx.asV2Read) }
        guard isBlocked else {
            return
        }
        failIfThrows {
            try blockedRecipientStore.setBlocked(false, recipientId: recipient.id!, tx: tx.asV2Write)
        }

        Logger.info("Removed blocked address: \(address)")

        if wasLocallyInitiated {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedAddresses: [address])
        }

        // Insert an info message that we unblocked this user.
        let threadStore = DependenciesBridge.shared.threadStore
        let interactionStore = DependenciesBridge.shared.interactionStore
        if let contactThread = threadStore.fetchContactThread(recipient: recipient, tx: tx.asV2Read) {
            interactionStore.insertInteraction(
                TSInfoMessage(thread: contactThread, messageType: .unblockedOtherUser),
                tx: tx.asV2Write
            )
        }

        didUpdate(wasLocallyInitiated: wasLocallyInitiated, tx: tx)
    }

    public func addBlockedGroupId(_ groupId: Data, blockMode: BlockMode, transaction: SDSAnyWriteTransaction) {
        guard GroupManager.isValidGroupIdOfAnyKind(groupId) else {
            owsFailDebug("Can't block invalid groupId: g\(groupId.base64EncodedString())")
            return
        }

        let isBlocked = failIfThrows { try blockedGroupStore.isBlocked(groupId: groupId, tx: transaction.asV2Read) }
        guard !isBlocked else {
            return
        }
        failIfThrows {
            try blockedGroupStore.setBlocked(true, groupId: groupId, tx: transaction.asV2Write)
        }

        Logger.info("Added blocked groupId: g\(groupId.base64EncodedString())")

        let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction)
        owsAssertDebug(groupThread != nil, "Must have TSGroupThread in order to block it.")

        if blockMode.locallyInitiated, let masterKey = try? (groupThread?.groupModel as? TSGroupModelV2)?.masterKey() {
            SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedGroupV2MasterKeys: [masterKey.serialize().asData])
        }

        if let groupThread {
            // Quit the group if we're a member.
            if
                blockMode == .localShouldLeaveGroups,
                groupThread.groupModel.groupMembership.isLocalUserMemberOfAnyKind,
                groupThread.isLocalUserMemberOfAnyKind
            {
                GroupManager.leaveGroupOrDeclineInviteAsyncWithoutUI(
                    groupThread: groupThread,
                    transaction: transaction,
                    success: nil
                )
            }

            // Insert an info message that we blocked this group.
            DependenciesBridge.shared.interactionStore.insertInteraction(
                TSInfoMessage(thread: groupThread, messageType: .blockedGroup),
                tx: transaction.asV2Write
            )
        }

        didUpdate(wasLocallyInitiated: blockMode.locallyInitiated, tx: transaction)
    }

    public func removeBlockedGroup(groupId: Data, wasLocallyInitiated: Bool, transaction: SDSAnyWriteTransaction) {
        let isBlocked = failIfThrows { try blockedGroupStore.isBlocked(groupId: groupId, tx: transaction.asV2Read) }
        guard isBlocked else {
            return
        }
        failIfThrows {
            try blockedGroupStore.setBlocked(false, groupId: groupId, tx: transaction.asV2Write)
        }

        Logger.info("Removed blocked groupId: g\(groupId.base64EncodedString())")

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
                SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(updatedGroupV2MasterKeys: [masterKey.serialize().asData])
            }
        }

        if let groupThread {
            // Insert an info message that we unblocked.
            DependenciesBridge.shared.interactionStore.insertInteraction(
                TSInfoMessage(thread: groupThread, messageType: .unblockedGroup),
                tx: transaction.asV2Write
            )

            // Refresh unblocked group.
            transaction.addSyncCompletion {
                SSKEnvironment.shared.groupV2UpdatesRef.refreshGroupUpThroughCurrentRevision(groupThread: groupThread, throttle: false)
            }
        }

        didUpdate(wasLocallyInitiated: wasLocallyInitiated, tx: transaction)
    }

    // MARK: Other convenience access

    public func isThreadBlocked(_ thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        if let contactThread = thread as? TSContactThread {
            return isAddressBlocked(contactThread.contactAddress, transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            return isGroupIdBlocked(groupThread.groupModel.groupId, transaction: transaction)
        } else if thread is TSPrivateStoryThread {
            return false
        } else {
            owsFailDebug("Invalid thread: \(type(of: thread))")
            return false
        }
    }

    public func addBlockedThread(_ thread: TSThread, blockMode: BlockMode, transaction: SDSAnyWriteTransaction) {
        if let contactThread = thread as? TSContactThread {
            addBlockedAddress(contactThread.contactAddress, blockMode: blockMode, transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            addBlockedGroupId(groupThread.groupId, blockMode: blockMode, transaction: transaction)
        } else {
            owsFailDebug("Invalid thread: \(type(of: thread))")
        }
    }

    public func removeBlockedThread(_ thread: TSThread, wasLocallyInitiated: Bool, transaction: SDSAnyWriteTransaction) {
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
        tx transaction: SDSAnyWriteTransaction
    ) {
        Logger.info("")
        transaction.addAsyncCompletionOnMain {
            NotificationCenter.default.post(name: Self.blockedSyncDidComplete, object: nil)
        }

        var didChange = false

        failIfThrows {
            let oldBlockedGroupIds = Set(try blockedGroupStore.blockedGroupIds(tx: transaction.asV2Read))
            let newBlockedGroupIds = blockedGroupIds
            try oldBlockedGroupIds.subtracting(newBlockedGroupIds).forEach {
                didChange = true
                try blockedGroupStore.setBlocked(false, groupId: $0, tx: transaction.asV2Write)
            }
            try newBlockedGroupIds.subtracting(oldBlockedGroupIds).forEach {
                didChange = true
                try blockedGroupStore.setBlocked(true, groupId: $0, tx: transaction.asV2Write)
            }
        }

        var blockedRecipientIds = Set<SignalRecipient.RowId>()
        let recipientFetcher = DependenciesBridge.shared.recipientFetcher
        for blockedAci in blockedAcis {
            blockedRecipientIds.insert(recipientFetcher.fetchOrCreate(serviceId: blockedAci, tx: transaction.asV2Write).id!)
        }
        for blockedPhoneNumber in blockedPhoneNumbers.compactMap(E164.init) {
            blockedRecipientIds.insert(recipientFetcher.fetchOrCreate(phoneNumber: blockedPhoneNumber, tx: transaction.asV2Write).id!)
        }

        failIfThrows {
            let oldBlockedRecipientIds = Set(try blockedRecipientStore.blockedRecipientIds(tx: transaction.asV2Read))
            let newBlockedRecipientIds = blockedRecipientIds
            try oldBlockedRecipientIds.subtracting(newBlockedRecipientIds).forEach {
                didChange = true
                try blockedRecipientStore.setBlocked(false, recipientId: $0, tx: transaction.asV2Write)
            }
            try newBlockedRecipientIds.subtracting(oldBlockedRecipientIds).forEach {
                didChange = true
                try blockedRecipientStore.setBlocked(true, recipientId: $0, tx: transaction.asV2Write)
            }
        }

        if didChange {
            didUpdate(wasLocallyInitiated: false, tx: transaction)
        }
    }

    public func syncBlockList() async {
        await sendBlockListSyncMessage(force: true)
    }

    private func sendBlockListSyncMessage(force: Bool) async {
        do {
            try await _sendBlockListSyncMessage(force: true)
        } catch {
            Logger.warn("\(error)")
        }
    }

    private func _sendBlockListSyncMessage(force: Bool) async throws {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            throw OWSGenericError("Not registered.")
        }

        let sendResult = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { (tx) -> (sendPromise: Promise<Void>, changeToken: UInt64)? in
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

            guard let localThread = TSContactThread.getOrCreateLocalThread(transaction: tx) else {
                throw OWSAssertionError("Missing thread.")
            }

            let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
            let blockedRecipients = try blockedRecipientStore.blockedRecipientIds(tx: tx.asV2Read).compactMap {
                return recipientDatabaseTable.fetchRecipient(rowId: $0, tx: tx.asV2Read)
            }

            let blockedGroupIds = try blockedGroupStore.blockedGroupIds(tx: tx.asV2Read)

            let message = OWSBlockedPhoneNumbersMessage(
                thread: localThread,
                phoneNumbers: blockedRecipients.compactMap { $0.phoneNumber?.stringValue },
                aciStrings: blockedRecipients.compactMap { $0.aci?.serviceIdString },
                groupIds: Array(blockedGroupIds),
                transaction: tx
            )

            let preparedMessage = PreparedOutgoingMessage.preprepared(
                transientMessageWithoutAttachments: message
            )

            let sendPromise = SSKEnvironment.shared.messageSenderJobQueueRef.add(
                .promise,
                message: preparedMessage,
                transaction: tx
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

    private func shouldSync(changeToken: UInt64, tx: SDSAnyReadTransaction) -> Bool {
        if changeToken > Constants.initialChangeToken, changeToken != fetchLastSyncedChangeToken(tx: tx) {
            return true
        }
        // If we don't have a last synced change token, we can use the existence of one of our
        // old KVS keys as a hint that we may need to sync. If they don't exist this is
        // probably a fresh install and we don't need to sync.
        return PersistenceKey.Legacy.allCases.contains { key in
            return keyValueStore.hasValue(key.rawValue, transaction: tx.asV2Read)
        }
    }

    // MARK: - Notifications

    public static let blockListDidChange = Notification.Name("blockListDidChange")
    public static let blockedSyncDidComplete = Notification.Name("blockedSyncDidComplete")

    fileprivate func observeNotifications() {
        AssertIsOnMainThread()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
    }

    @objc
    private func applicationDidBecomeActive() {
        syncIfNeeded()
    }

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

    func fetchChangeToken(tx: SDSAnyReadTransaction) -> UInt64 {
        keyValueStore.getUInt64(PersistenceKey.changeTokenKey.rawValue, defaultValue: Constants.initialChangeToken, transaction: tx.asV2Read)
    }

    func setChangeToken(_ newValue: UInt64, tx: SDSAnyWriteTransaction) {
        keyValueStore.setUInt64(newValue, key: PersistenceKey.changeTokenKey.rawValue, transaction: tx.asV2Write)
    }

    func fetchLastSyncedChangeToken(tx: SDSAnyReadTransaction) -> UInt64? {
        keyValueStore.getUInt64(PersistenceKey.lastSyncedChangeTokenKey.rawValue, transaction: tx.asV2Read)
    }

    func setLastSyncedChangeToken(_ newValue: UInt64, transaction writeTx: SDSAnyWriteTransaction) {
        keyValueStore.setUInt64(newValue, key: PersistenceKey.lastSyncedChangeTokenKey.rawValue, transaction: writeTx.asV2Write)
    }

    // MARK: - Helpers

    private func failIfThrows<T>(_ block: () throws -> T) -> T {
        do {
            return try block()
        } catch {
            DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(userDefaults: CurrentAppContext().appUserDefaults(), error: error)
            owsFail("Couldn't write: \(error)")
        }
    }
}
