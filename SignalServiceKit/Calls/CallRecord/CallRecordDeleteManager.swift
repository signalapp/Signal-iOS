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
    func deleteCallRecords(
        _ callRecords: [CallRecord],
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
        conversationId: CallRecord.ConversationID,
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

    public func markCallAsDeleted(
        callId: UInt64,
        conversationId: CallRecord.ConversationID,
        tx: DBWriteTransaction
    ) {
        insertDeletedCallRecords(
            deletedCallRecords: [
                DeletedCallRecord(
                    callId: callId,
                    conversationId: conversationId
                )
            ],
            tx: tx
        )
    }

    public func deleteCallRecords(
        _ callRecords: [CallRecord],
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
                let callEventTimestamp: UInt64

                switch callRecord.callType {
                case .audioCall, .videoCall:
                    // [Calls] TODO: pass through the "call event timestamp" for 1:1 call events
                    //
                    // We currently use the timestamp of the call record when sending all
                    // sync messages related to a 1:1 call. That's not quite right – we
                    // should be using the timestamp of the event that triggered the sync
                    // message, such as the user declining.
                    //
                    // This isn't a big deal for 1:1 calls though, since all 1:1 calls have
                    // a well-defined "start time" that both participants know about: the
                    // timestamp of the call offer message. That means no one will in
                    // practice consume this timestamp for 1:1 calls, and we can get away
                    // with it for now.
                    callEventTimestamp = callRecord.callBeganTimestamp
                case .groupCall, .adHocCall:
                    callEventTimestamp = Date().ows_millisecondsSince1970
                }

                outgoingCallEventSyncMessageManager.sendSyncMessage(
                    callRecord: callRecord,
                    callEvent: .callDeleted,
                    callEventTimestamp: callEventTimestamp,
                    tx: tx
                )
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
