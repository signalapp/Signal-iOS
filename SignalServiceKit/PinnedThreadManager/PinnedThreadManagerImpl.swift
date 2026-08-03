//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class PinnedThreadManagerImpl: PinnedThreadManager, PinnedThreadMerger {

    private let db: any DB
    private let pinnedThreadStore: PinnedThreadStore
    private let recipientFetcher: RecipientFetcher
    private let recipientStore: RecipientDatabaseTable
    private let storageServiceManager: StorageServiceManager
    private let threadStore: ThreadStore

    init(
        db: any DB,
        pinnedThreadStore: PinnedThreadStore,
        recipientFetcher: RecipientFetcher,
        recipientStore: RecipientDatabaseTable,
        storageServiceManager: StorageServiceManager,
        threadStore: ThreadStore,
    ) {
        self.db = db
        self.pinnedThreadStore = pinnedThreadStore
        self.recipientFetcher = recipientFetcher
        self.recipientStore = recipientStore
        self.storageServiceManager = storageServiceManager
        self.threadStore = threadStore
    }

    public func pinnedThreadOrder(forThread thread: TSThread, tx: DBReadTransaction) -> Int64? {
        guard let threadId = fetchPinnedThreadId(forThread: thread, tx: tx) else {
            return nil
        }
        return pinnedThreadStore.fetchPinnedThreadRecord(forThreadId: threadId, tx: tx)?.id
    }

    private func fetchPinnedThreadId(
        forThread thread: TSThread,
        tx: DBReadTransaction,
    ) -> PinnedThreadId? {
        return _fetchPinnedThreadId(
            forThread: thread,
            fetchOrCreateRecipient: { recipientStore.fetchRecipient(contactThread: $0, tx: tx) },
        )
    }

    private func insertPinnedThreadId(
        forThread thread: TSThread,
        tx: DBWriteTransaction,
    ) -> PinnedThreadId? {
        return _fetchPinnedThreadId(
            forThread: thread,
            fetchOrCreateRecipient: {
                if let aci = $0.contactAddress.serviceId as? Aci {
                    return recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
                }
                if let phoneNumber = E164($0.contactAddress.phoneNumber) {
                    return recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx)
                }
                if let pni = $0.contactAddress.serviceId as? Pni {
                    return recipientFetcher.fetchOrCreate(serviceId: pni, tx: tx)
                }
                return nil
            },
        )
    }

    private func _fetchPinnedThreadId(
        forThread thread: TSThread,
        fetchOrCreateRecipient: (TSContactThread) -> SignalRecipient?,
    ) -> PinnedThreadId? {
        switch thread {
        case let thread as TSContactThread:
            guard let recipient = fetchOrCreateRecipient(thread) else {
                return nil
            }
            return .recipientId(recipient.id)
        case let thread as TSGroupThread:
            return .groupId(thread.groupId)
        case is TSReleaseNotesThread:
            return .releaseNotes
        case is TSPrivateStoryThread:
            // Can't be pinned.
            return nil
        default:
            owsFailDebug("unknown type: \(type(of: thread))")
            return nil
        }
    }

    private func _pinnedThread(
        forThreadId threadId: PinnedThreadId,
        tx: DBReadTransaction,
    ) -> TSThread? {
        switch threadId {
        case .releaseNotes:
            return threadStore.fetchThread(uniqueId: TSReleaseNotesThread.releaseNotesUniqueId, tx: tx)
        case .groupId(let groupId):
            return threadStore.fetchGroupThread(groupId: groupId, tx: tx)
        case .recipientId(let recipientId):
            guard let recipient = recipientStore.fetchRecipient(rowId: recipientId, tx: tx) else {
                owsFailDebug("missing recipient specified via foreign key")
                return nil
            }
            return threadStore.fetchContactThread(recipient: recipient, tx: tx)
        }
    }

    private func _isVisiblePinnedThread(
        _ thread: TSThread,
        tx: DBReadTransaction,
    ) -> Bool {
        let associatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)
        // Ignore deleted or archived pinned threads. These shouldn't exist, but
        // it's possible they are incorrectly received from linked devices.
        return canPin(thread, with: associatedData)
    }

    public func pinnedThreads(tx: DBReadTransaction) -> [TSThread] {
        return pinnedThreadStore.fetchPinnedThreadRecords(tx: tx).compactMap {
            guard let thread = _pinnedThread(forThreadId: $0.threadId, tx: tx) else {
                return nil
            }
            guard _isVisiblePinnedThread(thread, tx: tx) else {
                Logger.warn("Ignoring deleted or archived pinned thread \(thread.uniqueId)")
                return nil
            }
            return thread
        }
    }

    public func setPinnedThreads(
        _ newThreads: [TSThread],
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        setPinnedThreadIds(
            newThreads.compactMap({
                let threadId = fetchPinnedThreadId(forThread: $0, tx: tx)
                owsAssertDebug(threadId != nil, "can't pin un-pinnable thread: \(type(of: $0))")
                return threadId
            }),
            updateStorageService: updateStorageService,
            tx: tx,
        )
    }

    public func setPinnedThreadIds(
        _ threadIds: [PinnedThreadId],
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        var didUpdate = false
        var oldPinnedThreads = pinnedThreadStore.fetchPinnedThreadRecords(tx: tx)[...]
        threadIds.forEach { threadId in
            // Iterate through existing pinned threads, removing any that don't match.
            // (Some of these may appear later in `threadIds`, and if that's the case,
            // we'll remove them and then re-insert them in the right order.)
            while !oldPinnedThreads.isEmpty {
                let oldPinnedThread = oldPinnedThreads.removeFirst()
                if oldPinnedThread.threadId == threadId {
                    // It's already pinned; woo hoo!
                    return /* aka continue threadIds.forEach */
                }
                _unpinThread(oldPinnedThread, tx: tx)
                didUpdate = true
            }
            // If we didn't find a match, we have unpinned everything after the point
            // where this thread should be pinned, and we can now pin this thread.
            _pinThread(threadId: threadId, updateStorageService: updateStorageService, tx: tx)
            didUpdate = true
        }
        // If we matched all the intended threads and there are any pinned threads
        // left over, unpin them.
        for oldPinnedThread in oldPinnedThreads {
            _unpinThread(oldPinnedThread, tx: tx)
            didUpdate = true
        }
        if didUpdate {
            didUpdatePinnedThreads(updateStorageService: updateStorageService, tx: tx)
        }
    }

    public func pinThread(
        _ thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) throws(TooManyPinnedThreadsError) {
        guard let threadId = insertPinnedThreadId(forThread: thread, tx: tx) else {
            owsFailDebug("can't pin thread without threadId: \(type(of: thread))")
            return
        }

        let pinnedThreads = pinnedThreadStore.fetchPinnedThreadRecords(tx: tx)

        if pinnedThreads.contains(where: { $0.threadId == threadId }) {
            return
        }

        if pinnedThreads.count >= PinnedThreads.maxPinnedThreads {
            // When pinning a thread, we want to enforce the limit against the pinned
            // threads that are actually visible as pinned threads (e.g., they exist,
            // they're not archived). Otherwise, there may be a pinned thread that you
            // can't see yet preventing you from pinning a new conversation.
            //
            // However, we also don't want to clear pinned threads unless necessary
            // (e.g., a pinned group that's restoring should remain pinned).
            //
            // So, if there's a visible/invisible pinned thread mismatch, we'll replace
            // on invisible pinned thread with the one currently being pinned.
            let firstMissingThreadIndex = pinnedThreads.firstIndex(where: {
                guard let thread = _pinnedThread(forThreadId: $0.threadId, tx: tx) else {
                    return true
                }
                return !_isVisiblePinnedThread(thread, tx: tx)
            })
            guard let firstMissingThreadIndex else {
                throw TooManyPinnedThreadsError()
            }
            Logger.warn("un-pinning missing thread")
            _unpinThread(pinnedThreads[firstMissingThreadIndex], tx: tx)
        }

        _pinThread(threadId: threadId, updateStorageService: updateStorageService, tx: tx)

        didUpdatePinnedThreads(updateStorageService: updateStorageService, tx: tx)
    }

    private func _pinThread(threadId: PinnedThreadId, updateStorageService: Bool, tx: DBWriteTransaction) {
        _ = PinnedThreadRecord.insertRecord(threadId: threadId, tx: tx)
        didPinThread(threadId: threadId, updateStorageService: updateStorageService, tx: tx)
    }

    private func didPinThread(
        threadId: PinnedThreadId,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        guard let thread = _pinnedThread(forThreadId: threadId, tx: tx) else {
            return
        }

        // Pinning a thread should unarchive it and make it visible if it was not already so.
        let associatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)
        if associatedData.isArchived {
            threadStore.updateAssociatedData(
                associatedData,
                isArchived: false,
                updateStorageService: updateStorageService,
                tx: tx,
            )
        }
        if !thread.shouldThreadBeVisible {
            threadStore.update(thread, withShouldThreadBeVisible: true, tx: tx)
        }

        self.db.touch(thread: thread, shouldReindex: false, shouldUpdateChatListUi: true, tx: tx)
    }

    public func unpinThread(
        _ thread: TSThread,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        guard
            let threadId = fetchPinnedThreadId(forThread: thread, tx: tx),
            let pinnedThread = pinnedThreadStore.fetchPinnedThreadRecord(forThreadId: threadId, tx: tx)
        else {
            return
        }
        _unpinThread(pinnedThread, tx: tx)
        didUpdatePinnedThreads(updateStorageService: updateStorageService, tx: tx)
    }

    private func _unpinThread(_ pinnedThread: PinnedThreadRecord, tx: DBWriteTransaction) {
        failIfThrows {
            try pinnedThread.delete(tx.database)
        }
        didUnpinThread(threadId: pinnedThread.threadId, tx: tx)
    }

    private func didUnpinThread(threadId: PinnedThreadId, tx: DBWriteTransaction) {
        guard let thread = _pinnedThread(forThreadId: threadId, tx: tx) else {
            return
        }

        self.db.touch(thread: thread, shouldReindex: false, shouldUpdateChatListUi: true, tx: tx)
    }

    public func handleUpdatedThread(_ thread: TSThread, tx: DBWriteTransaction) {
        guard
            let threadId = fetchPinnedThreadId(forThread: thread, tx: tx),
            let pinnedThread = pinnedThreadStore.fetchPinnedThreadRecord(forThreadId: threadId, tx: tx)
        else {
            return
        }
        let associatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)
        if canPin(thread, with: associatedData) {
            return
        }
        // If we now can't pin a thread, we should unpin it.
        _unpinThread(pinnedThread, tx: tx)
        didUpdatePinnedThreads(updateStorageService: true, tx: tx)
    }

    private func canPin(_ thread: TSThread, with associatedData: ThreadAssociatedData) -> Bool {
        owsAssertDebug(thread.uniqueId == associatedData.threadUniqueId)
        return thread.shouldThreadBeVisible && !associatedData.isArchived
    }

    private func didUpdatePinnedThreads(updateStorageService: Bool, tx: DBWriteTransaction) {
        if updateStorageService {
            tx.addSyncCompletion { [storageServiceManager] in
                storageServiceManager.recordPendingLocalAccountUpdates()
            }
        }
    }

    func mergeRecipientId(
        _ recipientId: SignalRecipient.RowId,
        into targetRecipientId: SignalRecipient.RowId,
        updateStorageService: Bool,
        tx: DBWriteTransaction,
    ) {
        let pinnedThread = pinnedThreadStore.fetchPinnedThreadRecord(forThreadId: .recipientId(recipientId), tx: tx)
        guard var pinnedThread else {
            // The recipient we're deleting isn't pinned; there's nothing to change.
            return
        }
        let targetPinnedThread = pinnedThreadStore.fetchPinnedThreadRecord(forThreadId: .recipientId(targetRecipientId), tx: tx)
        if targetPinnedThread != nil {
            // The one we're merging into is already pinned; delete the redundant pin.
            _unpinThread(pinnedThread, tx: tx)
        } else {
            // The one we're merging into needs to be pinned; pin it now.
            let threadId = PinnedThreadId.recipientId(targetRecipientId)
            pinnedThread.threadId = threadId
            failIfThrows { try pinnedThread.update(tx.database) }
            didPinThread(threadId: threadId, updateStorageService: updateStorageService, tx: tx)
        }
        didUpdatePinnedThreads(updateStorageService: updateStorageService, tx: tx)
    }
}
