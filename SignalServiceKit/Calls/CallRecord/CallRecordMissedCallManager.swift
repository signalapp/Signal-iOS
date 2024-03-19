//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public protocol CallRecordMissedCallManager {
    /// The number of unread missed calls.
    func countUnreadMissedCalls(tx: DBReadTransaction) -> UInt

    /// Marks all unread calls as read, before the given timestamp.
    ///
    /// - Parameter beforeTimestamp
    /// A timestamp before which to mark calls as read. Calls after this
    /// timestamp will not be marked as read. If this value is `nil`, all calls
    /// are marked as read.
    /// - Parameter sendMarkedAsReadSyncMessage
    /// Whether a "marked as read" sync message should be sent as part of this
    /// operation. No sync message is sent regardless of this value if no calls
    /// are actually marked as read.
    func markUnreadCallsAsRead(
        beforeTimestamp: UInt64?,
        sendMarkedAsReadSyncMessage: Bool,
        tx: DBWriteTransaction
    )
}

class CallRecordMissedCallManagerImpl: CallRecordMissedCallManager {
    private let callRecordQuerier: CallRecordQuerier
    private let callRecordStore: CallRecordStore
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let threadStore: ThreadStore

    init(
        callRecordQuerier: CallRecordQuerier,
        callRecordStore: CallRecordStore,
        messageSenderJobQueue: MessageSenderJobQueue,
        recipientDatabaseTable: RecipientDatabaseTable,
        threadStore: ThreadStore
    ) {
        self.callRecordQuerier = callRecordQuerier
        self.callRecordStore = callRecordStore
        self.messageSenderJobQueue = messageSenderJobQueue
        self.recipientDatabaseTable = recipientDatabaseTable
        self.threadStore = threadStore
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
        sendMarkedAsReadSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        var markedAsReadCount = 0

        let fetchCursorOrdering: CallRecordQuerier.FetchOrdering = {
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
        }()

        for callStatus in CallRecord.CallStatus.allCases {
            guard let unreadCallCursor = callRecordQuerier.fetchCursorForUnread(
                callStatus: callStatus,
                ordering: fetchCursorOrdering,
                tx: tx
            ) else { continue }

            do {
                let markedAsReadCountBefore = markedAsReadCount

                while let unreadCallRecord = try unreadCallCursor.next() {
                    markedAsReadCount += 1

                    callRecordStore.markAsRead(
                        callRecord: unreadCallRecord, tx: tx
                    )
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

        guard markedAsReadCount > 0 else { return }

        CallRecordLogger.shared.info("Marked \(markedAsReadCount) calls as read.")

        if sendMarkedAsReadSyncMessage {
            sendMarkedCallsAsReadSyncMessage(tx: tx)
        }
    }

    /// Send a "marked calls as read" sync message, so our other devices can
    /// clear their missed-call badges.
    ///
    /// The sync message includes a timestamp before which we want to consider
    /// calls read; that timestamp should be of our most-recent call.
    private func sendMarkedCallsAsReadSyncMessage(tx: DBWriteTransaction) {
        let mostRecentCall: CallRecord? = try? callRecordQuerier.fetchCursor(
            ordering: .descending, tx: tx
        )?.next()

        guard let mostRecentCall else {
            owsFailDebug("Unexpectedly failed to get most-recent call after marking calls as read!")
            return
        }

        guard
            let localThread = threadStore.getOrCreateLocalThread(tx: tx),
            let conversationId: OutgoingCallLogEventSyncMessage.CallLogEvent.ConversationId = mostRecentCall
                .conversationId(
                    threadStore: threadStore,
                    recipientDatabaseTable: recipientDatabaseTable,
                    tx: tx
                )
        else { return }

        let sdsTx = SDSDB.shimOnlyBridge(tx)

        let outgoingCallLogEventSyncMessage = OutgoingCallLogEventSyncMessage(
            callLogEvent: OutgoingCallLogEventSyncMessage.CallLogEvent(
                eventType: .markedAsRead,
                callId: mostRecentCall.callId,
                conversationId: conversationId,
                timestamp: mostRecentCall.callBeganTimestamp
            ),
            thread: localThread,
            tx: sdsTx
        )

        messageSenderJobQueue.add(
            message: outgoingCallLogEventSyncMessage.asPreparer,
            transaction: sdsTx
        )
    }
}
