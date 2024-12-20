//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum BlockMode: UInt {
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

public class BlockingManager: NSObject {
    private let appReadiness: AppReadiness
    private let blockedRecipientStore: any BlockedRecipientStore

    private let lock = UnfairLock()
    private var state = State()

    init(appReadiness: AppReadiness, blockedRecipientStore: any BlockedRecipientStore) {
        self.appReadiness = appReadiness
        self.blockedRecipientStore = blockedRecipientStore

        super.init()

        SwiftSingletons.register(self)
        appReadiness.runNowOrWhenAppWillBecomeReady {
            self.observeNotifications()
            self.loadStateOnLaunch()
        }
    }

    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)
        loadStateOnLaunch()
    }

    private func loadStateOnLaunch() {
        // Pre-warm our cached state
        SSKEnvironment.shared.databaseStorageRef.read {
            withCurrentState(transaction: $0) { _ in }
        }
        // Once we're ready to send a message, check to see if we need to sync.
        appReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            DispatchQueue.global().async {
                self.sendBlockListSyncMessage(force: false)
            }
        }
    }

    fileprivate func withCurrentState<T>(transaction: SDSAnyReadTransaction, _ handler: (State) -> T) -> T {
        lock.withLock {
            state.reloadIfNecessary(blockedRecipientStore: self.blockedRecipientStore, tx: transaction)
            return handler(state)
        }
    }

    @discardableResult
    fileprivate func updateCurrentState(transaction: SDSAnyWriteTransaction, wasLocallyInitiated: Bool, _ handler: (inout State) -> Void) -> Bool {
        lock.withLock {
            state.reloadIfNecessary(blockedRecipientStore: self.blockedRecipientStore, tx: transaction)
            handler(&state)
            let didUpdate = state.persistIfNecessary(blockedRecipientStore: self.blockedRecipientStore, tx: transaction)
            if didUpdate {
                if !wasLocallyInitiated {
                    State.setLastSyncedChangeToken(state.changeToken, transaction: transaction)
                }

                transaction.addAsyncCompletionOffMain {
                    Logger.info("blockListDidChange")
                    if wasLocallyInitiated {
                        self.sendBlockListSyncMessage(force: false)
                    }
                    NotificationCenter.default.postNotificationNameAsync(Self.blockListDidChange, object: nil)
                }
            }
            return didUpdate
        }
    }
}

// MARK: - Public block state accessors

extension BlockingManager {

    // MARK: Readers
    @objc
    public func isAddressBlocked(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        guard !address.isLocalAddress else {
            return false
        }
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        guard let recipientId = recipientDatabaseTable.fetchRecipient(address: address, tx: transaction.asV2Read)?.id else {
            return false
        }
        return withCurrentState(transaction: transaction) { $0.blockedRecipientIds.contains(recipientId) }
    }

    @objc
    public func isGroupIdBlocked(_ groupId: Data, transaction: SDSAnyReadTransaction) -> Bool {
        withCurrentState(transaction: transaction) { state in
            state.blockedGroupMap[groupId] != nil
        }
    }

    public func blockedAddresses(transaction: SDSAnyReadTransaction) -> Set<SignalServiceAddress> {
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable

        let blockedRecipientIds = withCurrentState(transaction: transaction) { $0.blockedRecipientIds }
        return Set(blockedRecipientIds.compactMap {
            return recipientDatabaseTable.fetchRecipient(rowId: $0, tx: transaction.asV2Read)?.address
        })
    }

    public func blockedGroupModels(transaction: SDSAnyReadTransaction) -> [TSGroupModel] {
        withCurrentState(transaction: transaction) { state in
            Array(state.blockedGroupMap.values)
        }
    }

