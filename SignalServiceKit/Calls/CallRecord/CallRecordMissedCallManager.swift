//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol CallRecordMissedCallManager {
    /// The number of unread missed calls.
    func countUnreadMissedCalls(tx: DBReadTransaction) -> UInt

    /// Marks all unread calls at and before the given timestamp as read.
    ///
    /// - Parameter beforeTimestamp
    /// A timestamp at and before which to mark calls as read. If this value is
    /// `nil`, all calls are marked as read.
    /// - Parameter sendSyncMessage
    /// Whether a sync message should be sent as part of this operation. No sync
    /// message is sent regardless of this value if no calls are actually marked
    /// as read. The sync message will be of type
    /// ``OutgoingCallLogEventSyncMessage/CallLogEvent/EventType/markedAsRead``.
    func markUnreadCallsAsRead(
        beforeTimestamp: UInt64?,
        sendSyncMessage: Bool,
        tx: DBWriteTransaction
    )

    /// Marks the given call and all unread calls before it in the same
    /// conversation as the given call as read.
    ///
    /// - Parameter beforeCallRecord
    /// The call identifying the conversation and timestamp at and before which
    /// to mark unread calls as read.
    /// - Parameter sendSyncMessage
    /// Whether a sync message should be sent as part of this operation. No sync
    /// message is sent regardless of this value if no calls are actually marked
    /// as read. The sync message will be of type
    /// ``OutgoingCallLogEventSyncMessage/CallLogEvent/EventType/markedAsReadInConversation``.
    func markUnreadCallsInConversationAsRead(
        beforeCallRecord: CallRecord,
        sendSyncMessage: Bool,
        tx: DBWriteTransaction
    )
}

class CallRecordMissedCallManagerImpl: CallRecordMissedCallManager {
    private let callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter
    private let callRecordQuerier: CallRecordQuerier
    private let callRecordStore: CallRecordStore
    private let syncMessageSender: Shims.SyncMessageSender

    private var logger: CallRecordLogger { .shared }

    init(
        callRecordConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter,
        callRecordQuerier: CallRecordQuerier,
        callRecordStore: CallRecordStore,
        syncMessageSender: Shims.SyncMessageSender
    ) {
        self.callRecordConversationIdAdapter = callRecordConversationIdAdapter
        self.callRecordStore = callRecordStore
        self.callRecordQuerier = callRecordQuerier
        self.syncMessageSender = syncMessageSender
    }

    // MARK: -

    func countUnreadMissedCalls(tx: DBReadTransaction) -> UInt {
        var unreadMissedCallCount: UInt = 0

        for missedCallStatus in CallRecord.CallStatus.missedCalls {
            guard let unreadMissedCallCursor = callRecordQuerier.fetchCursorForUnread(
                callStatus: missedCallStatus,
                ordering: .descending,
                tx: tx
            ) else { continue }

            do {
                while let _ = try unreadMissedCallCursor.next() {
                    unreadMissedCallCount += 1
                }
            } catch {
                owsFailDebug("Unexpectedly failed to iterate CallRecord cursor!")
                continue
            }
        }

        return unreadMissedCallCount
    }

    func markUnreadCallsAsRead(
        beforeTimestamp: UInt64?,
        sendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        let fetchOrdering = fetchOrdering(forBeforeTimestamp: beforeTimestamp)

        let markedAsReadCount = _markUnreadCallsAsRead(
            fetchOrdering: fetchOrdering,
            threadRowId: nil,
            tx: tx
        )

        guard markedAsReadCount > 0 else { return }

        logger.info("Marked \(markedAsReadCount) calls as read.")

        if sendSyncMessage {
            /// When doing a bulk mark-as-read, we want to use the newest call
            /// at or before the indicated timestamp (read or not) to populate
            /// the sync message. So, we'll query for a single call, using the
            /// same fetch ordering we used above.
            let mostRecentCall: CallRecord? = try? callRecordQuerier.fetchCursor(
                ordering: fetchOrdering, tx: tx
            )?.next()

            guard let mostRecentCall else {
                owsFailDebug("Unexpectedly failed to get most-recent call after marking calls as read!")
                return
            }

            sendMarkedCallsAsReadSyncMessage(
                callRecord: mostRecentCall,
                eventType: .markedAsRead,
                tx: tx
            )
        }
    }

    func markUnreadCallsInConversationAsRead(
        beforeCallRecord: CallRecord,
        sendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        let threadRowId: Int64
        switch beforeCallRecord.conversationId {
        case .thread(let threadRowId2):
            threadRowId = threadRowId2
        case .callLink(_):
            owsFailDebug("Can't mark call links as read within a conversation.")
            return
        }
        let markedAsReadCount = _markUnreadCallsAsRead(
            fetchOrdering: fetchOrdering(
                forBeforeTimestamp: beforeCallRecord.callBeganTimestamp
            ),
            threadRowId: threadRowId,
            tx: tx
        )

        guard markedAsReadCount > 0 else { return }

        logger.info("Marked \(markedAsReadCount) calls as read.")

        if sendSyncMessage {
            sendMarkedCallsAsReadSyncMessage(
                callRecord: beforeCallRecord,
                eventType: .markedAsReadInConversation,
                tx: tx
            )
        }
    }

