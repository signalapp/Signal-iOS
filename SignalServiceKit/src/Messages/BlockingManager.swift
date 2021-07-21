//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public enum BlockMode: UInt {
    case remote
    case localShouldLeaveGroups
    case localShouldNotLeaveGroups
}

// MARK: -

@objc
public class BlockingManager: NSObject {

    @objc
    public static let blockListDidChange = Notification.Name("blockListDidChange")
    @objc
    public static let blockedSyncDidComplete = Notification.Name("blockedSyncDidComplete")

    // MARK: -

    // We don't store the phone numbers as instances of PhoneNumber to avoid
    // consistency issues between clients, but these should all be valid e164
    // phone numbers.
    private static let unfairLock = UnfairLock()
    private var unfairLock: UnfairLock { Self.unfairLock }

    private struct State: Equatable {
        let blockedPhoneNumbers: Set<String>
        let blockedUUIDStrings: Set<String>
        // A map of group id-to-group model.
        let blockedGroupMap: [Data: TSGroupModel]

        static let empty: State = {
            State(blockedPhoneNumbers: Set(),
                  blockedUUIDStrings: Set(),
                  blockedGroupMap: [:])
        }()

        func isBlocked(address: SignalServiceAddress) -> Bool {
            if let phoneNumber = address.phoneNumber,
               blockedPhoneNumbers.contains(phoneNumber) {
                return true
            }
            if let uuidString = address.uuidString,
               blockedUUIDStrings.contains(uuidString) {
                return true
            }
            return false
        }

        func isBlocked(groupId: Data) -> Bool {
            blockedGroupMap[groupId] != nil
        }

        // MARK: - Equatable

        public static func == (lhs: State, rhs: State) -> Bool {
            // Ignore the group models.
            (lhs.blockedPhoneNumbers == rhs.blockedPhoneNumbers &&
                lhs.blockedUUIDStrings == rhs.blockedUUIDStrings &&
                Set(lhs.blockedGroupMap.keys) == Set(rhs.blockedGroupMap.keys))
        }

        // MARK: - Persistence

        fileprivate static let keyValueStore = SDSKeyValueStore(collection: "kOWSBlockingManager_BlockedPhoneNumbersCollection")

        // These keys are used to persist the current local "block list" state.
        private static let blockedPhoneNumbersKey = "kOWSBlockingManager_BlockedPhoneNumbersKey"
        private static let blockedUUIDsKey = "kOWSBlockingManager_BlockedUUIDsKey"
        private static let blockedGroupMapKey = "kOWSBlockingManager_BlockedGroupMapKey"

        // These keys are used to persist the most recently synced remote "block list" state.
        private static let syncedBlockedPhoneNumbersKey = "kOWSBlockingManager_SyncedBlockedPhoneNumbersKey"
        private static let syncedBlockedUUIDsKey = "kOWSBlockingManager_SyncedBlockedUUIDsKey"
        private static let syncedBlockedGroupIdsKey = "kOWSBlockingManager_SyncedBlockedGroupIdsKey"

        static func loadState(transaction: SDSAnyReadTransaction) -> State {
            load(phoneNumbersKey: blockedPhoneNumbersKey,
                 uuidStringsKey: blockedUUIDsKey,
                 groupsKey: blockedGroupMapKey,
                 shouldStoreGroupModels: true,
                 transaction: transaction)
        }

        static func loadSyncedState(transaction: SDSAnyReadTransaction) -> State {
            load(phoneNumbersKey: syncedBlockedPhoneNumbersKey,
                 uuidStringsKey: syncedBlockedUUIDsKey,
                 groupsKey: syncedBlockedGroupIdsKey,
                 shouldStoreGroupModels: false,
                 transaction: transaction)
        }

