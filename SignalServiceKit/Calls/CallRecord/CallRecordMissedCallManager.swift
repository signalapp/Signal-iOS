//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit

public protocol CallRecordMissedCallManager {
    /// The number of unread missed calls.
    func countUnreadMissedCalls(tx: DBReadTransaction) -> UInt

    /// Marks all unread calls as read.
    func markUnreadCallsAsRead(tx: DBWriteTransaction)
}

class CallRecordMissedCallManagerImpl: CallRecordMissedCallManager {
    private let callRecordQuerier: CallRecordQuerier
    private let callRecordStore: CallRecordStore

    init(
        callRecordQuerier: CallRecordQuerier,
        callRecordStore: CallRecordStore
    ) {
        self.callRecordQuerier = callRecordQuerier
        self.callRecordStore = callRecordStore
    }

    // MARK: -

    func countUnreadMissedCalls(tx: DBReadTransaction) -> UInt {
        guard FeatureFlags.shouldShowCallsTab else { return 0 }

        return _countUnreadMissedCalls(tx: tx)
    }

    func markUnreadCallsAsRead(tx: DBWriteTransaction) {
        guard FeatureFlags.shouldShowCallsTab else { return }

        _markUnreadCallsAsRead(tx: tx)
    }

    // MARK: -

    private func _countUnreadMissedCalls(tx: DBReadTransaction) -> UInt {
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

    private func _markUnreadCallsAsRead(tx: DBWriteTransaction) {
        for callStatus in CallRecord.CallStatus.allCases {
            guard let unreadCallCursor = callRecordQuerier.fetchCursorForUnread(
                callStatus: callStatus,
                ordering: .descending,
                tx: tx
            ) else { continue }

            do {
                var unreadCallCount = 0

                while let unreadCallRecord = try unreadCallCursor.next() {
                    unreadCallCount += 1

                    callRecordStore.markAsRead(
                        callRecord: unreadCallRecord, tx: tx
                    )
                }

                owsAssertDebug(
                    unreadCallCount == 0 || callStatus.isMissedCall,
                    "Unexpectedly had \(unreadCallCount) unread calls that were not missed!"
                )
            } catch {
                owsFailDebug("Unexpectedly failed to iterate CallRecord cursor!")
                continue
            }
        }
    }
}
