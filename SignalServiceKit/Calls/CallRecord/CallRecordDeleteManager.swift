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
    func deleteCallRecord(
        associatedIndividualCallInteraction: TSCall,
        tx: DBWriteTransaction
    )

    /// Delete the call record associated with the given interaction.
    /// - Important
    /// Does not delete the given interaction!
    func deleteCallRecord(
        associatedGroupCallInteraction: OWSGroupCallMessage,
        tx: DBWriteTransaction
    )

    /// Delete the given call record, and its associated call interaction.
    func deleteCallRecordsAndAssociatedInteractions(
        callRecords: [CallRecord],
        tx: DBWriteTransaction
    )

    /// Mark the call with the given identifiers, for which we do not have a
    /// local ``CallRecord``, as deleted.
    /// - Note
    /// Because there is no ``CallRecord``, there is no associated interaction.
    /// - Important
    /// This method should only be used if the caller knows a ``CallRecord``
    /// does not exist for the given identifiers.
    func markCallAsDeleted(
        callId: UInt64,
        threadRowId: Int64,
        tx: DBWriteTransaction
    )
}

final class CallRecordDeleteManagerImpl: CallRecordDeleteManager {
    private let callRecordStore: CallRecordStore
    private let deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager
    private let deletedCallRecordStore: DeletedCallRecordStore
    private let interactionStore: InteractionStore

    init(
        callRecordStore: CallRecordStore,
        deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager,
        deletedCallRecordStore: DeletedCallRecordStore,
        interactionStore: InteractionStore
    ) {
        self.callRecordStore = callRecordStore
        self.deletedCallRecordCleanupManager = deletedCallRecordCleanupManager
        self.deletedCallRecordStore = deletedCallRecordStore
        self.interactionStore = interactionStore
    }

    func deleteCallRecord(
        associatedIndividualCallInteraction callInteraction: TSCall,
        tx: DBWriteTransaction
    ) {
        guard
            let interactionRowId = callInteraction.sqliteRowId,
            let callRecord = callRecordStore.fetch(
                interactionRowId: interactionRowId, tx: tx
            )
        else { return }

        deleteCallRecords(callRecords: [callRecord], tx: tx)
    }

    func deleteCallRecord(
        associatedGroupCallInteraction callInteraction: OWSGroupCallMessage,
        tx: DBWriteTransaction
    ) {
        guard
            let interactionRowId = callInteraction.sqliteRowId,
            let callRecord = callRecordStore.fetch(
                interactionRowId: interactionRowId, tx: tx
            )
        else { return }

        deleteCallRecords(callRecords: [callRecord], tx: tx)
    }

    func deleteCallRecordsAndAssociatedInteractions(
        callRecords: [CallRecord],
        tx: DBWriteTransaction
    ) {
        deleteCallRecords(callRecords: callRecords, tx: tx)

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
        tx: DBWriteTransaction
    ) {
        callRecordStore.delete(callRecords: callRecords, tx: tx)

        insertDeletedCallRecords(
            deletedCallRecords: callRecords.map(DeletedCallRecord.init(callRecord:)),
            tx: tx
        )
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
