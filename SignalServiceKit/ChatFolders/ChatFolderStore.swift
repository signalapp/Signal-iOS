//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct ChatFolderStore {
    public init() {}

    public static let databaseTableNames: Set<String> = [
        ChatFolderRecord.databaseTableName,
        ChatFolderChatRecord.databaseTableName,
    ]

    // MARK: - Reading folders

    /// Fetches all folders, including ones marked for deletion.
    public func fetchAllRecords(tx: DBReadTransaction) -> [ChatFolderRecord] {
        return failIfThrows {
            try ChatFolderRecord.fetchAll(tx.database)
        }
    }

    /// Fetches and sorts displayable folders. Folders from different devices
    /// can share a position, so ties are broken by their shared ID.
    public func fetchDisplayableRecords(tx: DBReadTransaction) -> [ChatFolderRecord] {
        return failIfThrows {
            try ChatFolderRecord
                .filter(ChatFolderRecord.Columns.deletedAtTimestampMs == 0)
                .order(ChatFolderRecord.Columns.position.asc, ChatFolderRecord.Columns.chatFolderId.asc)
                .fetchAll(tx.database)
        }
    }

    public func fetchRecord(chatFolderId: UUID, tx: DBReadTransaction) -> ChatFolderRecord? {
        return failIfThrows {
            try ChatFolderRecord
                .filter(ChatFolderRecord.Columns.chatFolderId == chatFolderId)
                .fetchOne(tx.database)
        }
    }

    public func fetchRecord(rowId: Int64, tx: DBReadTransaction) -> ChatFolderRecord? {
        return failIfThrows {
            try ChatFolderRecord.fetchOne(tx.database, key: rowId)
        }
    }

    public func fetchRecordForAllChatsFolder(tx: DBReadTransaction) -> ChatFolderRecord? {
        return failIfThrows {
            try ChatFolderRecord
                .filter(ChatFolderRecord.Columns.folderType == ChatFolderRecord.FolderType.all.rawValue)
                .fetchOne(tx.database)
        }
    }

    func fetchRecords(deletedBefore date: Date, tx: DBReadTransaction) -> [ChatFolderRecord] {
        return failIfThrows {
            try ChatFolderRecord
                .filter(ChatFolderRecord.Columns.deletedAtTimestampMs > 0)
                .filter(ChatFolderRecord.Columns.deletedAtTimestampMs < Int64(clamping: date.ows_millisecondsSince1970))
                .fetchAll(tx.database)
        }
    }

    // MARK: - Reading membership

    func fetchMemberships(folderRowId: Int64, tx: DBReadTransaction) -> [ChatFolderChatRecord] {
        return failIfThrows {
            try ChatFolderChatRecord
                .filter(ChatFolderChatRecord.Columns.chatFolderRowId == folderRowId)
                .fetchAll(tx.database)
        }
    }

    // MARK: - Writing folders

    func insertCustomFolderRecord(
        chatFolderId: UUID,
        name: String,
        position: UInt32,
        showOnlyUnread: Bool,
        showMutedChats: Bool,
        includeAllIndividualChats: Bool,
        includeAllGroupChats: Bool,
        deletedAtTimestampMs: Int64,
        tx: DBWriteTransaction,
    ) -> ChatFolderRecord {
        return failIfThrows {
            try ChatFolderRecord.insertRecord(
                chatFolderId: chatFolderId,
                folderType: .custom,
                name: name,
                position: position,
                showOnlyUnread: showOnlyUnread,
                showMutedChats: showMutedChats,
                includeAllIndividualChats: includeAllIndividualChats,
                includeAllGroupChats: includeAllGroupChats,
                deletedAtTimestampMs: deletedAtTimestampMs,
                tx: tx,
            )
        }
    }

    func update(_ record: ChatFolderRecord, tx: DBWriteTransaction) {
        failIfThrows {
            try record.update(tx.database)
        }
    }

    func deleteTombstone(_ record: ChatFolderRecord, tx: DBWriteTransaction) {
        guard record.isDeleted else {
            owsFailDebug("Only deleted folders can be deleted from the database.")
            return
        }
        failIfThrows {
            _ = try record.delete(tx.database)
        }
    }

    func fetchOrInsertAllChatsRecord(tx: DBWriteTransaction) -> ChatFolderRecord {
        if let record = fetchRecordForAllChatsFolder(tx: tx) {
            return record
        }
        return failIfThrows {
            try ChatFolderRecord.insertRecord(
                chatFolderId: UUID(),
                folderType: .all,
                name: "",
                position: 0,
                showOnlyUnread: false,
                showMutedChats: true,
                includeAllIndividualChats: true,
                includeAllGroupChats: true,
                deletedAtTimestampMs: 0,
                tx: tx,
            )
        }
    }

    func setAllChatsChatFolderId(_ chatFolderId: UUID, tx: DBWriteTransaction) {
        failIfThrows {
            try tx.database.execute(
                sql: """
                UPDATE \(ChatFolderRecord.databaseTableName)
                SET \(ChatFolderRecord.Columns.chatFolderId.name) = ?
                WHERE \(ChatFolderRecord.Columns.folderType.name) = ?
                """,
                arguments: [chatFolderId, ChatFolderRecord.FolderType.all.rawValue],
            )
        }
    }

    func markDeleted(
        chatFolderId: UUID,
        deletedAtTimestampMs: Int64,
        tx: DBWriteTransaction,
    ) {
        guard deletedAtTimestampMs > 0 else {
            owsFailDebug("Positive timestamps are used to represent deletion")
            return
        }

        guard var record = fetchRecord(chatFolderId: chatFolderId, tx: tx) else {
            return
        }
        if record.folderType == .all {
            owsFailDebug("Refusing to delete the 'All chats' folder.")
            return
        }

        failIfThrows {
            try ChatFolderChatRecord
                .filter(ChatFolderChatRecord.Columns.chatFolderRowId == record.id)
                .deleteAll(tx.database)
        }

        record.markDeleted(atTimestampMs: deletedAtTimestampMs)
        update(record, tx: tx)
    }

    // MARK: - Writing membership

    func setMembership(
        _ membershipType: ChatFolder.MembershipType,
        chat: ChatFolderChatRecord.Chat,
        folderRowId: Int64,
        tx: DBWriteTransaction,
    ) {
        let record = ChatFolderChatRecord(
            chatFolderRowId: folderRowId,
            chat: chat,
            membershipType: membershipType,
        )
        failIfThrows {
            try record.insert(tx.database)
        }
    }

    func removeMembership(
        chat: ChatFolderChatRecord.Chat,
        folderRowId: Int64,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try ChatFolderChatRecord
                .filter(ChatFolderChatRecord.Columns.chatFolderRowId == folderRowId)
                .filter(ChatFolderChatRecord.Columns.matching(chat))
                .deleteAll(tx.database)
        }
    }

    func replaceMemberships(
        folderRowId: Int64,
        includedChats: Set<ChatFolderChatRecord.Chat>,
        excludedChats: Set<ChatFolderChatRecord.Chat>,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try ChatFolderChatRecord
                .filter(ChatFolderChatRecord.Columns.chatFolderRowId == folderRowId)
                .deleteAll(tx.database)
        }
        // Exclude wins if a chat is in both
        for chat in includedChats.subtracting(excludedChats) {
            setMembership(.included, chat: chat, folderRowId: folderRowId, tx: tx)
        }
        for chat in excludedChats {
            setMembership(.excluded, chat: chat, folderRowId: folderRowId, tx: tx)
        }
    }

    // MARK: - Recipient merging

    /// Folders that reference the recipient, either as include or exclude
    func fetchChatFolderIds(recipientRowId: SignalRecipient.RowId, tx: DBReadTransaction) -> Set<UUID> {
        return failIfThrows {
            let chatFolderRowIds = try ChatFolderChatRecord
                .select(ChatFolderChatRecord.Columns.chatFolderRowId, as: Int64.self)
                .filter(ChatFolderChatRecord.Columns.recipientRowId == recipientRowId)
                .fetchAll(tx.database)
            return Set(try ChatFolderRecord.fetchAll(tx.database, keys: chatFolderRowIds).map(\.chatFolderId))
        }
    }

    func mergeRecipient(
        _ recipientRowId: SignalRecipient.RowId,
        into targetRecipientRowId: SignalRecipient.RowId,
        tx: DBWriteTransaction,
    ) -> Set<UUID> {
        guard recipientRowId != targetRecipientRowId else {
            return []
        }

        let fromMemberships = failIfThrows {
            try ChatFolderChatRecord
                .filter(ChatFolderChatRecord.Columns.recipientRowId == recipientRowId)
                .fetchAll(tx.database)
        }
        guard !fromMemberships.isEmpty else {
            return []
        }

        var affected = Set<UUID>()
        for fromMembership in fromMemberships {
            let folderRowId = fromMembership.chatFolderRowId
            let targetIsMember = failIfThrows {
                try ChatFolderChatRecord
                    .filter(ChatFolderChatRecord.Columns.chatFolderRowId == folderRowId)
                    .filter(ChatFolderChatRecord.Columns.recipientRowId == targetRecipientRowId)
                    .fetchCount(tx.database) > 0
            }
            if !targetIsMember {
                setMembership(
                    fromMembership.membershipType,
                    chat: .contact(recipientRowId: targetRecipientRowId),
                    folderRowId: folderRowId,
                    tx: tx,
                )
            }
            if let record = fetchRecord(rowId: folderRowId, tx: tx) {
                affected.insert(record.chatFolderId)
            }
        }

        failIfThrows {
            try ChatFolderChatRecord
                .filter(ChatFolderChatRecord.Columns.recipientRowId == recipientRowId)
                .deleteAll(tx.database)
        }

        return affected
    }
}
