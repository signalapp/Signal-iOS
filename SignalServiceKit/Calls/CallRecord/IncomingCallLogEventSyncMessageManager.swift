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
        let beforeTimestamp: UInt64 = getEventAnchorTimestamp(
            incomingSyncMessage: incomingSyncMessage, tx: tx
        )

        switch incomingSyncMessage.eventType {
        case .cleared:
            deleteAllCallsJobQueue.deleteAllCalls(
                beforeTimestamp: beforeTimestamp,
                tx: tx
            )
        case .markedAsRead:
            missedCallManager.markUnreadCallsAsRead(
                beforeTimestamp: beforeTimestamp,
                sendMarkedAsReadSyncMessage: false,
                tx: tx
            )
        }
    }

    /// A `CallLogEvent` sync message contains information identifying a call
    /// whose `callBeganTimestamp` serves as a "reference point" for the bulk
    /// action the sync message describes. If for whatever reason that call
    /// isn't available on this device, we'll fall back to the timestamp
    /// embedded in the sync message.
    private func getEventAnchorTimestamp(
        incomingSyncMessage: IncomingCallLogEventSyncMessageParams,
        tx: DBReadTransaction
    ) -> UInt64 {
        if
            let callIdentifiers = incomingSyncMessage.anchorCallIdentifiers,
            let referencedCallRecord = hydrate(
                callIdentifiers: callIdentifiers, tx: tx
            )
        {
            return referencedCallRecord.callBeganTimestamp
        }

        return incomingSyncMessage.anchorTimestamp
    }

    private func hydrate(
        callIdentifiers: IncomingCallLogEventSyncMessageParams.CallIdentifiers,
        tx: DBReadTransaction
    ) -> CallRecord? {
        let threadRowId: Int64? = {
            switch callIdentifiers.conversation {
            case .individual(let serviceId):
                guard
                    let recipient = recipientDatabaseTable.fetchRecipient(
                        serviceId: serviceId, transaction: tx
                    ),
                    let contactThread = threadStore.fetchContactThread(
                        recipient: recipient, tx: tx
                    )
                else { return nil }

                return contactThread.sqliteRowId!
            case .group(let groupId):
                return threadStore.fetchGroupThread(
                    groupId: groupId, tx: tx
                )?.sqliteRowId!
            }
        }()

        guard let threadRowId else { return nil }

        return callRecordStore.fetch(
            callId: callIdentifiers.callId,
            threadRowId: threadRowId,
            tx: tx
        ).unwrapped
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
        beforeTimestamp: UInt64,
        tx: DBWriteTransaction
    )
}

class _IncomingCallLogEventSyncMessageManagerImpl_DeleteAllCallsJobQueue_Wrapper: _IncomingCallLogEventSyncMessageManagerImpl_DeleteAllCallsJobQueue_Shim {
    private let deleteAllCallsJobQueue: CallRecordDeleteAllJobQueue

    init(_ deleteAllCallsJobQueue: CallRecordDeleteAllJobQueue) {
        self.deleteAllCallsJobQueue = deleteAllCallsJobQueue
    }

    func deleteAllCalls(beforeTimestamp: UInt64, tx: DBWriteTransaction) {
        deleteAllCallsJobQueue.addJob(
            sendDeleteAllSyncMessage: false,
            deleteAllBeforeTimestamp: beforeTimestamp,
            tx: SDSDB.shimOnlyBridge(tx)
        )
    }
}
