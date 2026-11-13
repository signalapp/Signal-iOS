//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A manager that can delete group data.
public protocol GroupDataDeletionManager {
    /// Deletes the group's content on this device from before `preservedInteraction`.
    /// Interactions are deleted asynchronously as there may be a lot of them.
    func deleteGroupData(
        groupThread: TSGroupThread,
        preservedInteraction: TSInteraction,
        tx: DBWriteTransaction,
    )
}

final class GroupDataDeletionManagerImpl: GroupDataDeletionManager {
    private let bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue
    private let notificationPresenter: any NotificationPresenter
    private let storyManager: ThreadDeletionManagerImpl.Shims.StoryManager
    private let threadDeletionManager: any ThreadDeletionManager

    init(
        bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue,
        notificationPresenter: any NotificationPresenter,
        storyManager: ThreadDeletionManagerImpl.Shims.StoryManager,
        threadDeletionManager: any ThreadDeletionManager,
    ) {
        self.bulkDeleteInteractionJobQueue = bulkDeleteInteractionJobQueue
        self.notificationPresenter = notificationPresenter
        self.storyManager = storyManager
        self.threadDeletionManager = threadDeletionManager
    }

    func deleteGroupData(
        groupThread: TSGroupThread,
        preservedInteraction: TSInteraction,
        tx: DBWriteTransaction,
    ) {
        guard
            preservedInteraction.uniqueThreadId == groupThread.uniqueId,
            let preservedInteractionRowId = preservedInteraction.sqliteRowId
        else {
            owsFailDebug("Preserved interaction isn't saved in \(groupThread.logString).")
            return
        }

        Logger.info("Deleting group data in \(groupThread.logString) before interaction \(preservedInteractionRowId).")

        bulkDeleteInteractionJobQueue.addJob(
            anchorMessageRowId: preservedInteractionRowId - 1,
            isFullThreadDelete: false,
            threadUniqueId: groupThread.uniqueId,
            tx: tx,
        )

        storyManager.deleteAllStories(groupId: groupThread.groupId, tx: tx)

        threadDeletionManager.removeDrafts(thread: groupThread, tx: tx)

        notificationPresenter.cancelNotifications(
            threadId: groupThread.uniqueId,
            exceptMessageId: preservedInteraction.uniqueId,
        )
        threadDeletionManager.removeIntents(threadUniqueId: groupThread.uniqueId)
    }
}
