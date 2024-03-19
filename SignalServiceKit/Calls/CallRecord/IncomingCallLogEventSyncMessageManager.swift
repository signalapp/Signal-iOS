//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// Handles incoming `CallLogEvent` sync messages.
///
/// - SeeAlso ``IncomingCallLogEventSyncMessageParams``
protocol IncomingCallLogEventSyncMessageManager {
    func handleIncomingSyncMessage(
        incomingSyncMessage: IncomingCallLogEventSyncMessageParams,
        tx: DBWriteTransaction
    )
}

class IncomingCallLogEventSyncMessageManagerImpl: IncomingCallLogEventSyncMessageManager {
    private let callRecordStore: CallRecordStore
    private let deleteAllCallsJobQueue: Shims.DeleteAllCallsJobQueue
    private let missedCallManager: CallRecordMissedCallManager
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    init(
        callRecordStore: CallRecordStore,
        deleteAllCallsJobQueue: Shims.DeleteAllCallsJobQueue,
        missedCallManager: CallRecordMissedCallManager,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.callRecordStore = callRecordStore
        self.deleteAllCallsJobQueue = deleteAllCallsJobQueue
        self.missedCallManager = missedCallManager
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
    }

    func handleIncomingSyncMessage(
        incomingSyncMessage: IncomingCallLogEventSyncMessageParams,
        tx: DBWriteTransaction
    ) {
        /// A `CallLogEvent` sync message contains information identifying a
        /// call whose `callBeganTimestamp` serves as a "reference point" for
        /// the bulk action the sync message describes. If for whatever reason
        /// that call isn't available on this device, we'll fall back to the
        /// timestamp embedded in the sync message.
        let referencedCallRecord: CallRecord? = {
            if
                let callIdentifiers = incomingSyncMessage.anchorCallIdentifiers,
                let referencedCallRecord: CallRecord = .hydrate(
                    callId: callIdentifiers.callId,
                    conversationId: callIdentifiers.conversationId,
                    callRecordStore: callRecordStore,
                    recipientDatabaseTable: recipientDatabaseTable,
                    threadStore: threadStore,
                    tx: tx
                )
            {
                return referencedCallRecord
            }

            return nil
        }()

        if let referencedCallRecord {
            switch incomingSyncMessage.eventType {
            case .cleared:
                deleteAllCallsJobQueue.deleteAllCalls(
                    before: .callRecord(referencedCallRecord),
                    tx: tx
                )
            case .markedAsRead:
                missedCallManager.markUnreadCallsAsRead(
                    beforeTimestamp: referencedCallRecord.callBeganTimestamp,
                    sendMarkedAsReadSyncMessage: false,
                    tx: tx
                )
            }
        } else {
            switch incomingSyncMessage.eventType {
            case .cleared:
                deleteAllCallsJobQueue.deleteAllCalls(
                    before: .timestamp(incomingSyncMessage.anchorTimestamp),
                    tx: tx
                )
            case .markedAsRead:
                missedCallManager.markUnreadCallsAsRead(
                    beforeTimestamp: incomingSyncMessage.anchorTimestamp,
                    sendMarkedAsReadSyncMessage: false,
                    tx: tx
                )
            }
        }
    }
}

// MARK: - Mocks

extension IncomingCallLogEventSyncMessageManagerImpl {
    enum Shims {
        typealias DeleteAllCallsJobQueue = _IncomingCallLogEventSyncMessageManagerImpl_DeleteAllCallsJobQueue_Shim
    }

    enum Wrappers {
        typealias DeleteAllCallsJobQueue = _IncomingCallLogEventSyncMessageManagerImpl_DeleteAllCallsJobQueue_Wrapper
    }
}

protocol _IncomingCallLogEventSyncMessageManagerImpl_DeleteAllCallsJobQueue_Shim {
    func deleteAllCalls(
        before: CallRecordDeleteAllJobQueue.DeleteAllBeforeOptions,
        tx: DBWriteTransaction
    )
}

class _IncomingCallLogEventSyncMessageManagerImpl_DeleteAllCallsJobQueue_Wrapper: _IncomingCallLogEventSyncMessageManagerImpl_DeleteAllCallsJobQueue_Shim {
    private let deleteAllCallsJobQueue: CallRecordDeleteAllJobQueue

    init(_ deleteAllCallsJobQueue: CallRecordDeleteAllJobQueue) {
        self.deleteAllCallsJobQueue = deleteAllCallsJobQueue
    }

    func deleteAllCalls(
        before deleteAllBefore: CallRecordDeleteAllJobQueue.DeleteAllBeforeOptions,
        tx: DBWriteTransaction
    ) {
        deleteAllCallsJobQueue.addJob(
            sendDeleteAllSyncMessage: false,
            deleteAllBefore: deleteAllBefore,
            tx: SDSDB.shimOnlyBridge(tx)
        )
    }
}
