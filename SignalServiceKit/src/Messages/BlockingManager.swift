//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

public enum BlockMode: UInt {
    case remote
    case localShouldLeaveGroups
    case localShouldNotLeaveGroups

    var locallyInitiated: Bool {
        switch self {
        case .remote:
            return false
        case .localShouldLeaveGroups:
            return true
        case .localShouldNotLeaveGroups:
            return true
        }
    }
}

// MARK: -

public class BlockingManager: NSObject {
    private let lock = UnfairLock()
    private var state = State()

    public required override init() {
        super.init()
        SwiftSingletons.register(self)
        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.loadStateOnLaunch()
        }
    }

    public func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)
        loadStateOnLaunch()
    }

    private func loadStateOnLaunch() {
        // Pre-warm our cached state
        databaseStorage.read {
            withCurrentState(transaction: $0) { _ in }
        }
        // Once we're ready to send a message, check to see if we need to sync.
        AppReadiness.runNowOrWhenAppDidBecomeReadyAsync {
            DispatchQueue.global().async {
                self.sendBlockListSyncMessage(force: false)
            }
        }
        observeNotifications()
    }

    fileprivate func withCurrentState<T>(transaction: SDSAnyReadTransaction, _ handler: (State) -> T) -> T {
        lock.withLock {
            state.reloadIfNecessary(transaction)
            return handler(state)
        }
    }

    @discardableResult
    fileprivate func updateCurrentState(transaction: SDSAnyWriteTransaction, wasLocallyInitiated: Bool, _ handler: (inout State) -> Void) -> Bool {
        lock.withLock {
            state.reloadIfNecessary(transaction)
            handler(&state)
            let didUpdate = state.persistIfNecessary(transaction)
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
        return withCurrentState(transaction: transaction) { state in
            if let phoneNumber = address.phoneNumber, state.blockedPhoneNumbers.contains(phoneNumber) {
                return true
            }
            if let uuidString = address.uuidString, state.blockedUUIDStrings.contains(uuidString) {
                return true
            }
            return false
        }
    }

    @objc
    public func isGroupIdBlocked(_ groupId: Data, transaction: SDSAnyReadTransaction) -> Bool {
        withCurrentState(transaction: transaction) { state in
            state.blockedGroupMap[groupId] != nil
        }
    }

    @objc
    public func blockedAddresses(transaction: SDSAnyReadTransaction) -> Set<SignalServiceAddress> {
        // TODO UUID - optimize this. Maybe blocking manager should store a SignalServiceAddressSet as
        // it's state instead of the two separate sets.
        withCurrentState(transaction: transaction) { state in
            var addressSet = Set<SignalServiceAddress>()
            state.blockedPhoneNumbers.forEach {
                let address = SignalServiceAddress(phoneNumber: $0)
                if address.isValid {
                    addressSet.insert(address)
                }
            }
            state.blockedUUIDStrings.forEach {
                let address = SignalServiceAddress(uuidString: $0)
                if address.isValid {
                    addressSet.insert(address)
                }
            }
            return addressSet
        }
    }

    public func blockedGroupModels(transaction: SDSAnyReadTransaction) -> [TSGroupModel] {
        withCurrentState(transaction: transaction) { state in
            Array(state.blockedGroupMap.values)
        }
    }

    // MARK: Writers

    public func addBlockedAddress(_ address: SignalServiceAddress, blockMode: BlockMode, transaction: SDSAnyWriteTransaction) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }
        guard !address.isLocalAddress else {
            owsFailDebug("Cannot block the local address")
            return
        }
        updateCurrentState(transaction: transaction, wasLocallyInitiated: blockMode.locallyInitiated) { state in
            let didAdd = state.addBlockedAddress(address)
            if didAdd && blockMode.locallyInitiated {
                storageServiceManager.recordPendingUpdates(updatedAddresses: [address])
            }
        }
    }

    public func removeBlockedAddress(_ address: SignalServiceAddress, wasLocallyInitiated: Bool, transaction: SDSAnyWriteTransaction) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }
        guard !address.isLocalAddress else {
            owsFailDebug("Cannot unblock the local address")
            return
        }
        updateCurrentState(transaction: transaction, wasLocallyInitiated: wasLocallyInitiated) { state in
            let didRemove = state.removeBlockedAddress(address)
            if didRemove && wasLocallyInitiated {
                storageServiceManager.recordPendingUpdates(updatedAddresses: [address])
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
            let didInsert = state.addBlockedGroup(groupModel)
            if didInsert {
                Logger.info("Added blocked groupId: \(groupId.hexadecimalString)")
                TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)

                if blockMode.locallyInitiated {
                    storageServiceManager.recordPendingUpdates(groupModel: groupModel)
                }

                // Quit the group if we're a member.
                if blockMode == .localShouldLeaveGroups,
                   groupModel.groupMembership.isLocalUserMemberOfAnyKind,
                   let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction),
                   groupThread.isLocalUserMemberOfAnyKind {
                    GroupManager.leaveGroupOrDeclineInviteAsyncWithoutUI(groupThread: groupThread,
                                                                         transaction: transaction,
                                                                         success: nil)
                }
            }
        }
    }

    public func removeBlockedGroup(groupId: Data, wasLocallyInitiated: Bool, transaction: SDSAnyWriteTransaction) {
        guard GroupManager.isValidGroupIdOfAnyKind(groupId) else {
            owsFailDebug("Invalid group: \(groupId)")
            return
        }

        updateCurrentState(transaction: transaction, wasLocallyInitiated: wasLocallyInitiated) { state in
            if let unblockedGroup = state.removeBlockedGroup(groupId) {
                Logger.info("Removed blocked groupId: \(groupId.hexadecimalString)")
                TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)

                if wasLocallyInitiated {
                    storageServiceManager.recordPendingUpdates(groupModel: unblockedGroup)
                }

                // Refresh unblocked group.
                if let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
                    groupV2UpdatesObjc.tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithoutThrottling(groupThread)
                }
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
            TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)
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
    @objc
    public func processIncomingSync(blockedPhoneNumbers: Set<String>, blockedUUIDs: Set<UUID>, blockedGroupIds: Set<Data>, transaction: SDSAnyWriteTransaction) {
        Logger.info("")
        transaction.addAsyncCompletionOnMain {
            NotificationCenter.default.post(name: Self.blockedSyncDidComplete, object: nil)
        }

        updateCurrentState(transaction: transaction, wasLocallyInitiated: false) { state in
            var newBlockedAddresses = Set<SignalServiceAddress>()
            blockedPhoneNumbers.forEach { phoneNumber in
                let blockedAddress = SignalServiceAddress(phoneNumber: phoneNumber)
                if blockedAddress.isValid, blockedAddress.phoneNumber != nil {
                    newBlockedAddresses.insert(blockedAddress)
                }
            }
            blockedUUIDs.forEach { uuid in
                let blockedAddress = SignalServiceAddress(uuid: uuid)
                if blockedAddress.isValid, blockedAddress.uuidString != nil {
                    newBlockedAddresses.insert(blockedAddress)
                }
            }

            // We store the list of blocked groups as GroupModels (not group ids)
            // so that we can display the group names in the block list UI, if
            // possible.
            //
            // * If we have an existing group model, we use it to preserve the group name.
            // * If we can find the group thread, we use it to preserve the group name.
            // * If we only know the group id, we use a "fake" group model with only the group id.
            let newBlockedGroups: [Data: TSGroupModel] = blockedGroupIds.dictionaryMappingToValues { (blockedGroupId: Data) -> TSGroupModel? in
                TSGroupThread.ensureGroupIdMapping(forGroupId: blockedGroupId, transaction: transaction)
                if let existingModel = state.blockedGroupMap[blockedGroupId] {
                    return existingModel
                } else if let currentThread = TSGroupThread.fetch(groupId: blockedGroupId, transaction: transaction) {
                    return currentThread.groupModel
                } else {
                    return GroupManager.fakeGroupModel(groupId: blockedGroupId)
                }
            }.compactMapValues { $0 }

            state.replace(blockedAddresses: newBlockedAddresses, blockedGroups: newBlockedGroups)
        }
    }

    @objc
    public func syncBlockList(completion: @escaping () -> Void) {
        DispatchQueue.global().async {
            self.sendBlockListSyncMessage(force: true)
            completion()
        }
    }

    private func sendBlockListSyncMessage(force: Bool) {
        guard tsAccountManager.isRegistered else { return }

        databaseStorage.write { transaction in
            withCurrentState(transaction: transaction) { state in
                // If we're not forcing a sync, then we only sync if our last synced token is stale
                // and we're not in the NSE. We'll leaving syncing to the main app.
                if !force {
                    guard state.needsSync(transaction: transaction) else {
                        Logger.verbose("Skipping send for unchanged block state")
                        return
                    }
                    guard !CurrentAppContext().isNSE else {
                        Logger.verbose("Needs sync but running from NSE, deferring...")
                        return
                    }
                }

                let possibleThread = TSAccountManager.getOrCreateLocalThread(transaction: transaction)
                guard let thread = possibleThread else {
                    owsFailDebug("Missing thread.")
                    return
                }

                let outgoingChangeToken = state.changeToken
                let message = OWSBlockedPhoneNumbersMessage(
                    thread: thread,
                    phoneNumbers: Array(state.blockedPhoneNumbers),
                    uuids: Array(state.blockedUUIDStrings),
                    groupIds: Array(state.blockedGroupMap.keys), transaction: transaction)

                if TestingFlags.optimisticallyCommitSyncToken {
                    // Tests can opt in to setting this token early. This won't be executed in production.
                    State.setLastSyncedChangeToken(outgoingChangeToken, transaction: transaction)
                }

                sskJobQueues.messageSenderJobQueue.add(
                    .promise,
                    message: message.asPreparer,
                    transaction: transaction
                ).done(on: DispatchQueue.global()) {
                    Logger.info("Successfully sent blocked phone numbers sync message")

                    // Record the last block list which we successfully synced..
                    Self.databaseStorage.write { transaction in
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
    @objc
    public static let blockedSyncDidComplete = Notification.Name("blockedSyncDidComplete")

    fileprivate func observeNotifications() {
        AssertIsOnMainThread()

        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
    }

    @objc
    fileprivate func applicationDidBecomeActive() {
        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
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
        private(set) var blockedPhoneNumbers: Set<String>
        private(set) var blockedUUIDStrings: Set<String>
        private(set) var blockedGroupMap: [Data: TSGroupModel]   // GroupId -> GroupModel

        static let invalidChangeToken: UInt64 = 0
        static let initialChangeToken: UInt64 = 1

        fileprivate init() {
            // We're okay initializing with empty data since it'll be reloaded on first access
            // Only non-zero change tokens should ever be stored in the database, so we'll pick up on the mismatch
            isDirty = false
            changeToken = Self.invalidChangeToken
            blockedPhoneNumbers = Set()
            blockedUUIDStrings = Set()
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
                    Self.keyValueStore.hasValue(forKey: key.rawValue, transaction: readTx)
                }
                return hasOldKey
            }
        }

        // MARK: - Mutation

        mutating func replace(blockedAddresses: Set<SignalServiceAddress>, blockedGroups: [Data: TSGroupModel]) {
            owsAssertDebug(changeToken != Self.invalidChangeToken)

            let oldBlockedNumbers = blockedPhoneNumbers
            let oldBlockedUUIDStrings = blockedUUIDStrings
            let oldBlockedGroupMap = blockedGroupMap

            blockedGroupMap = blockedGroups
            blockedPhoneNumbers = Set()
            blockedUUIDStrings = Set()
            blockedAddresses.forEach { blockedAddress in
                if let phoneNumber = blockedAddress.phoneNumber {
                    blockedPhoneNumbers.insert(phoneNumber)
                }
                if let uuidString = blockedAddress.uuidString {
                    blockedUUIDStrings.insert(uuidString)
                }
            }

            isDirty = isDirty || (oldBlockedNumbers != blockedPhoneNumbers)
            isDirty = isDirty || (oldBlockedUUIDStrings != blockedUUIDStrings)
            isDirty = isDirty || (oldBlockedGroupMap != blockedGroupMap)
        }

        @discardableResult
        mutating func addBlockedAddress(_ address: SignalServiceAddress) -> Bool {
            owsAssertDebug(changeToken != Self.invalidChangeToken)

            var didInsert = false
            if let phoneNumber = address.phoneNumber {
                let result = blockedPhoneNumbers.insert(phoneNumber)
                didInsert = didInsert || result.inserted
            }
            if let uuidString = address.uuidString {
                let result = blockedUUIDStrings.insert(uuidString)
                didInsert = didInsert || result.inserted
            }
            isDirty = isDirty || didInsert
            return didInsert
        }

        @discardableResult
        mutating func removeBlockedAddress(_ address: SignalServiceAddress) -> Bool {
            owsAssertDebug(changeToken != Self.invalidChangeToken)

            var didRemove = false
            if let phoneNumber = address.phoneNumber, blockedPhoneNumbers.contains(phoneNumber) {
                blockedPhoneNumbers.remove(phoneNumber)
                didRemove = true
            }
            if let uuidString = address.uuidString, blockedUUIDStrings.contains(uuidString) {
                blockedUUIDStrings.remove(uuidString)
                didRemove = true
            }
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

        static let keyValueStore = SDSKeyValueStore(collection: "kOWSBlockingManager_BlockedPhoneNumbersCollection")

        enum PersistenceKey: String {
            case changeTokenKey = "kOWSBlockingManager_ChangeTokenKey"
            case lastSyncedChangeTokenKey = "kOWSBlockingManager_LastSyncedChangeTokenKey"
            case blockedPhoneNumbersKey = "kOWSBlockingManager_BlockedPhoneNumbersKey"
            case blockedUUIDsKey = "kOWSBlockingManager_BlockedUUIDsKey"
            case blockedGroupMapKey = "kOWSBlockingManager_BlockedGroupMapKey"

            // No longer in use
            enum Legacy: String, CaseIterable {
                case syncedBlockedPhoneNumbersKey = "kOWSBlockingManager_SyncedBlockedPhoneNumbersKey"
                case syncedBlockedUUIDsKey = "kOWSBlockingManager_SyncedBlockedUUIDsKey"
                case syncedBlockedGroupIdsKey = "kOWSBlockingManager_SyncedBlockedGroupIdsKey"
            }
        }

        mutating func reloadIfNecessary(_ transaction: SDSAnyReadTransaction) {
            owsAssertDebug(isDirty == false)

            let databaseChangeToken: UInt64 = Self.keyValueStore.getUInt64(
                PersistenceKey.changeTokenKey.rawValue,
                defaultValue: Self.initialChangeToken,
                transaction: transaction)

            if databaseChangeToken != changeToken {
                func fetchObject<T>(of type: T.Type, key: String, defaultValue: T) -> T {
                    if let storedObject = Self.keyValueStore.getObject(forKey: key, transaction: transaction) {
                        owsAssertDebug(storedObject is T)
                        return (storedObject as? T) ?? defaultValue
                    } else {
                        return defaultValue
                    }
                }
                changeToken = Self.keyValueStore.getUInt64(
                    PersistenceKey.changeTokenKey.rawValue,
                    defaultValue: Self.initialChangeToken,
                    transaction: transaction)
                blockedPhoneNumbers = Set(fetchObject(of: [String].self, key: PersistenceKey.blockedPhoneNumbersKey.rawValue, defaultValue: []))
                blockedUUIDStrings = Set(fetchObject(of: [String].self, key: PersistenceKey.blockedUUIDsKey.rawValue, defaultValue: []))
                blockedGroupMap = fetchObject(of: [Data: TSGroupModel].self, key: PersistenceKey.blockedGroupMapKey.rawValue, defaultValue: [:])
                isDirty = false
            }
        }

        mutating func persistIfNecessary(_ transaction: SDSAnyWriteTransaction) -> Bool {
            guard changeToken != Self.invalidChangeToken else {
                owsFailDebug("Attempting to persist an unfetched change token. Aborting...")
                return false
            }

            if isDirty {
                let databaseChangeToken = Self.keyValueStore.getUInt64(
                    PersistenceKey.changeTokenKey.rawValue,
                    defaultValue: Self.initialChangeToken,
                    transaction: transaction)
                owsAssertDebug(databaseChangeToken == changeToken)

                changeToken = databaseChangeToken + 1
                Self.keyValueStore.setUInt64(changeToken, key: PersistenceKey.changeTokenKey.rawValue, transaction: transaction)
                Self.keyValueStore.setObject(Array(blockedPhoneNumbers), key: PersistenceKey.blockedPhoneNumbersKey.rawValue, transaction: transaction)
                Self.keyValueStore.setObject(Array(blockedUUIDStrings), key: PersistenceKey.blockedUUIDsKey.rawValue, transaction: transaction)
                Self.keyValueStore.setObject(blockedGroupMap, key: PersistenceKey.blockedGroupMapKey.rawValue, transaction: transaction)
                isDirty = false
                return true

            } else {
                return false
            }
        }

        static func fetchLastSyncedChangeToken(_ readTx: SDSAnyReadTransaction) -> UInt64? {
            Self.keyValueStore.getUInt64(PersistenceKey.lastSyncedChangeTokenKey.rawValue, transaction: readTx)
        }

        static func setLastSyncedChangeToken(_ newValue: UInt64, transaction writeTx: SDSAnyWriteTransaction) {
            Self.keyValueStore.setUInt64(newValue, key: PersistenceKey.lastSyncedChangeTokenKey.rawValue, transaction: writeTx)
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
