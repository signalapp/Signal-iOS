//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

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
        // TODO: [BackupsPerf] just create insert a thread instead of get or create
        return threadStore.getOrCreateContactThread(with: context.recipientContext.localIdentifiers.aciAddress, tx: context.tx)
    }

    func createContactThread(
        with address: MessageBackup.ContactAddress,
        context: MessageBackup.ChatRestoringContext
    ) throws -> TSContactThread {
        // TODO: [BackupsPerf] just create insert a thread instead of get or create
        return threadStore.getOrCreateContactThread(with: address.asInteropAddress(), tx: context.tx)
    }

    func createGroupThread(
        groupModel: TSGroupModelV2,
        isStorySendEnabled: Bool?,
        context: MessageBackup.RestoringContext
    ) throws -> TSGroupThread {
        // TODO: [BackupsPerf] create and insert a thread directly
        let groupThread = threadStore.createGroupThread(groupModel: groupModel, tx: context.tx)
        // TODO: [BackupsPerf] do this in the initial create instead of as an update.
        if let isStorySendEnabled {
            threadStore.update(
                groupThread: groupThread,
                withStorySendEnabled: isStorySendEnabled,
                updateStorageService: false,
                tx: context.tx
            )
        }
        return groupThread
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

        // TODO: [BackupsPerf] update the row in the database directly
        threadStore.update(
            thread: thread.tsThread,
            withMentionNotificationMode: .never,
            // don't issue a storage service update
            wasLocallyInitiated: false,
            tx: context.tx
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
        // TODO: [BackupsPerf] don't attempt to fetch, create, insert, and then update. Just create and insert.
        let threadAssociatedData = threadStore.fetchOrDefaultAssociatedData(for: thread, tx: context.tx)
        threadStore.updateAssociatedData(
            threadAssociatedData: threadAssociatedData,
            isArchived: isArchived,
            isMarkedUnread: isMarkedUnread,
            mutedUntilTimestamp: mutedUntilTimestamp,
            audioPlaybackRate: nil,
            updateStorageService: false,
            tx: context.tx
        )
    }
}
