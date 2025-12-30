//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class StoryRecipientManager {
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let storyRecipientStore: StoryRecipientStore
    private let storageServiceManager: any StorageServiceManager
    private let threadStore: any ThreadStore

    init(
        recipientDatabaseTable: RecipientDatabaseTable,
        storyRecipientStore: StoryRecipientStore,
        storageServiceManager: any StorageServiceManager,
        threadStore: any ThreadStore,
    ) {
        self.recipientDatabaseTable = recipientDatabaseTable
        self.storyRecipientStore = storyRecipientStore
        self.storageServiceManager = storageServiceManager
        self.threadStore = threadStore
    }

    public func fetchRecipients(
        forStoryThread storyThread: TSPrivateStoryThread,
        tx: DBReadTransaction,
    ) throws -> [SignalRecipient] {
        let recipientIds = try storyRecipientStore.fetchRecipientIds(forStoryThreadId: storyThread.sqliteRowId!, tx: tx)
        return try recipientIds.map { recipientId in
            guard let recipient = recipientDatabaseTable.fetchRecipient(rowId: recipientId, tx: tx) else {
                throw OWSAssertionError("Couldn't fetch recipient that must exist.")
            }
            return recipient
        }
    }

    public func setRecipientIds(
        _ recipientIds: [SignalRecipient.RowId],
        for storyThread: TSPrivateStoryThread,
        shouldUpdateStorageService: Bool,
        tx: DBWriteTransaction,
    ) throws {
        let storyThreadId = storyThread.sqliteRowId!
        try storyRecipientStore.removeRecipientIds(forStoryThreadId: storyThreadId, tx: tx)
        for recipientId in recipientIds {
            try storyRecipientStore.insertRecipientId(recipientId, forStoryThreadId: storyThreadId, tx: tx)
        }
        if shouldUpdateStorageService {
            updateStorageService(for: [storyThread], tx: tx)
        }
    }

    public func insertRecipientIds(
        _ recipientIds: [SignalRecipient.RowId],
        for storyThread: TSPrivateStoryThread,
        shouldUpdateStorageService: Bool,
        tx: DBWriteTransaction,
    ) throws {
        let storyThreadId = storyThread.sqliteRowId!
        for recipientId in recipientIds {
            try storyRecipientStore.insertRecipientId(recipientId, forStoryThreadId: storyThreadId, tx: tx)
        }
        if shouldUpdateStorageService {
            updateStorageService(for: [storyThread], tx: tx)
        }
    }

    public func removeRecipientIds(
        _ recipientIds: [SignalRecipient.RowId],
        for storyThread: TSPrivateStoryThread,
        shouldUpdateStorageService: Bool,
        tx: DBWriteTransaction,
    ) throws {
        let storyThreadId = storyThread.sqliteRowId!
        for recipientId in recipientIds {
            try storyRecipientStore.removeRecipientId(recipientId, forStoryThreadId: storyThreadId, tx: tx)
        }
        if shouldUpdateStorageService {
            updateStorageService(for: [storyThread], tx: tx)
        }
    }

    private func updateStorageService(for storyThreads: [TSPrivateStoryThread], tx: DBWriteTransaction) {
        let distributionListIds = storyThreads.compactMap(\.distributionListIdentifier)
        tx.addSyncCompletion { [storageServiceManager] in
            storageServiceManager.recordPendingUpdates(updatedStoryDistributionListIds: distributionListIds)
        }
    }

    /// Removes a given address from any TSPrivateStoryThread(s) that involve it
    /// (e.g., custom stories, "My Signal Connections Except..."). Doesn't
    /// remove it from already-deleted custom stories.
    public func removeRecipientIdFromAllPrivateStoryThreads(_ recipientId: SignalRecipient.RowId, shouldUpdateStorageService: Bool, tx: DBWriteTransaction) {
        let threadIds = failIfThrows {
            return try storyRecipientStore.fetchStoryThreadIds(forRecipientId: recipientId, tx: tx)
        }
        var updatedStoryThreads = [TSPrivateStoryThread]()
        for threadId in threadIds {
            guard let storyThread = threadStore.fetchThread(rowId: threadId, tx: tx) as? TSPrivateStoryThread else {
                continue
            }
            switch storyThread.storyViewMode {
            case .default, .disabled:
                continue
            case .explicit, .blockList:
                failIfThrows {
                    try storyRecipientStore.removeRecipientId(recipientId, forStoryThreadId: threadId, tx: tx)
                }
                updatedStoryThreads.append(storyThread)
            }
        }
        if shouldUpdateStorageService {
            updateStorageService(for: updatedStoryThreads, tx: tx)
        }
    }
}