    // MARK: Writers

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
        updateCurrentState(transaction: tx, wasLocallyInitiated: blockMode.locallyInitiated) { state in
            guard state.addBlockedRecipientId(recipient.id!) else {
                return
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
        }
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
        guard !address.isLocalAddress else {
            owsFailDebug("Cannot unblock the local address")
            return
        }

        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
        guard let recipient = recipientDatabaseTable.fetchRecipient(address: address, tx: tx.asV2Read) else {
            // No need to unblock non-existent recipients. They can't possibly be blocked.
            return
        }
        updateCurrentState(transaction: tx, wasLocallyInitiated: wasLocallyInitiated) { state in
            guard state.removeBlockedRecipientId(recipient.id!) else {
                return
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
        }
    }

    public func addBlockedGroup(groupModel: TSGroupModel, blockMode: BlockMode, transaction: SDSAnyWriteTransaction) {
        let groupId = groupModel.groupId
        guard GroupManager.isValidGroupIdOfAnyKind(groupId) else {
            owsFailDebug("Invalid group: \(groupId)")
            return
        }

        updateCurrentState(transaction: transaction, wasLocallyInitiated: blockMode.locallyInitiated) { state in
            guard state.addBlockedGroup(groupModel) else {
                return
            }

            Logger.info("Added blocked groupId: \(groupId.hexadecimalString)")

            if blockMode.locallyInitiated {
                SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(groupModel: groupModel)
            }

            if let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
                // Quit the group if we're a member.
                if
                    blockMode == .localShouldLeaveGroups,
                    groupModel.groupMembership.isLocalUserMemberOfAnyKind,
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
        }
    }

    public func removeBlockedGroup(groupId: Data, wasLocallyInitiated: Bool, transaction: SDSAnyWriteTransaction) {
        guard GroupManager.isValidGroupIdOfAnyKind(groupId) else {
            owsFailDebug("Invalid group: \(groupId)")
            return
        }

        updateCurrentState(transaction: transaction, wasLocallyInitiated: wasLocallyInitiated) { state in
            guard let unblockedGroup = state.removeBlockedGroup(groupId) else {
                return
            }

            Logger.info("Removed blocked groupId: \(groupId.hexadecimalString)")

            if wasLocallyInitiated {
                SSKEnvironment.shared.storageServiceManagerRef.recordPendingUpdates(groupModel: unblockedGroup)
            }

            if let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
                // Refresh unblocked group.
                SSKEnvironment.shared.groupV2UpdatesRef.tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithoutThrottling(groupThread)

                // Insert an info message that we unblocked.
                DependenciesBridge.shared.interactionStore.insertInteraction(
                    TSInfoMessage(thread: groupThread, messageType: .unblockedGroup),
                    tx: transaction.asV2Write
                )
            }
        }
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

    public func addBlockedThread(_ thread: TSThread,
                                 blockMode: BlockMode,
                                 transaction: SDSAnyWriteTransaction) {
        if let contactThread = thread as? TSContactThread {
            addBlockedAddress(contactThread.contactAddress, blockMode: blockMode, transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            addBlockedGroup(groupModel: groupThread.groupModel, blockMode: blockMode, transaction: transaction)
        } else {
            owsFailDebug("Invalid thread: \(type(of: thread))")
        }
    }

    public func removeBlockedThread(_ thread: TSThread,
                                    wasLocallyInitiated: Bool,
                                    transaction: SDSAnyWriteTransaction) {
        if let contactThread = thread as? TSContactThread {
            removeBlockedAddress(contactThread.contactAddress,
                                 wasLocallyInitiated: wasLocallyInitiated,
                                 transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            removeBlockedGroup(groupId: groupThread.groupId,
                               wasLocallyInitiated: wasLocallyInitiated,
                               transaction: transaction)
        } else {
            owsFailDebug("Invalid thread: \(type(of: thread))")
        }
    }

    public func addBlockedGroup(groupId: Data, blockMode: BlockMode, transaction: SDSAnyWriteTransaction) {
        // Since we're in a write transaction, current state shouldn't have updated between this read
        // and the following write. I'm just using the `withCurrentState` method here to avoid reenterancy
        // that'd require having a separate helper implementation.
        let groupModelToUse: TSGroupModel? = withCurrentState(transaction: transaction) { state in
            if let existingModel = state.blockedGroupMap[groupId] {
                return existingModel
            } else if let currentThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
                return currentThread.groupModel
            } else {
                return GroupManager.fakeGroupModel(groupId: groupId)
            }
        }

        if let groupModelToUse = groupModelToUse {
            addBlockedGroup(groupModel: groupModelToUse, blockMode: blockMode, transaction: transaction)
        }
    }
}

// MARK: - Syncing

extension BlockingManager {
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

        updateCurrentState(transaction: transaction, wasLocallyInitiated: false) { state in
            // We store the list of blocked groups as GroupModels (not group ids)
            // so that we can display the group names in the block list UI, if
            // possible.
            //
            // * If we have an existing group model, we use it to preserve the group name.
            // * If we can find the group thread, we use it to preserve the group name.
            // * If we only know the group id, we use a "fake" group model with only the group id.
            let newBlockedGroups: [Data: TSGroupModel] = blockedGroupIds.dictionaryMappingToValues { (blockedGroupId: Data) -> TSGroupModel? in
                if let existingModel = state.blockedGroupMap[blockedGroupId] {
                    return existingModel
                } else if let currentThread = TSGroupThread.fetch(groupId: blockedGroupId, transaction: transaction) {
                    return currentThread.groupModel
                } else {
                    return GroupManager.fakeGroupModel(groupId: blockedGroupId)
                }
            }.compactMapValues { $0 }

            var blockedRecipientIds = Set<SignalRecipient.RowId>()

            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            for blockedAci in blockedAcis {
                blockedRecipientIds.insert(recipientFetcher.fetchOrCreate(serviceId: blockedAci, tx: transaction.asV2Write).id!)
            }
            for blockedPhoneNumber in blockedPhoneNumbers.compactMap(E164.init) {
                blockedRecipientIds.insert(recipientFetcher.fetchOrCreate(phoneNumber: blockedPhoneNumber, tx: transaction.asV2Write).id!)
            }

            state.replace(blockedRecipientIds: blockedRecipientIds, blockedGroups: newBlockedGroups)
        }
    }

    public func syncBlockList(completion: @escaping () -> Void) {
        DispatchQueue.global().async {
            self.sendBlockListSyncMessage(force: true)
            completion()
        }
    }

    private func sendBlockListSyncMessage(force: Bool) {
        let tsAccountManager = DependenciesBridge.shared.tsAccountManager
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else { return }

        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            withCurrentState(transaction: transaction) { state in
                // If we're not forcing a sync, then we only sync if our last synced token is stale
                // and we're not in the NSE. We'll leaving syncing to the main app.
                if !force {
                    guard state.needsSync(transaction: transaction) else {
                        return
                    }
                    guard !CurrentAppContext().isNSE else {
                        return
                    }
                }

                let possibleThread = TSContactThread.getOrCreateLocalThread(transaction: transaction)
                guard let thread = possibleThread else {
                    owsFailDebug("Missing thread.")
                    return
                }

                let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable
                let blockedRecipients = state.blockedRecipientIds.compactMap {
                    return recipientDatabaseTable.fetchRecipient(rowId: $0, tx: transaction.asV2Read)
                }

                let outgoingChangeToken = state.changeToken
                let message = OWSBlockedPhoneNumbersMessage(
                    thread: thread,
                    phoneNumbers: blockedRecipients.compactMap { $0.phoneNumber?.stringValue },
                    aciStrings: blockedRecipients.compactMap { $0.aci?.serviceIdString },
                    groupIds: Array(state.blockedGroupMap.keys),
                    transaction: transaction
                )

                if TestingFlags.optimisticallyCommitSyncToken {
                    // Tests can opt in to setting this token early. This won't be executed in production.
                    State.setLastSyncedChangeToken(outgoingChangeToken, transaction: transaction)
                }
                let preparedMessage = PreparedOutgoingMessage.preprepared(
                    transientMessageWithoutAttachments: message
                )

                SSKEnvironment.shared.messageSenderJobQueueRef.add(
                    .promise,
                    message: preparedMessage,
                    transaction: transaction
                ).done(on: DispatchQueue.global()) {
                    Logger.info("Successfully sent blocked phone numbers sync message")

                    // Record the last block list which we successfully synced..
                    SSKEnvironment.shared.databaseStorageRef.write { transaction in
                        State.setLastSyncedChangeToken(outgoingChangeToken, transaction: transaction)
                    }
                }.catch { error in
                    owsFailDebugUnlessNetworkFailure(error)
                }
            }
        }
    }
}

