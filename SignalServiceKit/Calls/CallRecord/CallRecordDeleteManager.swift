//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Responsible for deleting ``CallRecord``s.
///
/// We want to take special steps when a ``CallRecord`` is deleted, beyond
/// simply removing it on-disk. This manager is responsible for performing all
/// the necessary additional tasks related to deleting a ``CallRecord``.
///
/// - SeeAlso ``DeletedCallRecord``
/// - SeeAlso ``DeletedCallRecordCleanupManager``
/// - SeeAlso ``CallRecordStore/delete(callRecords:tx:)``
public protocol CallRecordDeleteManager {
    /// Delete the call record associated with the given interaction.
    /// - Important
    /// Does not delete the given interaction!
    /// - Parameter sendSyncMessageOnDelete
    /// Whether we should send a sync message if we delete a call record.
    func deleteCallRecord(
        associatedIndividualCallInteraction: TSCall,
        sendSyncMessageOnDelete: Bool,
        tx: DBWriteTransaction
    )

    /// Delete the call record associated with the given interaction.
    /// - Important
    /// Does not delete the given interaction!
    /// - Parameter sendSyncMessageOnDelete
    /// Whether we should send a sync message if we delete a call record.
    func deleteCallRecord(
        associatedGroupCallInteraction: OWSGroupCallMessage,
        sendSyncMessageOnDelete: Bool,
        tx: DBWriteTransaction
    )

    /// Delete the given call record, and its associated call interaction.
    /// - Parameter sendSyncMessageOnDelete
    /// Whether we should send a sync message if we delete a call record.
    func deleteCallRecordsAndAssociatedInteractions(
        callRecords: [CallRecord],
        sendSyncMessageOnDelete: Bool,
        tx: DBWriteTransaction
    )

    /// Mark the call with the given identifiers, for which we do not have a
    /// local ``CallRecord``, as deleted.
    /// - Important
    /// This method should only be used if the caller knows a ``CallRecord``
    /// does not exist for the given identifiers.
    /// - Note
    /// Because there is no ``CallRecord``, there is no associated interaction.
    /// - Note
    /// This API never sends a sync message about the delete, as it isn't
    /// actually deleting a call this device knows about.
    func markCallAsDeleted(
        callId: UInt64,
        threadRowId: Int64,
        tx: DBWriteTransaction
    )
}

final class CallRecordDeleteManagerImpl: CallRecordDeleteManager {
    private let callRecordStore: CallRecordStore
    private let callRecordOutgoingSyncMessageManager: CallRecordOutgoingSyncMessageManager
    private let deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager
    private let deletedCallRecordStore: DeletedCallRecordStore
    private let interactionStore: InteractionStore
    private let threadStore: ThreadStore

    init(
        callRecordStore: CallRecordStore,
        callRecordOutgoingSyncMessageManager: CallRecordOutgoingSyncMessageManager,
        deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager,
        deletedCallRecordStore: DeletedCallRecordStore,
        interactionStore: InteractionStore,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.callRecordOutgoingSyncMessageManager = callRecordOutgoingSyncMessageManager
        self.deletedCallRecordCleanupManager = deletedCallRecordCleanupManager
        self.deletedCallRecordStore = deletedCallRecordStore
        self.interactionStore = interactionStore
        self.threadStore = threadStore
    }

    func deleteCallRecord(
        associatedIndividualCallInteraction callInteraction: TSCall,
        sendSyncMessageOnDelete: Bool,
        tx: DBWriteTransaction
    ) {
        guard
            let interactionRowId = callInteraction.sqliteRowId,
            let callRecord = callRecordStore.fetch(
                interactionRowId: interactionRowId, tx: tx
            )
        else { return }

        deleteCallRecords(
            callRecords: [callRecord],
            shouldSendSyncMessage: sendSyncMessageOnDelete,
            tx: tx
        )
    }

    func deleteCallRecord(
        associatedGroupCallInteraction callInteraction: OWSGroupCallMessage,
        sendSyncMessageOnDelete: Bool,
        tx: DBWriteTransaction
    ) {
        guard
            let interactionRowId = callInteraction.sqliteRowId,
            let callRecord = callRecordStore.fetch(
                interactionRowId: interactionRowId, tx: tx
            )
        else { return }

        deleteCallRecords(
            callRecords: [callRecord],
            shouldSendSyncMessage: sendSyncMessageOnDelete,
            tx: tx
        )
    }

    func deleteCallRecordsAndAssociatedInteractions(
        callRecords: [CallRecord],
        sendSyncMessageOnDelete: Bool,
        tx: DBWriteTransaction
    ) {
        /// It's important that we delete the call records *before* we delete
        /// the interactions, as ``TSCall`` and ``OWSGroupCallMessage`` override
        /// hooks in their deletion to delete any associated call records. To
        /// avoid a duplicate delete attempt, we'll ensure there's no call
        /// records to delete by the time we get there.

        deleteCallRecords(
            callRecords: callRecords,
            shouldSendSyncMessage: sendSyncMessageOnDelete,
            tx: tx
        )

        for callRecord in callRecords {
            if let associatedInteraction: TSInteraction = interactionStore
                .fetchAssociatedInteraction(callRecord: callRecord, tx: tx)
            {
                CallRecord.assertDebugIsCallRecordInteraction(associatedInteraction)
                interactionStore.deleteInteraction(associatedInteraction, tx: tx)
            }
        }
    }

    func markCallAsDeleted(
        callId: UInt64,
        threadRowId: Int64,
        tx: DBWriteTransaction
    ) {
        insertDeletedCallRecords(
            deletedCallRecords: [
                DeletedCallRecord(callId: callId, threadRowId: threadRowId)
            ],
            tx: tx
        )
    }

    private func deleteCallRecords(
        callRecords: [CallRecord],
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        callRecordStore.delete(callRecords: callRecords, tx: tx)

        insertDeletedCallRecords(
            deletedCallRecords: callRecords.map(DeletedCallRecord.init(callRecord:)),
            tx: tx
        )

        if shouldSendSyncMessage {
            for callRecord in callRecords {
                guard let thread = threadStore.fetchThread(
                    rowId: callRecord.threadRowId, tx: tx
                ) else {
                    owsFailBeta("Missing thread for call record!")
                    continue
                }

                if let contactThread = thread as? TSContactThread {
                    callRecordOutgoingSyncMessageManager.sendSyncMessage(
                        contactThread: contactThread,
                        callRecord: callRecord,
                        callEvent: .callDeleted,
                        tx: tx
                    )
                } else if let groupThread = thread as? TSGroupThread {
                    callRecordOutgoingSyncMessageManager.sendSyncMessage(
                        groupThread: groupThread,
                        callRecord: callRecord,
                        callEvent: .callDeleted,
                        callEventTimestamp: Date().ows_millisecondsSince1970,
                        tx: tx
                    )
                } else {
                    owsFailBeta("Unexpected thread type! \(type(of: thread))")
                }
            }
        }
    }

    private func insertDeletedCallRecords(
        deletedCallRecords: [DeletedCallRecord],
        tx: DBWriteTransaction
    ) {
        for deletedCallRecord in deletedCallRecords {
            deletedCallRecordStore.insert(deletedCallRecord: deletedCallRecord, tx: tx)
        }

        deletedCallRecordCleanupManager.startCleanupIfNecessary(tx: tx)
    }
}
