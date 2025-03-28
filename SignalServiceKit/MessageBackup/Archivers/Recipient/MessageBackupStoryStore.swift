//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public final class MessageBackupStoryStore {

    private let storyStore: StoryStore
    private let storyRecipientStore: StoryRecipientStore

    init(storyStore: StoryStore, storyRecipientStore: StoryRecipientStore) {
        self.storyStore = storyStore
        self.storyRecipientStore = storyRecipientStore
    }

    // MARK: - Archiving

    func getOrCreateStoryContextAssociatedData(
        for aci: Aci,
        context: MessageBackup.RecipientArchivingContext
    ) throws -> StoryContextAssociatedData {
        return storyStore.getOrCreateStoryContextAssociatedData(for: aci, tx: context.tx)
    }

    func getOrCreateStoryContextAssociatedData(
        for groupThread: TSGroupThread,
        context: MessageBackup.RecipientArchivingContext
    ) throws -> StoryContextAssociatedData {
        return storyStore.getOrCreateStoryContextAssociatedData(forGroupThread: groupThread, tx: context.tx)
    }

    func fetchRecipientIds(for storyThread: TSPrivateStoryThread, context: MessageBackup.RecipientArchivingContext) throws -> [SignalRecipient.RowId] {
        return try storyRecipientStore.fetchRecipientIds(forStoryThreadId: storyThread.sqliteRowId!, tx: context.tx)
    }

    // MARK: - Restoring

    func createMyStory(
        name: String,
        allowReplies: Bool,
        viewMode: TSThreadStoryViewMode,
        context: MessageBackup.RecipientRestoringContext
    ) throws -> TSPrivateStoryThread {
        let myStory = TSPrivateStoryThread(
            uniqueId: TSPrivateStoryThread.myStoryUniqueId,
            name: name,
            allowsReplies: allowReplies,
            viewMode: viewMode
        )
        var record = myStory.asRecord()

        let existingMyStoryRowId = try Int64.fetchOne(
            context.tx.database,
            sql: """
                SELECT id from model_TSThread WHERE uniqueId = ?
                """,
            arguments: [TSPrivateStoryThread.myStoryUniqueId]
        )
        if let existingMyStoryRowId {
            record.id = existingMyStoryRowId
        }

        // Use save to insert or update as my story might already exist.
        try record.save(context.tx.database)
        return myStory
    }

    func insertRecipientId(
        _ recipientId: SignalRecipient.RowId,
        forStoryThreadId storyThreadId: TSPrivateStoryThread.RowId,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        try storyRecipientStore.insertRecipientId(recipientId, forStoryThreadId: storyThreadId, tx: context.tx)
    }

    func insert(
        _ storyThread: TSPrivateStoryThread,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        let record = storyThread.asRecord()
        try record.insert(context.tx.database)
    }

    func createStoryContextAssociatedData(
        for aci: Aci,
        isHidden: Bool,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        let storyContext = StoryContextAssociatedData(
            sourceContext: .contact(contactAci: aci),
            isHidden: isHidden
        )
        try storyContext.insert(context.tx.database)
    }

    func createStoryContextAssociatedData(
        for groupThread: TSGroupThread,
        isHidden: Bool,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        let storyContext = StoryContextAssociatedData(
            sourceContext: .group(groupId: groupThread.groupId),
            isHidden: isHidden
        )
        try storyContext.insert(context.tx.database)
    }
}
