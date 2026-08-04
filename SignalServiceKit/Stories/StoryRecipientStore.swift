//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public struct StoryRecipientStore {
    public func insertRecipientId(
        _ recipientId: SignalRecipient.RowId,
        forStoryThreadId storyThreadId: TSPrivateStoryThread.RowId,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            do {
                try StoryRecipient(threadId: storyThreadId, recipientId: recipientId).insert(tx.database)
            } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_PRIMARYKEY {
                // This is fine. It's already there.
            }
        }
    }

    public func removeRecipientId(
        _ recipientId: SignalRecipient.RowId,
        forStoryThreadId storyThreadId: TSPrivateStoryThread.RowId,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try StoryRecipient(threadId: storyThreadId, recipientId: recipientId).delete(tx.database)
        }
    }

    public func removeRecipientIds(
        forStoryThreadId storyThreadId: TSPrivateStoryThread.RowId,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try StoryRecipient.filter(Column(StoryRecipient.CodingKeys.threadId) == storyThreadId).deleteAll(tx.database)
        }
    }

    public func fetchRecipientIds(forStoryThreadId storyThreadId: TSPrivateStoryThread.RowId, tx: DBReadTransaction) -> [SignalRecipient.RowId] {
        return failIfThrows {
            return try StoryRecipient
                .filter(Column(StoryRecipient.CodingKeys.threadId) == storyThreadId)
                .fetchAll(tx.database).map(\.recipientId)
        }
    }

    public func doesStoryThreadId(_ storyThreadId: TSPrivateStoryThread.RowId, containRecipientId recipientId: SignalRecipient.RowId, tx: DBReadTransaction) -> Bool {
        return failIfThrows {
            return try StoryRecipient
                .filter(Column(StoryRecipient.CodingKeys.threadId) == storyThreadId)
                .filter(Column(StoryRecipient.CodingKeys.recipientId) == recipientId)
                .fetchOne(tx.database) != nil
        }
    }

    public func fetchStoryThreadIds(forRecipientId recipientId: SignalRecipient.RowId, tx: DBWriteTransaction) -> [TSPrivateStoryThread.RowId] {
        return failIfThrows {
            return try StoryRecipient
                .filter(Column(StoryRecipient.CodingKeys.recipientId) == recipientId)
                .fetchAll(tx.database)
                .map(\.threadId)
        }
    }

    public func mergeRecipient(_ recipient: SignalRecipient, into targetRecipient: SignalRecipient, tx: DBWriteTransaction) {
        let threadIds = fetchStoryThreadIds(forRecipientId: recipient.id, tx: tx)
        for threadId in threadIds {
            removeRecipientId(recipient.id, forStoryThreadId: threadId, tx: tx)
            insertRecipientId(targetRecipient.id, forStoryThreadId: threadId, tx: tx)
        }
    }
}
