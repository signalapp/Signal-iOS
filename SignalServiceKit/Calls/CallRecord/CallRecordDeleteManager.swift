//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

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
    /// Delete the given call record.
    ///
    /// - Important
    /// Callers must ensure the ``TSInteraction`` associated with the given call
    /// record is also deleted. If you're not sure if that's happening, you may
    /// want ``InteractionDeleteManager/delete(alongsideAssociatedCallRecords:associatedCallDeleteBehavior:tx:)``.
    ///
    /// - Parameter sendSyncMessageOnDelete
    /// Whether we should send an ``OutgoingCallEventSyncMessage`` if we delete
    /// a call record.
    func deleteCallRecord(
        _ callRecord: CallRecord,
        sendSyncMessageOnDelete: Bool,
        tx: DBWriteTransaction
    )

    /// Mark the call with the given identifiers, for which we do not have a
    /// local ``CallRecord``, as deleted.
    ///
    /// - Important
    /// This method should only be used if the caller knows a ``CallRecord``
    /// does not exist for the given identifiers.
    ///
    /// - Note
    /// Because there is no ``CallRecord``, there is no associated interaction.
    ///
    /// - Note
    /// This API never sends an ``OutgoingCallEventSyncMessage`` about the
    /// delete, as it isn't actually deleting a call this device knows about.
    func markCallAsDeleted(
        callId: UInt64,
        threadRowId: Int64,
        tx: DBWriteTransaction
    )
}

// MARK: -

final class CallRecordDeleteManagerImpl: CallRecordDeleteManager {
    private let callRecordStore: CallRecordStore
    private let outgoingCallEventSyncMessageManager: OutgoingCallEventSyncMessageManager
    private let deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager
    private let deletedCallRecordStore: DeletedCallRecordStore
    private let threadStore: ThreadStore

    init(
        callRecordStore: CallRecordStore,
        outgoingCallEventSyncMessageManager: OutgoingCallEventSyncMessageManager,
        deletedCallRecordCleanupManager: DeletedCallRecordCleanupManager,
        deletedCallRecordStore: DeletedCallRecordStore,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.outgoingCallEventSyncMessageManager = outgoingCallEventSyncMessageManager
        self.deletedCallRecordCleanupManager = deletedCallRecordCleanupManager
        self.deletedCallRecordStore = deletedCallRecordStore
        self.threadStore = threadStore
    }

    // MARK: -

    func deleteCallRecord(
        _ callRecord: CallRecord,
        sendSyncMessageOnDelete: Bool,
        tx: DBWriteTransaction
    ) {
        deleteCallRecords(
            callRecords: [callRecord],
            sendSyncMessageOnDelete: sendSyncMessageOnDelete,
            tx: tx
        )
    }

    func markCallAsDeleted(
        callId: UInt64,
        threadRowId: Int64,
        tx: DBWriteTransaction
    ) {
        insertDeletedCallRecords(
            deletedCallRecords: [
                DeletedCallRecord(
                    callId: callId,
                    threadRowId: threadRowId
                )
            ],
            tx: tx
        )
    }

    // MARK: -

    private func deleteCallRecords(
        callRecords: [CallRecord],
        sendSyncMessageOnDelete: Bool,
        tx: DBWriteTransaction
    ) {
        callRecordStore.delete(callRecords: callRecords, tx: tx)

        insertDeletedCallRecords(
            deletedCallRecords: callRecords.map {
                DeletedCallRecord(callRecord: $0)
            },
            tx: tx
        )

        if sendSyncMessageOnDelete {
            for callRecord in callRecords {
                guard let thread = threadStore.fetchThread(
                    rowId: callRecord.threadRowId, tx: tx
                ) else {
                    owsFailBeta("Missing thread for call record!")
                    continue
                }

                if let contactThread = thread as? TSContactThread {
                    outgoingCallEventSyncMessageManager.sendSyncMessage(
                        contactThread: contactThread,
                        callRecord: callRecord,
                        callEvent: .callDeleted,
                        tx: tx
                    )
                } else if let groupThread = thread as? TSGroupThread {
                    outgoingCallEventSyncMessageManager.sendSyncMessage(
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

        deletedCallRecordCleanupManager.startCleanupIfNecessary()
    }
}
