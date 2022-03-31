//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

@objc
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
    private var state: State = State(isDirty: false, changeToken: 0, blockedPhoneNumbers: Set(), blockedUUIDStrings: Set(), blockedGroupMap: [:])

    @objc
    public required override init() {
        super.init()
        SwiftSingletons.register(self)
        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.loadStateOnLaunch()
        }
    }

    @objc
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
            self.sendBlockListSyncMessage(force: false)
        }
        observeNotifications()
    }

    fileprivate func withCurrentState<T>(transaction: SDSAnyReadTransaction, _ handler: (State) -> T) -> T {
        return lock.withLock {
            state.reloadIfNecessary(transaction)
            return handler(state)
        }
    }

    @discardableResult
    fileprivate func updateCurrentState(transaction: SDSAnyWriteTransaction, wasLocallyInitiated: Bool, _ handler: (inout State) -> Void) -> Bool {
        return lock.withLock {
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
        withCurrentState(transaction: transaction) { state in
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

    @objc
    public func blockedGroupModels(transaction: SDSAnyReadTransaction) -> [TSGroupModel] {
        withCurrentState(transaction: transaction) { state in
            Array(state.blockedGroupMap.values)
        }
    }

    // MARK: Writers

    @objc public func addBlockedAddress(_ address: SignalServiceAddress, blockMode: BlockMode, transaction: SDSAnyWriteTransaction) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }
        updateCurrentState(transaction: transaction, wasLocallyInitiated: blockMode.locallyInitiated) { state in
            let didAdd = state.addBlockedAddress(address)
            if didAdd && blockMode.locallyInitiated {
                storageServiceManager.recordPendingUpdates(updatedAddresses: [address])
            }
        }
    }

    @objc public func removeBlockedAddress(_ address: SignalServiceAddress, wasLocallyInitiated: Bool, transaction: SDSAnyWriteTransaction) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }
        updateCurrentState(transaction: transaction, wasLocallyInitiated: wasLocallyInitiated) { state in
            let didRemove = state.removeBlockedAddress(address)
            if didRemove && wasLocallyInitiated {
                storageServiceManager.recordPendingUpdates(updatedAddresses: [address])
            }
        }
    }

    @objc public func addBlockedGroup(groupModel: TSGroupModel, blockMode: BlockMode, transaction: SDSAnyWriteTransaction) {
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

    @objc public func removeBlockedGroup(groupId: Data, wasLocallyInitiated: Bool, transaction: SDSAnyWriteTransaction) {
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

    @objc
    public func isThreadBlocked(_ thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool {
        if let contactThread = thread as? TSContactThread {
            return isAddressBlocked(contactThread.contactAddress, transaction: transaction)
        } else if let groupThread = thread as? TSGroupThread {
            return isGroupIdBlocked(groupThread.groupModel.groupId, transaction: transaction)
        } else {
            owsFailDebug("Invalid thread: \(type(of: thread))")
            return false
        }
    }

    @objc
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

    @objc
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

    @objc public func addBlockedGroup(groupId: Data, blockMode: BlockMode, transaction: SDSAnyWriteTransaction) {
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
                return GroupManager.fakeGroupModel(groupId: groupId, transaction: transaction)
            }
        }

        if let groupModelToUse = groupModelToUse {
            addBlockedGroup(groupModel: groupModelToUse, blockMode: blockMode, transaction: transaction)
        }
    }
}

// MARK: - Syncing