// MARK: - Notifications

extension BlockingManager {
    @objc
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
        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            DispatchQueue.global().async {
                self.sendBlockListSyncMessage(force: false)
            }
        }
    }
}

// MARK: - Persistence

extension BlockingManager {
    struct State {
        private(set) var isDirty: Bool
        private(set) var changeToken: UInt64
        private(set) var blockedRecipientIds: Set<SignalRecipient.RowId>
        private(set) var blockedGroupMap: [Data: TSGroupModel]   // GroupId -> GroupModel

        static let invalidChangeToken: UInt64 = 0
        static let initialChangeToken: UInt64 = 1

        fileprivate init() {
            // We're okay initializing with empty data since it'll be reloaded on first access
            // Only non-zero change tokens should ever be stored in the database, so we'll pick up on the mismatch
            isDirty = false
            changeToken = Self.invalidChangeToken
            blockedRecipientIds = []
            blockedGroupMap = [:]
        }

        func needsSync(transaction readTx: SDSAnyReadTransaction) -> Bool {
            owsAssertDebug(changeToken != Self.invalidChangeToken)

            if let lastSyncedToken = State.fetchLastSyncedChangeToken(readTx) {
                return changeToken != lastSyncedToken

            } else if changeToken > Self.initialChangeToken {
                // If we've made changes and we don't have a last synced token, we must require a sync
                return true

            } else {
                // If we don't have a last synced change token, we can use the existence of one of our
                // old KVS keys as a hint that we may need to sync. If they don't exist this is
                // probably a fresh install and we don't need to sync.
                let hasOldKey = PersistenceKey.Legacy.allCases.contains { key in
                    Self.keyValueStore.hasValue(key.rawValue, transaction: readTx.asV2Read)
                }
                return hasOldKey
            }
        }

