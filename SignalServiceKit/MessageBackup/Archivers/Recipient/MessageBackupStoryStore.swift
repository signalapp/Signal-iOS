//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public final class MessageBackupStoryStore {

    private let storyStore: StoryStore

    init(storyStore: StoryStore) {
        self.storyStore = storyStore
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

    // MARK: - Restoring

    func createMyStory(
        name: String,
        allowReplies: Bool,
        viewMode: TSThreadStoryViewMode,
        addresses: [MessageBackup.ContactAddress],
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        let myStory = TSPrivateStoryThread(
            uniqueId: TSPrivateStoryThread.myStoryUniqueId,
            name: name,
            allowsReplies: allowReplies,
            addresses: addresses.map({ $0.asInteropAddress() }),
            viewMode: viewMode
        )
        var record = myStory.asRecord()

        let existingMyStoryRowId = try Int64.fetchOne(
            context.tx.databaseConnection,
            sql: """
                SELECT id from model_TSThread WHERE uniqueId = ?
                """,
            arguments: [TSPrivateStoryThread.myStoryUniqueId]
        )
        if let existingMyStoryRowId {
            record.id = existingMyStoryRowId
        }

        // Use save to insert or update as my story might already exist.
        try record.save(context.tx.databaseConnection)
    }

    func insert(
        _ storyThread: TSPrivateStoryThread,
        context: MessageBackup.RecipientRestoringContext
    ) throws {
        let record = storyThread.asRecord()
        try record.insert(context.tx.databaseConnection)
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
        try storyContext.insert(context.tx.databaseConnection)
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
        try storyContext.insert(context.tx.databaseConnection)
    }
}
