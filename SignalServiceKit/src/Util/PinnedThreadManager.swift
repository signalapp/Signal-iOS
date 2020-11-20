//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class PinnedThreadManager: NSObject {
    @objc
    static let tooManyPinnedThreadsError = NSError(
        domain: "PinnedThreadManager",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Pinned thread count would exceed maximum pinned threads."]
    )

    @objc
    public static let maxPinnedThreads = 4

    private static let keyValueStore = SDSKeyValueStore(collection: "PinnedConversationManager")
    private static let pinnedThreadIdsKey = "pinnedThreadIds"
    private static let cachedPinnedThreadIds = AtomicArray<String>()

    @objc
    public class func warmCaches() {
        let pinnedThreadIds = SDSDatabaseStorage.shared.read { transaction in
            return keyValueStore.getObject(
                forKey: pinnedThreadIdsKey,
                transaction: transaction
            ) as? [String] ?? []
        }
        cachedPinnedThreadIds.set(pinnedThreadIds)
    }

    @objc
    public class func pinnedThreads(transaction: SDSAnyReadTransaction) -> [TSThread] {
        return pinnedThreadIds.compactMap { threadId in
            guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
//                owsFailDebug("pinned thread record no longer exists \(threadId)")
                return nil
            }
            // Ignore deleted or archived pinned threads. These should exist, but it's
            // possible they are incorrectly received from linked devices.
            guard thread.shouldThreadBeVisible, !thread.isArchived else {
                owsFailDebug("Ignoring deleted or archived pinned thread \(threadId)")
                return nil
            }
            return thread
        }
    }

    @objc
    public class func isThreadPinned(_ thread: TSThread) -> Bool {
        return pinnedThreadIds.contains(thread.uniqueId)
    }

    @objc
    public class var pinnedThreadIds: [String] { cachedPinnedThreadIds.get() }

    @objc
    public class func updatePinnedThreadIds(_ pinnedThreadIds: [String], transaction: SDSAnyWriteTransaction) {
        let previousPinnedThreadIds = self.pinnedThreadIds

        keyValueStore.setObject(pinnedThreadIds, key: pinnedThreadIdsKey, transaction: transaction)
        cachedPinnedThreadIds.set(pinnedThreadIds)

        if previousPinnedThreadIds != pinnedThreadIds {
            let changedThreadIds = Set(previousPinnedThreadIds).symmetricDifference(pinnedThreadIds)

            // Touch any threads whose pin state changed, so we update the UI
            for threadId in changedThreadIds {
                guard let thread = TSThread.anyFetch(uniqueId: threadId, transaction: transaction) else {
                    // In some legitimate cases, we may not yet have a thread for a pinned
                    // thread. For example, if you received a pinned GV2 thread via a storage
                    // sync, but have not yet fetched the GV2 thread. We'll update the UI to
                    // reflect it when the thread is ready.
                    continue
                }

                if pinnedThreadIds.contains(threadId) && (thread.isArchived || !thread.shouldThreadBeVisible) {
                    // Pinning a thread should unarchive it and make it visible if it was not already so.
                    thread.unarchiveThreadAndMarkVisible(updateStorageService: true, transaction: transaction)
                } else {
                    SDSDatabaseStorage.shared.touch(thread: thread, shouldReindex: false, transaction: transaction)
                }
            }
        }
    }

    @objc
    public class func pinThread(
        _ thread: TSThread,
        updateStorageService: Bool,
        transaction: SDSAnyWriteTransaction
    ) throws {
        // When pinning a thread, we want to treat the existing list of pinned
        // threads as only those that actually have current threads. Otherwise,
        // there may be a pinned thread that you can't see preventing you from
        // pinning a new conversation (e.g. a v2 group we haven't created yet)
        var pinnedThreadIds = Self.pinnedThreads(transaction: transaction).map { $0.uniqueId }

        guard !pinnedThreadIds.contains(thread.uniqueId) else {
            throw OWSGenericError("Attempted to pin thread that is already pinned.")
        }

        guard pinnedThreadIds.count < maxPinnedThreads else { throw tooManyPinnedThreadsError }

        pinnedThreadIds.append(thread.uniqueId)
        updatePinnedThreadIds(pinnedThreadIds, transaction: transaction)

        if updateStorageService {
            SSKEnvironment.shared.storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    @objc
    public class func unpinThread(
        _ thread: TSThread,
        updateStorageService: Bool,
        transaction: SDSAnyWriteTransaction
    ) throws {
        var pinnedThreadIds = Self.pinnedThreadIds

        guard let idx = pinnedThreadIds.firstIndex(of: thread.uniqueId) else {
            throw OWSGenericError("Attempted to unpin thread that is not pinned.")
        }

        pinnedThreadIds.remove(at: idx)
        updatePinnedThreadIds(pinnedThreadIds, transaction: transaction)

        if updateStorageService {
            SSKEnvironment.shared.storageServiceManager.recordPendingLocalAccountUpdates()
        }
    }

    @objc
    public class func handleUpdatedThread(_ thread: TSThread, transaction: SDSAnyWriteTransaction) {
        guard pinnedThreadIds.contains(thread.uniqueId) else { return }

        // If we archive or delete a thread, we should unpin it.
        guard !thread.shouldThreadBeVisible || thread.isArchived else { return }

        do {
            try unpinThread(thread, updateStorageService: true, transaction: transaction)
        } catch {
            owsFailDebug("Failed to upin updated thread \(error)")
        }
    }
}