        // MARK: - Mutation

        mutating func replace(
            blockedRecipientIds newBlockedRecipientIds: Set<SignalRecipient.RowId>,
            blockedGroups newBlockedGroups: [Data: TSGroupModel]
        ) {
            owsAssertDebug(changeToken != Self.invalidChangeToken)

            let oldBlockedRecipientIds = self.blockedRecipientIds
            let oldBlockedGroupMap = self.blockedGroupMap

            self.blockedRecipientIds = newBlockedRecipientIds
            self.blockedGroupMap = newBlockedGroups

            isDirty = isDirty || (oldBlockedRecipientIds != self.blockedRecipientIds)
            isDirty = isDirty || (oldBlockedGroupMap != self.blockedGroupMap)
        }

        @discardableResult
        mutating func addBlockedRecipientId(_ recipientId: SignalRecipient.RowId) -> Bool {
            owsAssertDebug(changeToken != Self.invalidChangeToken)

            let didInsert = blockedRecipientIds.insert(recipientId).inserted
            isDirty = isDirty || didInsert
            return didInsert
        }

        @discardableResult
        mutating func removeBlockedRecipientId(_ recipientId: SignalRecipient.RowId) -> Bool {
            owsAssertDebug(changeToken != Self.invalidChangeToken)

            let didRemove = blockedRecipientIds.remove(recipientId) != nil
            isDirty = isDirty || didRemove
            return didRemove
        }

        @discardableResult
        mutating func addBlockedGroup(_ model: TSGroupModel) -> Bool {
            owsAssertDebug(changeToken != Self.invalidChangeToken)

            var didInsert = false
            if blockedGroupMap[model.groupId] == nil {
                blockedGroupMap[model.groupId] = model
                didInsert = true
            }
            isDirty = didInsert || isDirty
            return didInsert
        }

        @discardableResult
        mutating func removeBlockedGroup(_ groupId: Data) -> TSGroupModel? {
            owsAssertDebug(changeToken != Self.invalidChangeToken)

            let oldValue = blockedGroupMap.removeValue(forKey: groupId)
            isDirty = isDirty || (oldValue != nil)
            return oldValue
        }

        // MARK: Persistence

        static let keyValueStore = KeyValueStore(collection: "kOWSBlockingManager_BlockedPhoneNumbersCollection")

        enum PersistenceKey: String {
            case changeTokenKey = "kOWSBlockingManager_ChangeTokenKey"
            case lastSyncedChangeTokenKey = "kOWSBlockingManager_LastSyncedChangeTokenKey"
            case blockedGroupMapKey = "kOWSBlockingManager_BlockedGroupMapKey"

            // No longer in use
            enum Legacy: String, CaseIterable {
                case syncedBlockedPhoneNumbersKey = "kOWSBlockingManager_SyncedBlockedPhoneNumbersKey"
                case syncedBlockedUUIDsKey = "kOWSBlockingManager_SyncedBlockedUUIDsKey"
                case syncedBlockedGroupIdsKey = "kOWSBlockingManager_SyncedBlockedGroupIdsKey"
            }
        }

