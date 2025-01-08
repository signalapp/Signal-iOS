//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public final class MessageBackupThreadStore {

    private let threadStore: ThreadStore

    init(threadStore: ThreadStore) {
        self.threadStore = threadStore
    }

    // MARK: - Archiving

    /// Covers contact and group threads.
    /// - Parameter block
    /// A block executed for each enumerated thread. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    func enumerateNonStoryThreads(
        context: MessageBackup.ChatArchivingContext,
        block: (TSThread) throws -> Bool
    ) throws {
        try threadStore.enumerateNonStoryThreads(tx: context.tx, block: block)
    }

    /// Enumerates group threads in "last interaction" order.
    /// - Parameter block
    /// A block executed for each enumerated thread. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    func enumerateGroupThreads(
        context: MessageBackup.ArchivingContext,
        block: (TSGroupThread) throws -> Bool
    ) throws {
        try threadStore.enumerateGroupThreads(tx: context.tx, block: block)
    }

    /// Enumerates story distribution lists
    /// - Parameter block
    /// A block executed for each enumerated thread. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    func enumerateStoryThreads(
        context: MessageBackup.ArchivingContext,
        block: (TSPrivateStoryThread) throws -> Bool
    ) throws {
        try threadStore.enumerateStoryThreads(tx: context.tx, block: block)
    }

    func fetchOrDefaultAssociatedData(
        for thread: TSThread,
        context: MessageBackup.ChatArchivingContext
    ) -> ThreadAssociatedData {
        return threadStore.fetchOrDefaultAssociatedData(for: thread, tx: context.tx)
    }

    func fetchContactThread(
        recipient: SignalRecipient,
        context: MessageBackup.ArchivingContext
    ) -> TSContactThread? {
        return threadStore.fetchContactThread(recipient: recipient, tx: context.tx)
    }

    // MARK: - Restoring

    func createNoteToSelfThread(
        context: MessageBackup.ChatRestoringContext
    ) throws -> TSContactThread {
        let thread = TSContactThread(contactAddress: context.recipientContext.localIdentifiers.aciAddress)
        let record = thread.asRecord()
        try record.insert(context.tx.databaseConnection)
        return thread
    }

    func createContactThread(
        with address: MessageBackup.ContactAddress,
        context: MessageBackup.ChatRestoringContext
    ) throws -> TSContactThread {
        let thread = TSContactThread(contactAddress: address.asInteropAddress())
        let record = thread.asRecord()
        try record.insert(context.tx.databaseConnection)
        return thread
    }

    func createGroupThread(
        groupModel: TSGroupModelV2,
        isStorySendEnabled: Bool?,
        context: MessageBackup.RestoringContext
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
        try record.insert(context.tx.databaseConnection)
        return groupThread
    }

    func insertFullGroupMemberRecords(
        acis: Set<Aci>,
        groupThread: TSGroupThread,
        context: MessageBackup.RestoringContext
    ) throws {
        for aci in acis {
            let groupMember = TSGroupMember(
                address: NormalizedDatabaseRecordAddress(aci: aci),
                groupThreadId: groupThread.uniqueId,
                // This gets updated in post frame restore actions.
                lastInteractionTimestamp: 0
            )
            try groupMember.insert(context.tx.databaseConnection)
        }
    }

    /// We _have_ to do this in a separate step from group thread creation; we create the group
    /// thread when we process the group's Recipient frame, but only have mention state later
    /// when processing the group's Chat frame.
    func update(
        thread: MessageBackup.ChatThread,
        dontNotifyForMentionsIfMuted: Bool,
        context: MessageBackup.ChatRestoringContext
    ) throws {
        guard dontNotifyForMentionsIfMuted else {
            // We only need to set if its not the default (false)
            return
        }

        // Technically, this isn't relevant for contact threads (they can't have mentions
        // in them anyway), but the boolean does exist for them and the backup integration
        // tests have contact threads with muted mentions. So we set for all thread types.

        try context.tx.databaseConnection.execute(
            sql: """
            UPDATE \(TSThread.table.tableName)
            SET
                \(TSThreadSerializer.mentionNotificationModeColumn.columnName) = ?
            WHERE
                \(TSThreadSerializer.idColumn.columnName) = ?;
            """,
            arguments: [TSThreadMentionNotificationMode.never.rawValue, thread.threadRowId]
        )
    }

    func markVisible(
        thread: MessageBackup.ChatThread,
        lastInteractionRowId: Int64?,
        context: MessageBackup.ChatRestoringContext
    ) throws {
        try context.tx.databaseConnection.execute(
            sql: """
            UPDATE \(TSThread.table.tableName)
            SET
                \(TSThreadSerializer.shouldThreadBeVisibleColumn.columnName) = 1,
                \(TSThreadSerializer.lastInteractionRowIdColumn.columnName) = ?
            WHERE
                \(TSThreadSerializer.idColumn.columnName) = ?;
            """,
            arguments: [lastInteractionRowId ?? 0, thread.threadRowId]
        )
    }

    func createAssociatedData(
        for thread: TSThread,
        isArchived: Bool,
        isMarkedUnread: Bool,
        mutedUntilTimestamp: UInt64?,
        context: MessageBackup.ChatRestoringContext
    ) throws {
        let threadAssociatedData = ThreadAssociatedData(
            threadUniqueId: thread.uniqueId,
            isArchived: isArchived,
            isMarkedUnread: isMarkedUnread,
            mutedUntilTimestamp: mutedUntilTimestamp ?? 0,
            audioPlaybackRate: 1
        )
        try threadAssociatedData.insert(context.tx.databaseConnection)
    }
}
