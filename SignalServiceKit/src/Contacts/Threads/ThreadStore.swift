//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalCoreKit

public protocol ThreadStore {
    /// Covers contact and group threads.
    func enumerateNonStoryThreads(
        tx: DBReadTransaction,
        block: @escaping (TSThread, _ stop: inout Bool) -> Void
    ) throws
    /// Enumerates group threads in "last interaction" order.
    func enumerateGroupThreads(
        tx: DBReadTransaction,
        block: @escaping (TSGroupThread, _ stop: inout Bool) -> Void
    ) throws
    func fetchThread(rowId threadRowId: Int64, tx: DBReadTransaction) -> TSThread?
    func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread?
    func fetchContactThreads(serviceId: ServiceId, tx: DBReadTransaction) -> [TSContactThread]
    func fetchContactThreads(phoneNumber: String, tx: DBReadTransaction) -> [TSContactThread]
    func fetchGroupThread(groupId: Data, tx: DBReadTransaction) -> TSGroupThread?

    func getOrCreateContactThread(with address: SignalServiceAddress, tx: DBWriteTransaction) -> TSContactThread

    func removeThread(_ thread: TSThread, tx: DBWriteTransaction)
    func updateThread(_ thread: TSThread, tx: DBWriteTransaction)

    func update(
        groupThread: TSGroupThread,
        withStorySendEnabled storySendEnabled: Bool,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    )

    /// Note: does not intert any created default associated data into the db.
    /// (This method only takes a read transaction, so it could not insert even if it wanted to)
    func fetchOrDefaultAssociatedData(for thread: TSThread, tx: DBReadTransaction) -> ThreadAssociatedData

    func updateAssociatedData(
        threadAssociatedData: ThreadAssociatedData,
        isArchived: Bool?,
        isMarkedUnread: Bool?,
        mutedUntilTimestamp: UInt64?,
        audioPlaybackRate: Float?,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    )

    func update(
        thread: TSThread,
        withMentionNotificationMode: TSThreadMentionNotificationMode,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction
    )
}

extension ThreadStore {
    public func fetchGroupThread(uniqueId: String, tx: DBReadTransaction) -> TSGroupThread? {
        guard let thread = fetchThread(uniqueId: uniqueId, tx: tx) else {
            return nil
        }
        guard let groupThread = thread as? TSGroupThread else {
            owsFailDebug("Object has unexpected type: \(type(of: thread))")
            return nil
        }
        return groupThread
    }

    /// Fetch a contact thread for the given recipient.
    ///
    /// There may be multiple threads for a given service ID, but there is only
    /// one canonical thread for a recipient. This gets that thread.
    ///
    /// If you simply want a thread, and don't want to think about thread
    /// merges, ACIs, PNIs, etc. – this is the method for you.
    public func fetchContactThread(recipient: SignalRecipient, tx: DBReadTransaction) -> TSContactThread? {
        return UniqueRecipientObjectMerger.fetchAndExpunge(
            for: recipient,
            serviceIdField: \.contactUUID,
            phoneNumberField: \.contactPhoneNumber,
            uniqueIdField: \.uniqueId,
            fetchObjectsForServiceId: { fetchContactThreads(serviceId: $0, tx: tx) },
            fetchObjectsForPhoneNumber: { fetchContactThreads(phoneNumber: $0.stringValue, tx: tx) },
            updateObject: { _ in }
        ).first
    }

    public func updateAssociatedData(
        _ threadAssociatedData: ThreadAssociatedData,
        isArchived: Bool? = nil,
        isMarkedUnread: Bool? = nil,
        mutedUntilTimestamp: UInt64? = nil,
        audioPlaybackRate: Float? = nil,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        self.updateAssociatedData(
            threadAssociatedData: threadAssociatedData,
            isArchived: isArchived,
            isMarkedUnread: isMarkedUnread,
            mutedUntilTimestamp: mutedUntilTimestamp,
            audioPlaybackRate: audioPlaybackRate,
            updateStorageService: updateStorageService,
            tx: tx
        )
    }
}

