//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

/// A request, sent alongside a group change, for members to delete their group data.
public enum GroupDataDeletionRequest: Equatable {
    /// The removed members should delete their group data.
    case membersRemoved(Set<Aci>)
    /// Every member should delete their group data because the group ended.
    case groupTerminated
}

/// A manager that can delete group data.
public protocol GroupDataDeletionManager {
    /// Deletes the group's content on this device from before `preservedInteraction`.
    /// Interactions are deleted asynchronously as there may be a lot of them.
    func deleteGroupData(
        groupThread: TSGroupThread,
        preservedInteraction: TSInteraction,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction,
    )
}

final class GroupDataDeletionManagerImpl: GroupDataDeletionManager {
    private let bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue
    private let threadDeletionManager: any ThreadDeletionManager

    init(
        bulkDeleteInteractionJobQueue: BulkDeleteInteractionJobQueue,
        threadDeletionManager: any ThreadDeletionManager,
    ) {
        self.bulkDeleteInteractionJobQueue = bulkDeleteInteractionJobQueue
        self.threadDeletionManager = threadDeletionManager
    }

    func deleteGroupData(
        groupThread: TSGroupThread,
        preservedInteraction: TSInteraction,
        localIdentifiers: LocalIdentifiers,
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

        threadDeletionManager.removeAssociatedContent(
            thread: groupThread,
            keepingNotificationForMessageId: preservedInteraction.uniqueId,
            localIdentifiers: localIdentifiers,
            tx: tx,
        )
    }
}