        private static func load(phoneNumbersKey: String,
                                 uuidStringsKey: String,
                                 groupsKey: String,
                                 shouldStoreGroupModels: Bool,
                                 transaction: SDSAnyReadTransaction) -> State {
            let state: State = {
                let keyValueStore = Self.keyValueStore
                let blockedPhoneNumbers: [String] = keyValueStore.getObject(forKey: phoneNumbersKey,
                                                                            transaction: transaction) as? [String] ?? []
                let blockedUUIDStrings: [String] = keyValueStore.getObject(forKey: uuidStringsKey,
                                                                           transaction: transaction) as? [String] ?? []
                let blockedGroupMap: [Data: TSGroupModel]
                if shouldStoreGroupModels {
                    blockedGroupMap = keyValueStore.getObject(forKey: groupsKey,
                                                              transaction: transaction) as? [Data: TSGroupModel] ?? [:]
                } else {
                    // For "synced" state we only store group ids,
                    // not the group models.  So we fill in fake
                    // group models as necessary.
                    let blockedGroupIds: [Data] = keyValueStore.getObject(forKey: groupsKey,
                                                                          transaction: transaction) as? [Data] ?? []
                    var fakeBlockedGroupMap = [Data: TSGroupModel]()
                    for groupId in blockedGroupIds {
                        let groupModel = GroupManager.fakeGroupModel(groupId: groupId,
                                                                     transaction: transaction)
                        fakeBlockedGroupMap[groupId] = groupModel
                    }
                    blockedGroupMap = fakeBlockedGroupMap
                }
                return State(blockedPhoneNumbers: Set(blockedPhoneNumbers),
                             blockedUUIDStrings: Set(blockedUUIDStrings),
                             blockedGroupMap: blockedGroupMap)
            }()

            // Reduce memory usage by discarding group avatars.
            var blockedGroupMap = [Data: TSGroupModel]()
            for groupModel in state.blockedGroupMap.values {
                groupModel.discardGroupAvatarForBlockingManager()
                blockedGroupMap[groupModel.groupId] = groupModel
            }

            return State(blockedPhoneNumbers: state.blockedPhoneNumbers,
                         blockedUUIDStrings: state.blockedUUIDStrings,
                         blockedGroupMap: blockedGroupMap)
        }

        func saveState(transaction: SDSAnyWriteTransaction) {
            save(phoneNumbersKey: Self.blockedPhoneNumbersKey,
                 uuidStringsKey: Self.blockedUUIDsKey,
                 groupsKey: Self.blockedGroupMapKey,
                 shouldStoreGroupModels: true,
                 transaction: transaction)
        }

        func saveSyncedState(transaction: SDSAnyWriteTransaction) {
            save(phoneNumbersKey: Self.syncedBlockedPhoneNumbersKey,
                 uuidStringsKey: Self.syncedBlockedUUIDsKey,
                 groupsKey: Self.syncedBlockedGroupIdsKey,
                 shouldStoreGroupModels: false,
                 transaction: transaction)
        }

        private func save(phoneNumbersKey: String,
                          uuidStringsKey: String,
                          groupsKey: String,
                          shouldStoreGroupModels: Bool,
                          transaction: SDSAnyWriteTransaction) {
            let keyValueStore = Self.keyValueStore
            keyValueStore.setObject(Array(blockedPhoneNumbers),
                                    key: phoneNumbersKey,
                                    transaction: transaction)
            keyValueStore.setObject(Array(blockedUUIDStrings),
                                    key: uuidStringsKey,
                                    transaction: transaction)
            if shouldStoreGroupModels {
                // Store "group id-to-group model" map.
                keyValueStore.setObject(blockedGroupMap,
                                        key: groupsKey,
                                        transaction: transaction)
            } else {
                // Store "group id" array.
                keyValueStore.setObject(Array(blockedGroupMap.keys),
                                        key: groupsKey,
                                        transaction: transaction)
            }
        }
    }

    // An in-memory cache of current database state.
    //
    // This property should only be accessed with unfairLock acquired.
    private var _currentState: State?
    // This var should only be accessed with unfairLock acquired.
    private var currentState: State {
        get {
            guard let currentState = _currentState else {
                owsFailDebug("Accessed state before it was cached.")
                return .empty
            }
            return currentState
        }
        set {
            _currentState = newValue
        }
    }

    @objc
    public required override init() {
        super.init()

        SwiftSingletons.register(self)

        AppReadiness.runNowOrWhenAppWillBecomeReady {
            self.loadStateOnLaunch()
        }
    }