public class ThreadStoreImpl: ThreadStore {

    public init() {}

    public func enumerateNonStoryThreads(tx: DBReadTransaction, block: @escaping (TSThread, inout Bool) -> Void) throws {
        return try ThreadFinder().enumerateNonStoryThreads(transaction: SDSDB.shimOnlyBridge(tx), block: block)
    }

    public func enumerateGroupThreads(tx: DBReadTransaction, block: @escaping (TSGroupThread, inout Bool) -> Void) throws {
        return try ThreadFinder().enumerateGroupThreads(transaction: SDSDB.shimOnlyBridge(tx), block: block)
    }

    public func fetchThread(rowId threadRowId: Int64, tx: DBReadTransaction) -> TSThread? {
        return ThreadFinder().fetch(rowId: threadRowId, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread? {
        TSThread.anyFetch(uniqueId: uniqueId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchContactThreads(serviceId: ServiceId, tx: DBReadTransaction) -> [TSContactThread] {
        ContactThreadFinder().contactThreads(for: serviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchContactThreads(phoneNumber: String, tx: DBReadTransaction) -> [TSContactThread] {
        ContactThreadFinder().contactThreads(for: phoneNumber, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func fetchGroupThread(groupId: Data, tx: DBReadTransaction) -> TSGroupThread? {
        TSGroupThread.fetch(groupId: groupId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func getOrCreateContactThread(with address: SignalServiceAddress, tx: DBWriteTransaction) -> TSContactThread {
        return TSContactThread.getOrCreateThread(withContactAddress: address, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func removeThread(_ thread: TSThread, tx: DBWriteTransaction) {
        let tx = SDSDB.shimOnlyBridge(tx)

        // TODO: If we ever use transaction finalizations for more than
        // de-bouncing thread touches, we should promote this to TSYapDatabaseObject
        // (or at least include it in the "will remove" hook for any relevant models.
        tx.addRemovedFinalizationKey(thread.transactionFinalizationKey)

        let sql = "DELETE FROM \(thread.sdsTableName) WHERE uniqueId = ?"
        tx.unwrapGrdbWrite.executeAndCacheStatement(sql: sql, arguments: [thread.uniqueId])
    }

    public func updateThread(_ thread: TSThread, tx: DBWriteTransaction) {
        thread.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func update(
        groupThread: TSGroupThread,
        withStorySendEnabled storySendEnabled: Bool,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        groupThread.updateWithStorySendEnabled(
            storySendEnabled,
            transaction: SDSDB.shimOnlyBridge(tx),
            updateStorageService: updateStorageService
        )
    }

    public func fetchOrDefaultAssociatedData(for thread: TSThread, tx: DBReadTransaction) -> ThreadAssociatedData {
        return ThreadAssociatedData.fetchOrDefault(for: thread, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func updateAssociatedData(
        threadAssociatedData: ThreadAssociatedData,
        isArchived: Bool?,
        isMarkedUnread: Bool?,
        mutedUntilTimestamp: UInt64?,
        audioPlaybackRate: Float?,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        threadAssociatedData.updateWith(
            isArchived: isArchived,
            isMarkedUnread: isMarkedUnread,
            mutedUntilTimestamp: mutedUntilTimestamp,
            audioPlaybackRate: audioPlaybackRate,
            updateStorageService: updateStorageService,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }

    public func update(
        thread: TSThread,
        withMentionNotificationMode mode: TSThreadMentionNotificationMode,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction
    ) {
        thread.updateWithMentionNotificationMode(
            mode,
            wasLocallyInitiated: wasLocallyInitiated,
            transaction: SDSDB.shimOnlyBridge(tx)
        )
    }
}

#if TESTABLE_BUILD

public class MockThreadStore: ThreadStore {
    private(set) var threads = [TSThread]()
    public var nextRowId: Int64 = 1

    public func enumerateNonStoryThreads(tx: DBReadTransaction, block: @escaping (TSThread, inout Bool) -> Void) throws {
        var stop = false
        for thread in threads {
            guard !(thread is TSPrivateStoryThread) else {
                continue
            }
            block(thread, &stop)
            if stop {
                return
            }
        }
    }

    public func enumerateGroupThreads(tx: DBReadTransaction, block: @escaping (TSGroupThread, inout Bool) -> Void) throws {
        var stop = false
        for thread in threads {
            guard let groupThread = thread as? TSGroupThread else {
                continue
            }
            block(groupThread, &stop)
            if stop {
                return
            }
        }
    }

    public func insertThreads(_ threads: [TSThread]) {
        threads.forEach { insertThread($0) }
    }

    public func insertThread(_ thread: TSThread) {
        thread.updateRowId(nextRowId)
        threads.append(thread)
        nextRowId += 1
    }

    public func fetchThread(rowId threadRowId: Int64, tx: DBReadTransaction) -> TSThread? {
        threads.first(where: { $0.sqliteRowId == threadRowId })
    }

    public func fetchThread(uniqueId: String, tx: DBReadTransaction) -> TSThread? {
        threads.first(where: { $0.uniqueId == uniqueId })
    }

    public func fetchContactThreads(serviceId: ServiceId, tx: DBReadTransaction) -> [TSContactThread] {
        threads.lazy.compactMap { $0 as? TSContactThread }
            .filter { contactThread in
                guard
                    let contactServiceIdString = contactThread.contactUUID,
                    let contactServiceId = try? ServiceId.parseFrom(serviceIdString: contactServiceIdString)
                else {
                    return false
                }

                return contactServiceId == serviceId
            }
    }

    public func fetchContactThreads(phoneNumber: String, tx: DBReadTransaction) -> [TSContactThread] {
        threads.lazy.compactMap { $0 as? TSContactThread }.filter { $0.contactPhoneNumber == phoneNumber }
    }

    public func fetchGroupThread(groupId: Data, tx: DBReadTransaction) -> TSGroupThread? {
        threads
            .first { $0.groupModelIfGroupThread?.groupId == groupId }
            .map { $0 as! TSGroupThread }
    }

    public func getOrCreateContactThread(with address: SignalServiceAddress, tx: DBWriteTransaction) -> TSContactThread {
        let contactThread = threads
            .lazy
            .compactMap { $0 as? TSContactThread }
            .filter { $0.contactAddress.isEqualToAddress(address) }
            .first
        guard let contactThread else {
            let thread = TSContactThread(contactAddress: address)
            threads.append(thread)
            return thread
        }
        return contactThread
    }

    public func removeThread(_ thread: TSThread, tx: DBWriteTransaction) {
        threads.removeAll(where: { $0.uniqueId == thread.uniqueId })
    }

    public func updateThread(_ thread: TSThread, tx: DBWriteTransaction) {
        let threadIndex = threads.firstIndex(where: { $0.uniqueId == thread.uniqueId })!
        threads[threadIndex] = thread
    }

    public func update(
        groupThread: TSGroupThread,
        withStorySendEnabled storySendEnabled: Bool,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }

    public func fetchOrDefaultAssociatedData(for thread: TSThread, tx: DBReadTransaction) -> ThreadAssociatedData {
        return ThreadAssociatedData(threadUniqueId: thread.uniqueId)
    }

    public func updateAssociatedData(
        threadAssociatedData: ThreadAssociatedData,
        isArchived: Bool?,
        isMarkedUnread: Bool?,
        mutedUntilTimestamp: UInt64?,
        audioPlaybackRate: Float?,
        updateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }

    public func update(
        thread: TSThread,
        withMentionNotificationMode mode: TSThreadMentionNotificationMode,
        wasLocallyInitiated: Bool,
        tx: DBWriteTransaction
    ) {
        // Unimplemented
    }
}

#endif
