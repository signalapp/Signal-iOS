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
protocol CallRecordDeleteManager {
    func deleteCallRecord(
        associatedIndividualCallInteraction: TSCall,
        tx: DBWriteTransaction
    )

    func deleteCallRecord(
        associatedGroupCallInteraction: OWSGroupCallMessage,
        tx: DBWriteTransaction
    )
}

final class CallRecordDeleteManagerImpl: CallRecordDeleteManager {
    private let callRecordStore: CallRecordStore
    private let deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager

    init(
        callRecordStore: CallRecordStore,
        deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager
    ) {
        self.callRecordStore = callRecordStore
        self.deletedCallRecordCleanupManager = deletedCallRecordCleanupManager
    }

    func deleteCallRecord(
        associatedIndividualCallInteraction callInteraction: TSCall,
        tx: DBWriteTransaction
    ) {
        deleteCallRecord(associatedInteraction: callInteraction, tx: tx)
    }

    func deleteCallRecord(
        associatedGroupCallInteraction callInteraction: OWSGroupCallMessage,
        tx: DBWriteTransaction
    ) {
        deleteCallRecord(associatedInteraction: callInteraction, tx: tx)
    }

    private func deleteCallRecord(
        associatedInteraction callInteraction: TSInteraction,
        tx: DBWriteTransaction
    ) {
        if
            let interactionRowId = callInteraction.sqliteRowId,
            let callRecord = callRecordStore.fetch(interactionRowId: interactionRowId, tx: tx)
        {
            callRecordStore.delete(callRecords: [callRecord], tx: tx)
            deletedCallRecordCleanupManager.startCleanupIfNecessary(tx: tx)
        }
    }
}