    private func observeNotifications() {
        AssertIsOnMainThread()

        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil
        )
    }

    // MARK: - Initialization

    @objc
    public func warmCaches() {
        loadStateOnLaunch()
    }

    private func loadStateOnLaunch() {
        AssertIsOnMainThread()

        unfairLock.withLock {
            _currentState = nil
            loadState()
        }
    }

    private func wasLocallyInitiated(withBlockMode blockMode: BlockMode) -> Bool {
        blockMode != .remote
    }

    // MARK: - Sync

    @objc
    public func processIncomingSync(blockedPhoneNumbers: Set<String>,
                                    blockedUUIDs: Set<UUID>,
                                    blockedGroupIds: Set<Data>,
                                    transaction: SDSAnyWriteTransaction) {
        Logger.info("")

        transaction.addAsyncCompletionOnMain {
            NotificationCenter.default.post(name: Self.blockedSyncDidComplete, object: nil)
        }

        // Since we store uuidStrings, rather than UUIDs, we need to
        // be sure to round-trip any foreign input to ensure consistent
        // serialization.
        let blockedUUIDStrings = Set(blockedUUIDs.compactMap { $0.uuidString })

        // We store the list of blocked groups as GroupModels (not group ids)
        // so that we can display the group names in the block list UI, if
        // possible.
        //
        // * If we have an existing group model, we use it to preserve the group name.
        // * If we can find the group thread, we use it to preserve the group name.
        // * If we only know the group id, we use a "fake" group model with only the group id.
        //
        // Try to fill in missing TSGroupModels before we acquire unfairLock.
        var transitionalBlockedGroupMap: [Data: TSGroupModel] = unfairLock.withLock {
            self.currentState.blockedGroupMap
        }
        for groupId in blockedGroupIds {
            if nil != transitionalBlockedGroupMap[groupId] {
                continue
            }

            TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)
            guard let groupThread = TSGroupThread.fetch(groupId: groupId,
                                                        transaction: transaction) else {
                continue
            }
            transitionalBlockedGroupMap[groupId] = groupThread.groupModel
        }

        let state: State? = unfairLock.withLock {
            let oldState = self.currentState

            // The new "blocked group" state should reflect the state from the sync.
            // If possible we re-use a group model from the old "blocked group" state
            // or from the database; otherwise we use a "fake" group model.
            // See above.
            var blockedGroupMap = [Data: TSGroupModel]()
            for groupId in blockedGroupIds {
                if let groupModel = transitionalBlockedGroupMap[groupId] {
                    blockedGroupMap[groupId] = groupModel
                } else {
                    let groupModel = GroupManager.fakeGroupModel(groupId: groupId,
                                                                 transaction: transaction)
                    blockedGroupMap[groupId] = groupModel
                }
            }

            let newState = State(blockedPhoneNumbers: blockedPhoneNumbers,
                                 blockedUUIDStrings: blockedUUIDStrings,
                                 blockedGroupMap: blockedGroupMap)

            let hasChanges = (newState.blockedPhoneNumbers != oldState.blockedPhoneNumbers ||
                                newState.blockedUUIDStrings != oldState.blockedUUIDStrings ||
                                newState.blockedGroupMap.keys != oldState.blockedGroupMap.keys)
            guard hasChanges else {
                return nil
            }

            self.currentState = newState

            return newState
        }

        guard let newState = state else {
            // No changes.
            return
        }

        Self.handleUpdate(newState: newState,
                          sendSyncMessage: false,
                          transaction: transaction)
    }

    // MARK: - Contact Blocking

    public var blockedAddresses: Set<SignalServiceAddress> {
        let state = unfairLock.withLock {
            self.currentState
        }
        var blockedAddresses = Set<SignalServiceAddress>()
        for phoneNumber in state.blockedPhoneNumbers {
            blockedAddresses.insert(SignalServiceAddress(phoneNumber: phoneNumber))
        }
        for uuidString in state.blockedUUIDStrings {
            blockedAddresses.insert(SignalServiceAddress(uuidString: uuidString))
        }
        // TODO UUID - optimize this. Maybe blocking manager should store a SignalServiceAddressSet as
        // it's state instead of the two separate sets.
        return blockedAddresses
    }

    @objc
    public func addBlockedAddress(_ address: SignalServiceAddress,
                                  blockMode: BlockMode,
                                  transaction: SDSAnyWriteTransaction) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }

        let state: State? = unfairLock.withLock {
            let oldState = self.currentState
            guard !oldState.isBlocked(address: address) else {
                return nil
            }

            var blockedPhoneNumbers = oldState.blockedPhoneNumbers
            var blockedUUIDStrings = oldState.blockedUUIDStrings
            let blockedGroupMap = oldState.blockedGroupMap

            if let phoneNumber = address.phoneNumber {
                blockedPhoneNumbers.insert(phoneNumber)
            }
            if let uuidString = address.uuidString {
                blockedUUIDStrings.insert(uuidString)
            }
            let newState = State(blockedPhoneNumbers: blockedPhoneNumbers,
                                 blockedUUIDStrings: blockedUUIDStrings,
                                 blockedGroupMap: blockedGroupMap)
            self.currentState = newState
            return newState
        }
        guard let newState = state else {
            // No changes.
            return
        }

        Logger.info("addBlockedAddress: \(address)")

        // TODO: Should we consult "didChange" or "isBlockedAfter != isBlockedBefore".
        // What if isBlocked didn't change but now we know one of the address components
        // that we didn't before?
        let wasLocallyInitiated = self.wasLocallyInitiated(withBlockMode: blockMode)
        if wasLocallyInitiated {
            // The block state changed, schedule a backup with the storage service
            storageServiceManager.recordPendingUpdates(updatedAddresses: [address])
        }

        Self.handleUpdate(newState: newState,
                          sendSyncMessage: wasLocallyInitiated,
                          transaction: transaction)
    }

    @objc
    public func removeBlockedAddress(_ address: SignalServiceAddress,
                                     wasLocallyInitiated: Bool,
                                     transaction: SDSAnyWriteTransaction) {
        guard address.isValid else {
            owsFailDebug("Invalid address: \(address).")
            return
        }

        let state: State? = unfairLock.withLock {
            let oldState = self.currentState

            guard oldState.isBlocked(address: address) else {
                return nil
            }

            var blockedPhoneNumbers = oldState.blockedPhoneNumbers
            var blockedUUIDStrings = oldState.blockedUUIDStrings
            let blockedGroupMap = oldState.blockedGroupMap

            if let phoneNumber = address.phoneNumber {
                blockedPhoneNumbers.remove(phoneNumber)
            }
            if let uuidString = address.uuidString {
                blockedUUIDStrings.remove(uuidString)
            }
            let newState = State(blockedPhoneNumbers: blockedPhoneNumbers,
                                 blockedUUIDStrings: blockedUUIDStrings,
                                 blockedGroupMap: blockedGroupMap)
            self.currentState = newState
            return newState
        }
        guard let newState = state else {
            // No changes.
            return
        }

        Logger.info("removeBlockedAddress: \(address)")

        if wasLocallyInitiated {
            // The block state changed, schedule a backup with the storage service
            storageServiceManager.recordPendingUpdates(updatedAddresses: [address])
        }

        Self.handleUpdate(newState: newState,
                          sendSyncMessage: wasLocallyInitiated,
                          transaction: transaction)
    }

    @objc
    public var blockedPhoneNumbers: Set<String> {
        unfairLock.withLock { self.currentState.blockedPhoneNumbers }
    }

    @objc
    public var blockedUUIDStrings: Set<String> {
        unfairLock.withLock { self.currentState.blockedUUIDStrings }
    }

    @objc
    public func isAddressBlocked(_ address: SignalServiceAddress) -> Bool {
        unfairLock.withLock { self.currentState.isBlocked(address: address) }
    }

    // MARK: - Group Blocking

    @objc
    public var blockedGroupIds: Set<Data> {
        let blockedGroupIds = unfairLock.withLock { self.currentState.blockedGroupMap.keys }
        return Set(blockedGroupIds)
    }

    @objc
    public var blockedGroupModels: [TSGroupModel] {
        unfairLock.withLock { Array(self.currentState.blockedGroupMap.values) }
    }

    @objc
    public func isGroupIdBlocked(_ groupId: Data) -> Bool {
        unfairLock.withLock { self.currentState.isBlocked(groupId: groupId) }
    }

    private func cachedGroupModel(forGroupId groupId: Data) -> TSGroupModel? {
        unfairLock.withLock { self.currentState.blockedGroupMap[groupId] }
    }

    @objc
    public func addBlockedGroup(groupModel: TSGroupModel,
                                blockMode: BlockMode,
                                transaction: SDSAnyWriteTransaction) {
        let groupId = groupModel.groupId
        owsAssertDebug(GroupManager.isValidGroupIdOfAnyKind(groupId))

        let state: State? = unfairLock.withLock {
            let oldState = self.currentState

            guard !oldState.isBlocked(groupId: groupId) else {
                // Already blocked.
                return nil
            }

            let blockedPhoneNumbers = oldState.blockedPhoneNumbers
            let blockedUUIDStrings = oldState.blockedUUIDStrings
            var blockedGroupMap = oldState.blockedGroupMap

            blockedGroupMap[groupId] = groupModel

            let newState = State(blockedPhoneNumbers: blockedPhoneNumbers,
                                 blockedUUIDStrings: blockedUUIDStrings,
                                 blockedGroupMap: blockedGroupMap)
            self.currentState = newState
            return newState
        }
        guard let newState = state else {
            // Already blocked.
            return
        }

        Logger.info("groupId: \(groupId.hexadecimalString)")

        TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)

        // Quit the group if we're a member.
        if blockMode == .localShouldLeaveGroups,
           groupModel.groupMembership.isLocalUserMemberOfAnyKind,
           let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction),
           groupThread.isLocalUserMemberOfAnyKind {
            GroupManager.leaveGroupOrDeclineInviteAsyncWithoutUI(groupThread: groupThread,
                                                                 transaction: transaction,
                                                                 success: nil)
        }

        let wasLocallyInitiated = self.wasLocallyInitiated(withBlockMode: blockMode)

        if wasLocallyInitiated {
            // The block state changed, schedule a backup with the storage service.
            storageServiceManager.recordPendingUpdates(groupModel: groupModel)
        }

        Self.handleUpdate(newState: newState,
                          sendSyncMessage: wasLocallyInitiated,
                          transaction: transaction)
    }

    @objc
    public func addBlockedGroup(groupId: Data,
                                blockMode: BlockMode,
                                transaction: SDSAnyWriteTransaction) {

        let groupModel: TSGroupModel = {
            if let groupModel = self.cachedGroupModel(forGroupId: groupId) {
                return groupModel
            }
            TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)
            if let groupThread = TSGroupThread.fetch(groupId: groupId,
                                                     transaction: transaction) {
                return groupThread.groupModel
            }
            return GroupManager.fakeGroupModel(groupId: groupId, transaction: transaction)!
        }()

        addBlockedGroup(groupModel: groupModel,
                        blockMode: blockMode,
                        transaction: transaction)
    }

    @objc
    public func removeBlockedGroup(groupId: Data,
                                   wasLocallyInitiated: Bool,
                                   transaction: SDSAnyWriteTransaction) {
        owsAssertDebug(GroupManager.isValidGroupIdOfAnyKind(groupId))

        let result: (State, TSGroupModel)? = unfairLock.withLock {
            let oldState = self.currentState

            guard let blockedGroupModel = oldState.blockedGroupMap[groupId] else {
                // Not blocked.
                return nil
            }

            let blockedPhoneNumbers = oldState.blockedPhoneNumbers
            let blockedUUIDStrings = oldState.blockedUUIDStrings
            var blockedGroupMap = oldState.blockedGroupMap

            blockedGroupMap.removeValue(forKey: groupId)

            let newState = State(blockedPhoneNumbers: blockedPhoneNumbers,
                                 blockedUUIDStrings: blockedUUIDStrings,
                                 blockedGroupMap: blockedGroupMap)
            self.currentState = newState
            return (newState, blockedGroupModel)
        }
        guard let (newState, blockedGroupModel) = result else {
            owsFailDebug("Group not blocked.")
            return
        }

        Logger.info("groupId: \(groupId.hexadecimalString)")

        TSGroupThread.ensureGroupIdMapping(forGroupId: groupId, transaction: transaction)

        if wasLocallyInitiated {
            // The block state changed, schedule a backup with the storage service.
            storageServiceManager.recordPendingUpdates(groupModel: blockedGroupModel)
        }

        Self.handleUpdate(newState: newState,
                          sendSyncMessage: wasLocallyInitiated,
                          transaction: transaction)

        // Refresh unblocked group.
        if let groupThread = TSGroupThread.fetch(groupId: groupId, transaction: transaction) {
            groupV2UpdatesObjc.tryToRefreshV2GroupUpToCurrentRevisionAfterMessageProcessingWithoutThrottling(groupThread)
        }
    }

    // MARK: - Thread Blocking

    @objc
    public func isThreadBlocked(_ thread: TSThread) -> Bool {
        if let contactThread = thread as? TSContactThread {
            return isAddressBlocked(contactThread.contactAddress)
        } else if let groupThread = thread as? TSGroupThread {
            return isGroupIdBlocked(groupThread.groupModel.groupId)
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

    // MARK: - Updates

    // This should be called every time the block list changes.
    private static func handleUpdate(newState: State,
                                     sendSyncMessage: Bool,
                                     transaction: SDSAnyWriteTransaction) {

        newState.saveState(transaction: transaction)

        transaction.addAsyncCompletionOffMain {
            if sendSyncMessage {
                Self.sendBlockListSyncMessage(state: newState)
            } else {
                // If this update came from an incoming block list sync message,
                // update the "synced blocked list" state immediately,
                // since we're now in sync.
                //
                // There could be data loss if both clients modify the block list
                // at the same time, but:
                //
                // a) Block list changes will be rare.
                // b) Conflicting block list changes will be even rarer.
                // c) It's unlikely a user will make conflicting changes on two
                //    devices around the same time.
                // d) There isn't a good way to avoid this.
                //
                // TODO: Can we make the storage service the single
                // source of truth for this state?
                databaseStorage.write { transaction in
                    newState.saveSyncedState(transaction: transaction)
                }
            }

            Logger.info("blockListDidChange")
            NotificationCenter.default.postNotificationNameAsync(Self.blockListDidChange, object: nil)
        }
    }

    // This method should only be called with unfairLock acquired.
    private func loadState() {
        owsAssertDebug(_currentState == nil)

        Logger.verbose("")

        let state = databaseStorage.read { transaction in
            State.loadState(transaction: transaction)
        }

        _currentState = state

        DispatchQueue.global().async {
            Self.syncBlockListIfNecessary(state: state)
        }

        observeNotifications()
    }

    @objc
    public func syncBlockList() {
        DispatchQueue.global().async {
            let state = Self.unfairLock.withLock { self.currentState }
            Self.sendBlockListSyncMessage(state: state)
        }
    }

    // This method should only be called off the main thread.
    private static func syncBlockListIfNecessary(state: State) {

        // If we haven't yet successfully synced the current "block list" changes,
        // try again to sync now.
        let syncedState = databaseStorage.read { transaction in
            State.loadSyncedState(transaction: transaction)
        }

        guard state != syncedState else {
            Logger.verbose("Ignoring redundant block list sync.")
            return
        }

        Logger.info("Syncing block list.")

        Self.sendBlockListSyncMessage(state: state)
    }

    private static func sendBlockListSyncMessage(state: State) {
        let possibleThread = databaseStorage.write { transaction in
            TSAccountManager.getOrCreateLocalThread(transaction: transaction)
        }
        guard let thread = possibleThread else {
            owsFailDebug("Missing thread.")
            return
        }

        let message = OWSBlockedPhoneNumbersMessage(thread: thread,
                                                    phoneNumbers: Array(state.blockedPhoneNumbers),
                                                    uuids: Array(state.blockedUUIDStrings),
                                                    groupIds: Array(state.blockedGroupMap.keys))

        messageSender.sendMessage(message.asPreparer,
                                  success: {
                                    Logger.info("Successfully sent blocked phone numbers sync message")

                                    // Record the last block list which we successfully synced..
                                    databaseStorage.write { transaction in
                                        state.saveSyncedState(transaction: transaction)
                                    }
                                  },
                                  failure: { error in
                                    owsFailDebugUnlessNetworkFailure(error)
                                  })
    }

    // MARK: - Notifications

    @objc
    private func applicationDidBecomeActive() {
        AssertIsOnMainThread()

        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync {
            DispatchQueue.global().async {
                let state = Self.unfairLock.withLock {
                    self.currentState
                }
                Self.syncBlockListIfNecessary(state: state)
            }
        }
    }
}