    /// Mark calls before or at the given timestamp as read, optionally
    /// considering only calls with the given thread row ID.
    private func _markUnreadCallsAsRead(
        fetchOrdering: CallRecordQuerier.FetchOrdering,
        threadRowId: Int64?,
        tx: DBWriteTransaction
    ) -> UInt {
        var markedAsReadCount: UInt = 0

        for callStatus in CallRecord.CallStatus.allCases {
            let unreadCallCursor: CallRecordCursor? = {
                if let threadRowId {
                    return callRecordQuerier.fetchCursorForUnread(
                        threadRowId: threadRowId,
                        callStatus: callStatus,
                        ordering: fetchOrdering,
                        tx: tx
                    )
                } else {
                    return callRecordQuerier.fetchCursorForUnread(
                        callStatus: callStatus,
                        ordering: fetchOrdering,
                        tx: tx
                    )
                }
            }()

            guard let unreadCallCursor else { continue }

            do {
                let markedAsReadCountBefore = markedAsReadCount

                while let unreadCallRecord = try unreadCallCursor.next() {
                    markedAsReadCount += 1

                    do {
                        try callRecordStore.markAsRead(
                            callRecord: unreadCallRecord, tx: tx
                        )
                    } catch let error {
                        owsFailBeta("Failed to update call record: \(error)")
                    }
                }

                owsAssertDebug(
                    markedAsReadCount == markedAsReadCountBefore || callStatus.isMissedCall,
                    "Unexpectedly had \(markedAsReadCount - markedAsReadCountBefore) unread calls that were not missed!"
                )
            } catch {
                owsFailDebug("Unexpectedly failed to iterate CallRecord cursor!")
                continue
            }
        }

        return markedAsReadCount
    }

    /// Returns a fetch ordering appropriate for querying calls at or before the
    /// given timestamp. If a `nil` timestamp, all calls will be queried.
    private func fetchOrdering(
        forBeforeTimestamp beforeTimestamp: UInt64?
    ) -> CallRecordQuerier.FetchOrdering {
        if let beforeTimestamp {
            /// Adjust the timestamp forward one second to catch calls at
            /// this exact timestamp. That's relevant because when we send
            /// this sync message, we do so with the timestamp of an actual
            /// call – and because we (try to) sync call timestamps across
            /// devices, our copy of the call likely has the exact same
            /// timestamp. Without adjusting, we'll skip that call!
            return .descendingBefore(timestamp: beforeTimestamp + 1)
        }

        return .descending
    }

    /// Send a "marked calls as read" sync message with the given event type, so
    /// our other devices can also mark the calls as read.
    ///
    /// - Parameter callRecord
    /// A call record whose timestamp and other parameters will populate the
    /// sync message.
    /// - Parameter eventType
    /// The type of sync message to send.
    private func sendMarkedCallsAsReadSyncMessage(
        callRecord: CallRecord,
        eventType: OutgoingCallLogEventSyncMessage.CallLogEvent.EventType,
        tx: DBWriteTransaction
    ) {
        let conversationId: Data
        do {
            conversationId = try callRecordConversationIdAdapter.getConversationId(callRecord: callRecord, tx: tx)
        } catch {
            owsFailDebug("\(error)")
            return
        }
        syncMessageSender.sendCallLogEventSyncMessage(
            eventType: eventType,
            callId: callRecord.callId,
            conversationId: conversationId,
            timestamp: callRecord.callBeganTimestamp,
            tx: tx
        )
    }
}

// MARK: - Mocks

extension CallRecordMissedCallManagerImpl {
    enum Shims {
        typealias SyncMessageSender = _CallRecordMissedCallManagerImpl_SyncMessageSender_Shim
    }

    enum Wrappers {
        typealias SyncMessageSender = _CallRecordMissedCallManagerImpl_SyncMessageSender_Wrapper
    }
}

protocol _CallRecordMissedCallManagerImpl_SyncMessageSender_Shim {
    func sendCallLogEventSyncMessage(
        eventType: OutgoingCallLogEventSyncMessage.CallLogEvent.EventType,
        callId: UInt64,
        conversationId: Data,
        timestamp: UInt64,
        tx: DBWriteTransaction
    )
}

class _CallRecordMissedCallManagerImpl_SyncMessageSender_Wrapper: _CallRecordMissedCallManagerImpl_SyncMessageSender_Shim {
    private let messageSenderJobQueue: MessageSenderJobQueue

    init(_ messageSenderJobQueue: MessageSenderJobQueue) {
        self.messageSenderJobQueue = messageSenderJobQueue
    }

    func sendCallLogEventSyncMessage(
        eventType: OutgoingCallLogEventSyncMessage.CallLogEvent.EventType,
        callId: UInt64,
        conversationId: Data,
        timestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let sdsTx = SDSDB.shimOnlyBridge(tx)

        guard let localThread = TSContactThread.getOrCreateLocalThread(transaction: sdsTx) else {
            return
        }

        let outgoingCallLogEventSyncMessage = OutgoingCallLogEventSyncMessage(
            callLogEvent: OutgoingCallLogEventSyncMessage.CallLogEvent(
                eventType: eventType,
                callId: callId,
                conversationId: conversationId,
                timestamp: timestamp
            ),
            thread: localThread,
            tx: sdsTx
        )

        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: outgoingCallLogEventSyncMessage
        )
        messageSenderJobQueue.add(
            message: preparedMessage,
            transaction: sdsTx
        )
    }
}
