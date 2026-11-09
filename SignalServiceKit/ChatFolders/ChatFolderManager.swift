//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct ChatFolderManager {
    private let chatFolderStore: ChatFolderStore
    private let groupStore = GroupStore()
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let recipientFetcher: RecipientFetcher
    private let storageServiceManager: any StorageServiceManager
    private let threadStore: ThreadStore

    init(
        chatFolderStore: ChatFolderStore,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        storageServiceManager: any StorageServiceManager,
        threadStore: ThreadStore,
    ) {
        self.chatFolderStore = chatFolderStore
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientFetcher = recipientFetcher
        self.storageServiceManager = storageServiceManager
        self.threadStore = threadStore
    }

    // MARK: - Reading

    public func fetch(chatFolderId: UUID, tx: DBReadTransaction) -> ChatFolder? {
        chatFolderStore.fetchRecord(chatFolderId: chatFolderId, tx: tx).map {
            chatFolder(record: $0, tx: tx)
        }
    }

    public func fetchFoldersForDisplay(tx: DBReadTransaction) -> [ChatFolder] {
        chatFolderStore.fetchDisplayableRecords(tx: tx).map {
            chatFolder(record: $0, tx: tx)
        }
    }

    private func chatFolder(record: ChatFolderRecord, tx: DBReadTransaction) -> ChatFolder {
        var included = Set<Int64>()
        var excluded = Set<Int64>()
        for (membership, threadRowId) in resolveThreadRowIds(folderRowId: record.id, tx: tx) {
            // Chats without a local thread can't be shown yet
            guard let threadRowId else {
                continue
            }
            switch membership.membershipType {
            case .included: included.insert(threadRowId)
            case .excluded: excluded.insert(threadRowId)
            }
        }

        return ChatFolder(
            record: record,
            includedThreadRowIds: included,
            excludedThreadRowIds: excluded,
        )
    }

    /// Pairs each of a folder's memberships with its local thread, if any.
    private func resolveThreadRowIds(
        folderRowId: Int64,
        tx: DBReadTransaction,
    ) -> [(membership: ChatFolderChatRecord, threadRowId: Int64?)] {
        let memberships = chatFolderStore.fetchMemberships(folderRowId: folderRowId, tx: tx)
        return memberships.map { membership in
            let threadRowId: Int64? = switch membership.chat {
            case .contact(let recipientRowId):
                recipientDatabaseTable.fetchRecipient(rowId: recipientRowId, tx: tx).flatMap {
                    threadStore.fetchContactThread(recipient: $0, tx: tx)?.sqliteRowId
                }
            case .group(let groupRowId):
                groupStore.fetchGroup(rowId: groupRowId, tx: tx)?.threadId
            }
            return (membership, threadRowId)
        }
    }

    // MARK: - Writing

    func setMembership(
        _ membershipType: ChatFolder.MembershipType,
        thread: TSThread,
        folderRowId: Int64,
        tx: DBWriteTransaction,
    ) {
        let chat = chat(
            forThread: thread,
            recipient: { thread in
                recipientFetcher.fetchOrCreate(contactThread: thread, tx: tx)
            },
            tx: tx,
        )
        guard let chat else {
            return
        }
        chatFolderStore.setMembership(membershipType, chat: chat, folderRowId: folderRowId, tx: tx)
    }

    /// Applies edits to a folder's memberships. Only the given threads are
    /// touched, so memberships for threads not given are not mutated.
    /// A thread in both `included` and `excluded` is stored as excluded.
    func updateMemberships(
        folderRowId: Int64,
        includedThreadRowIds: Set<Int64>,
        excludedThreadRowIds: Set<Int64>,
        removedThreadRowIds: Set<Int64>,
        tx: DBWriteTransaction,
    ) {
        for thread in fetchThreads(rowIds: removedThreadRowIds, tx: tx) {
            let chat = chat(
                forThread: thread,
                recipient: { recipientDatabaseTable.fetchRecipient(contactThread: $0, tx: tx) },
                tx: tx,
            )
            if let chat {
                chatFolderStore.removeMembership(chat: chat, folderRowId: folderRowId, tx: tx)
            }
        }
        for thread in fetchThreads(rowIds: includedThreadRowIds.subtracting(excludedThreadRowIds), tx: tx) {
            setMembership(.included, thread: thread, folderRowId: folderRowId, tx: tx)
        }
        for thread in fetchThreads(rowIds: excludedThreadRowIds, tx: tx) {
            setMembership(.excluded, thread: thread, folderRowId: folderRowId, tx: tx)
        }
    }

    private func fetchThreads(rowIds: Set<Int64>, tx: DBReadTransaction) -> [TSThread] {
        return rowIds.compactMap { rowId in
            guard let thread = threadStore.fetchThread(rowId: rowId, tx: tx) else {
                owsFailDebug("Missing thread for a folder member")
                return nil
            }
            return thread
        }
    }

    private func chat(
        forThread thread: TSThread,
        recipient: (TSContactThread) -> SignalRecipient?,
        tx: DBReadTransaction,
    ) -> ChatFolderChatRecord.Chat? {
        switch thread {
        case let thread as TSContactThread:
            return recipient(thread).map { .contact(recipientRowId: $0.id) }
        case let thread as TSGroupThread:
            return groupStore.fetchGroup(forGroupIdData: thread.groupId, tx: tx).map { .group(groupRowId: $0.rowId) }
        default:
            owsFailDebug("Chat folders don't support \(type(of: thread))")
            return nil
        }
    }

    // MARK: - Recipient merging

    func mergeRecipient(
        _ recipientRowId: SignalRecipient.RowId,
        into targetRecipientRowId: SignalRecipient.RowId,
        tx: DBWriteTransaction,
    ) {
        let mergedIds = chatFolderStore.mergeRecipient(recipientRowId, into: targetRecipientRowId, tx: tx)
        storageServiceManager.recordPendingUpdates(chatFolderIds: mergedIds)
    }

    func recordPendingUpdates(forRecipientRowId recipientRowId: SignalRecipient.RowId, tx: DBReadTransaction) {
        let chatFolderIds = chatFolderStore.fetchChatFolderIds(recipientRowId: recipientRowId, tx: tx)
        storageServiceManager.recordPendingUpdates(chatFolderIds: chatFolderIds)
    }

    // MARK: - App launch

    func createAllChatsFolderIfNeeded(db: DB) {
        guard db.read(block: { chatFolderStore.fetchRecordForAllChatsFolder(tx: $0) }) == nil else {
            return
        }
        let allChats = db.write { tx in
            chatFolderStore.fetchOrInsertAllChatsRecord(tx: tx)
        }
        storageServiceManager.recordPendingUpdates(chatFolderIds: [allChats.chatFolderId])
    }
}