        mutating func reloadIfNecessary(blockedRecipientStore: any BlockedRecipientStore, tx transaction: SDSAnyReadTransaction) {
            owsAssertDebug(isDirty == false)

            let databaseChangeToken: UInt64 = Self.keyValueStore.getUInt64(
                PersistenceKey.changeTokenKey.rawValue,
                defaultValue: Self.initialChangeToken,
                transaction: transaction.asV2Read
            )

            if databaseChangeToken != changeToken {
                changeToken = Self.keyValueStore.getUInt64(
                    PersistenceKey.changeTokenKey.rawValue,
                    defaultValue: Self.initialChangeToken,
                    transaction: transaction.asV2Read
                )
                blockedRecipientIds = Set((try? blockedRecipientStore.blockedRecipientIds(tx: transaction.asV2Read)) ?? [])
                blockedGroupMap = Self.keyValueStore.getData(PersistenceKey.blockedGroupMapKey.rawValue, transaction: transaction.asV2Read).flatMap {
                    do {
                        return try NSKeyedUnarchiver.unarchiveTopLevelObjectWithData($0)
                    } catch {
                        owsFailDebug("Couldn't decode blocked groups.")
                        return nil
                    }
                } as? [Data: TSGroupModel] ?? [:]
                isDirty = false
            }
        }

        mutating func persistIfNecessary(blockedRecipientStore: any BlockedRecipientStore, tx transaction: SDSAnyWriteTransaction) -> Bool {
            guard changeToken != Self.invalidChangeToken else {
                owsFailDebug("Attempting to persist an unfetched change token. Aborting...")
                return false
            }

            if isDirty {
                let databaseChangeToken = Self.keyValueStore.getUInt64(
                    PersistenceKey.changeTokenKey.rawValue,
                    defaultValue: Self.initialChangeToken,
                    transaction: transaction.asV2Read
                )
                owsAssertDebug(databaseChangeToken == changeToken)

                changeToken = databaseChangeToken + 1
                Self.keyValueStore.setUInt64(changeToken, key: PersistenceKey.changeTokenKey.rawValue, transaction: transaction.asV2Write)
                Self.keyValueStore.setObject(blockedGroupMap, key: PersistenceKey.blockedGroupMapKey.rawValue, transaction: transaction.asV2Write)
                do {
                    let oldBlockedRecipientIds = Set(try blockedRecipientStore.blockedRecipientIds(tx: transaction.asV2Read))
                    let newBlockedRecipientIds = self.blockedRecipientIds
                    try oldBlockedRecipientIds.subtracting(newBlockedRecipientIds).forEach {
                        try blockedRecipientStore.setBlocked(false, recipientId: $0, tx: transaction.asV2Write)
                    }
                    try newBlockedRecipientIds.subtracting(oldBlockedRecipientIds).forEach {
                        try blockedRecipientStore.setBlocked(true, recipientId: $0, tx: transaction.asV2Write)
                    }
                } catch {
                    DatabaseCorruptionState.flagDatabaseCorruptionIfNecessary(userDefaults: CurrentAppContext().appUserDefaults(), error: error)
                    owsFailDebug("Couldn't update BlockedRecipients: \(error)")
                }
                isDirty = false
                return true

            } else {
                return false
            }
        }

        static func fetchLastSyncedChangeToken(_ readTx: SDSAnyReadTransaction) -> UInt64? {
            Self.keyValueStore.getUInt64(PersistenceKey.lastSyncedChangeTokenKey.rawValue, transaction: readTx.asV2Read)
        }

        static func setLastSyncedChangeToken(_ newValue: UInt64, transaction writeTx: SDSAnyWriteTransaction) {
            Self.keyValueStore.setUInt64(newValue, key: PersistenceKey.lastSyncedChangeTokenKey.rawValue, transaction: writeTx.asV2Write)
        }
    }
}

// MARK: - Testing Helpers

extension BlockingManager {
    enum TestingFlags {
        // Usually, we wait until after MessageSender finishes sending before commiting our last-sync
        // token. It's easier to just expose a knob for tests to force an early commit than having a test wait
        // for some nonexistent send.
        #if TESTABLE_BUILD
        static var optimisticallyCommitSyncToken = false
        #else
        static let optimisticallyCommitSyncToken = false
        #endif
    }
}

#if TESTABLE_BUILD

extension BlockingManager {
    func _testingOnly_needsSyncMessage(_ readTx: SDSAnyReadTransaction) -> Bool {
        state.needsSync(transaction: readTx)
    }

    func _testingOnly_clearNeedsSyncMessage(_ writeTx: SDSAnyWriteTransaction) {
        State.setLastSyncedChangeToken(state.changeToken, transaction: writeTx)
    }
}

extension BlockingManager.State {
    static func _testing_createEmpty() -> BlockingManager.State {
        return .init()
    }

    mutating func _testingOnly_resetDirtyBit() {
        isDirty = false
    }
}

#endif
