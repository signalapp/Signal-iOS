//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public final class BackupArchiveThreadStore {

    private let threadStore: ThreadStore

    init(threadStore: ThreadStore) {
        self.threadStore = threadStore
    }

    // MARK: - Archiving

    func enumerateNonStoryThreads(
        tx: DBReadTransaction,
        block: (TSThread) throws -> Bool,
    ) throws {
        try threadStore.enumerateNonStoryThreads(tx: tx, block: block)
    }

    func enumerateGroupThreads(
        tx: DBReadTransaction,
        block: (TSGroupThread) throws -> Bool,
    ) throws {
        try threadStore.enumerateGroupThreads(tx: tx, block: block)
    }

    func enumerateStoryThreads(
        tx: DBReadTransaction,
        block: (TSPrivateStoryThread) throws -> Bool,
    ) throws {
        try threadStore.enumerateStoryThreads(tx: tx, block: block)
    }

    func fetchOrDefaultAssociatedData(
        for thread: TSThread,
        tx: DBReadTransaction,
    ) -> ThreadAssociatedData {
        return threadStore.fetchOrDefaultAssociatedData(for: thread, tx: tx)
    }

    func fetchContactThread(
        recipient: SignalRecipient,
        tx: DBReadTransaction,
    ) -> TSContactThread? {
        return threadStore.fetchContactThread(recipient: recipient, tx: tx)
    }

    // MARK: - Restoring

    func createNoteToSelfThread(
        context: BackupArchive.ChatRestoringContext,
    ) throws -> TSContactThread {
        let thread = TSContactThread(contactAddress: context.recipientContext.localIdentifiers.aciAddress)
        let record = thread.asRecord()
        try record.insert(context.tx.database)
        return thread
    }

    func createContactThread(
        with address: BackupArchive.ContactAddress,
        context: BackupArchive.ChatRestoringContext,
    ) throws -> TSContactThread {
        let thread = TSContactThread(contactAddress: address.asInteropAddress())
        let record = thread.asRecord()
        try record.insert(context.tx.database)
        return thread
    }

    func createGroupThread(
        groupModel: TSGroupModelV2,
        isStorySendEnabled: Bool?,
        context: BackupArchive.RestoringContext,
    ) throws -> TSGroupThread {
        let groupThread = TSGroupThread(groupModel: groupModel)
        switch isStorySendEnabled {
        case true:
            groupThread.storyViewMode = .explicit
        case false:
            groupThread.storyViewMode = .disabled
        default:
            groupThread.storyViewMode = .default
        }
        let record = groupThread.asRecord()
        try record.insert(context.tx.database)
        return groupThread
    }

    func insertFullGroupMemberRecords(
        acis: Set<Aci>,
        groupThread: TSGroupThread,
        context: BackupArchive.RestoringContext,
    ) throws {
        for aci in acis {
            let groupMember = TSGroupMember(
                address: NormalizedDatabaseRecordAddress(aci: aci),
                groupThreadId: groupThread.uniqueId,
                // This gets updated in post frame restore actions.
                lastInteractionTimestamp: 0,
            )
            try groupMember.insert(context.tx.database)
        }
    }

    /// We _have_ to do this in a separate step from group thread creation; we create the group
    /// thread when we process the group's Recipient frame, but only have mention state later
    /// when processing the group's Chat frame.
    func update(
        thread: BackupArchive.ChatThread,
        dontNotifyForMentionsIfMuted: Bool,
        context: BackupArchive.ChatRestoringContext,
    ) throws {
        guard dontNotifyForMentionsIfMuted else {
            // We only need to set if its not the default (false)
            return
        }

        // Technically, this isn't relevant for contact threads (they can't have mentions
        // in them anyway), but the boolean does exist for them and the backup integration
        // tests have contact threads with muted mentions. So we set for all thread types.

        try context.tx.database.execute(
            sql: """
            UPDATE \(TSThread.table.tableName)
            SET
                \(TSThreadSerializer.mentionNotificationModeColumn.columnName) = ?
            WHERE
                \(TSThreadSerializer.idColumn.columnName) = ?;
            """,
            arguments: [TSThreadMentionNotificationMode.never.rawValue, thread.threadRowId],
        )
    }

    func markVisible(
        thread: BackupArchive.ChatThread,
        lastInteractionRowId: Int64?,
        context: BackupArchive.ChatRestoringContext,
    ) throws {
        try context.tx.database.execute(
            sql: """
            UPDATE \(TSThread.table.tableName)
            SET
                \(TSThreadSerializer.shouldThreadBeVisibleColumn.columnName) = 1,
                \(TSThreadSerializer.lastInteractionRowIdColumn.columnName) = ?
            WHERE
                \(TSThreadSerializer.idColumn.columnName) = ?;
            """,
            arguments: [lastInteractionRowId ?? 0, thread.threadRowId],
        )
    }

    func createAssociatedData(
        for thread: TSThread,
        isArchived: Bool,
        isMarkedUnread: Bool,
        mutedUntilTimestamp: UInt64?,
        context: BackupArchive.ChatRestoringContext,
    ) throws {
        let threadAssociatedData = ThreadAssociatedData(
            threadUniqueId: thread.uniqueId,
            isArchived: isArchived,
            isMarkedUnread: isMarkedUnread,
            mutedUntilTimestamp: mutedUntilTimestamp ?? 0,
            audioPlaybackRate: 1,
        )
        try threadAssociatedData.insert(context.tx.database)
    }
}