extension BlockingManager {
    @objc public func processIncomingSync(blockedPhoneNumbers: Set<String>, blockedUUIDs: Set<UUID>, blockedGroupIds: Set<Data>, transaction: SDSAnyWriteTransaction) {
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
                    return GroupManager.fakeGroupModel(groupId: blockedGroupId, transaction: transaction)
                }
            }.compactMapValues { $0 }

            state.replace(blockedAddresses: newBlockedAddresses, blockedGroups: newBlockedGroups)
        }
    }

    @objc public func syncBlockList(completion: @escaping () -> Void) {
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
                    let currentToken = state.changeToken
                    let lastSyncedToken = State.fetchLastSyncedChangeToken(transaction)
                    guard currentToken != lastSyncedToken && !CurrentAppContext().isNSE else {
                        Logger.verbose("Skipping send for unchanged block state")
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
                    groupIds: Array(state.blockedGroupMap.keys))

                messageSenderJobQueue.add(
                    .promise,
                    message: message.asPreparer,
                    transaction: transaction
                ).done(on: .global()) {
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
    @objc public static let blockListDidChange = Notification.Name("blockListDidChange")
    @objc public static let blockedSyncDidComplete = Notification.Name("blockedSyncDidComplete")

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
    fileprivate struct State {
        private(set) var isDirty: Bool
        private(set) var changeToken: UInt64
        private(set) var blockedPhoneNumbers: Set<String>
        private(set) var blockedUUIDStrings: Set<String>
        private(set) var blockedGroupMap: [Data: TSGroupModel]   // GroupId -> GroupModel

        // MARK: - Mutation

        mutating func replace(blockedAddresses: Set<SignalServiceAddress>, blockedGroups: [Data: TSGroupModel]) {
            let oldBlockedNumbers = blockedPhoneNumbers
            let oldBlockedUUIDStrings = blockedUUIDStrings
            let oldBlockedGroupMap = blockedGroupMap

            blockedGroupMap = blockedGroups
            blockedPhoneNumbers = Set()
            blockedUUIDStrings = Set()
            blockedAddresses.forEach { blockedAddress in
                blockedAddress.phoneNumber.map { _ = blockedPhoneNumbers.insert($0) }
                blockedAddress.uuidString.map { _ = blockedUUIDStrings.insert($0) }
            }

            isDirty = false
            isDirty = isDirty || (oldBlockedNumbers != blockedPhoneNumbers)
            isDirty = isDirty || (oldBlockedUUIDStrings != blockedUUIDStrings)
            isDirty = isDirty || (oldBlockedGroupMap != blockedGroupMap)
        }

        @discardableResult
        mutating func addBlockedAddress(_ address: SignalServiceAddress) -> Bool {
            var didInsert = false
            if let phoneNumber = address.phoneNumber, !blockedPhoneNumbers.contains(phoneNumber) {
                blockedPhoneNumbers.insert(phoneNumber)
                didInsert = true
            }
            if let uuidString = address.uuidString, !blockedUUIDStrings.contains(uuidString) {
                blockedUUIDStrings.insert(uuidString)
                didInsert = true
            }
            isDirty = isDirty || didInsert
            return didInsert
        }

        @discardableResult
        mutating func removeBlockedAddress(_ address: SignalServiceAddress) -> Bool {
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
            let oldValue = blockedGroupMap.removeValue(forKey: groupId)
            isDirty = isDirty || (oldValue != nil)
            return oldValue
        }

        // MARK: Persistence
        fileprivate static let keyValueStore = SDSKeyValueStore(collection: "kOWSBlockingManager_BlockedPhoneNumbersCollection")

        // These keys are used to persist the current local "block list" state.
        private static var changeTokenKey: String { "kOWSBlockingManager_ChangeTokenKey" }
        private static var lastSyncedChangeTokenKey: String { "kOWSBlockingManager_LastSyncedChangeTokenKey" }
        private static var blockedPhoneNumbersKey: String { "kOWSBlockingManager_BlockedPhoneNumbersKey" }
        private static var blockedUUIDsKey: String { "kOWSBlockingManager_BlockedUUIDsKey" }
        private static var blockedGroupMapKey: String { "kOWSBlockingManager_BlockedGroupMapKey" }
        // These keys are used to persist the most recently synced remote "block list" state.
        private static var syncedBlockedPhoneNumbersKey: String { "kOWSBlockingManager_SyncedBlockedPhoneNumbersKey" }
        private static var syncedBlockedUUIDsKey: String { "kOWSBlockingManager_SyncedBlockedUUIDsKey" }
        private static var syncedBlockedGroupIdsKey: String { "kOWSBlockingManager_SyncedBlockedGroupIdsKey" }

        mutating func reloadIfNecessary(_ transaction: SDSAnyReadTransaction) {
            owsAssertDebug(isDirty == false)
            let databaseChangeToken: UInt64 = Self.keyValueStore.getUInt64(Self.changeTokenKey, defaultValue: 1, transaction: transaction)

            if databaseChangeToken != changeToken {
                func fetchObject<T>(of type: T.Type, key: String, defaultValue: T) -> T {
                    if let storedObject = Self.keyValueStore.getObject(forKey: key, transaction: transaction) {
                        owsAssertDebug(storedObject is T)
                        return (storedObject as? T) ?? defaultValue
                    } else {
                        return defaultValue
                    }
                }
                changeToken = Self.keyValueStore.getUInt64(Self.changeTokenKey, defaultValue: 1, transaction: transaction)
                blockedPhoneNumbers = Set(fetchObject(of: [String].self, key: Self.blockedPhoneNumbersKey, defaultValue: []))
                blockedUUIDStrings = Set(fetchObject(of: [String].self, key: Self.blockedUUIDsKey, defaultValue: []))
                blockedGroupMap = fetchObject(of: [Data: TSGroupModel].self, key: Self.blockedGroupMapKey, defaultValue: [:])
                isDirty = false
            }
        }

        mutating func persistIfNecessary(_ transaction: SDSAnyWriteTransaction) -> Bool {
            if isDirty {
                let databaseChangeToken = Self.keyValueStore.getUInt64(Self.changeTokenKey, defaultValue: 1, transaction: transaction)
                owsAssertDebug(databaseChangeToken == changeToken)

                changeToken = databaseChangeToken + 1
                Self.keyValueStore.setUInt64(changeToken, key: Self.changeTokenKey, transaction: transaction)
                Self.keyValueStore.setObject(Array(blockedPhoneNumbers), key: Self.blockedPhoneNumbersKey, transaction: transaction)
                Self.keyValueStore.setObject(Array(blockedUUIDStrings), key: Self.blockedUUIDsKey, transaction: transaction)
                Self.keyValueStore.setObject(blockedGroupMap, key: Self.blockedGroupMapKey, transaction: transaction)
                isDirty = false
                return true

            } else {
                return false
            }
        }

        static func fetchLastSyncedChangeToken(_ readTx: SDSAnyReadTransaction) -> UInt64 {
            Self.keyValueStore.getUInt64(Self.lastSyncedChangeTokenKey, defaultValue: 0, transaction: readTx)
        }

        static func setLastSyncedChangeToken(_ newValue: UInt64, transaction writeTx: SDSAnyWriteTransaction) {
            Self.keyValueStore.setUInt64(newValue, key: Self.lastSyncedChangeTokenKey, transaction: writeTx)
        }
    }
}
