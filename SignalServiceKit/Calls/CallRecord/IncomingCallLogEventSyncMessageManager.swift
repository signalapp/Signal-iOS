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
    private let callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter
    private let deleteAllCallsJobQueue: Shims.DeleteAllCallsJobQueue
    private let missedCallManager: CallRecordMissedCallManager

    private var logger: CallRecordLogger { .shared }

    init(
        callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter,
        deleteAllCallsJobQueue: Shims.DeleteAllCallsJobQueue,
        missedCallManager: CallRecordMissedCallManager
    ) {
        self.callRecordConversationIdAdapter = callRecordConversationIdAdapter
        self.deleteAllCallsJobQueue = deleteAllCallsJobQueue
        self.missedCallManager = missedCallManager
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
            if let callIdentifiers = incomingSyncMessage.anchorCallIdentifiers {
                do {
                    return try callRecordConversationIdAdapter.hydrate(
                        conversationId: callIdentifiers.conversationId,
                        callId: callIdentifiers.callId,
                        tx: tx
                    )
                } catch {
                    owsFailDebug("\(error)")
                }
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
                    sendSyncMessage: false,
                    tx: tx
                )
            case .markedAsReadInConversation:
                missedCallManager.markUnreadCallsInConversationAsRead(
                    beforeCallRecord: referencedCallRecord,
                    sendSyncMessage: false,
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
                    sendSyncMessage: false,
                    tx: tx
                )
            case .markedAsReadInConversation:
                /// This case was added concurrently with the introduction of
                /// call identifiers to the `CallLogEvent` sync message, and so
                /// it's unexpected that we're missing the referenced call
                /// record. We'd only expect this if the call record was deleted
                /// on this device, so if we end up here: do nothing.
                logger.warn("Received markedAsReadInConversation CallLogEvent sync message, but missing referenced call record!")
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
