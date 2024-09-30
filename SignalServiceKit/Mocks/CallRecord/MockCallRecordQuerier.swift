//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#if TESTABLE_BUILD

public class MockCallRecordQuerier: CallRecordQuerier {
    private class Cursor: CallRecordCursor {
        private var callRecords: [CallRecord] = []
        init(_ callRecords: [CallRecord]) { self.callRecords = callRecords }
        func next() throws -> CallRecord? { return callRecords.popFirst() }
    }

    public var mockCallRecords: [CallRecord]

    public init() {
        self.mockCallRecords = []
    }

    private func applyOrdering(_ mockCallRecords: [CallRecord], ordering: FetchOrdering) -> [CallRecord] {
        switch ordering {
        case .descending:
            return mockCallRecords.sorted { $0.callBeganTimestamp > $1.callBeganTimestamp }
        case .descendingBefore(let timestamp):
            return mockCallRecords.filter { $0.callBeganTimestamp < timestamp }.sorted { $0.callBeganTimestamp > $1.callBeganTimestamp }
        case .ascendingAfter(let timestamp):
            return mockCallRecords.filter { $0.callBeganTimestamp > timestamp }.sorted { $0.callBeganTimestamp < $1.callBeganTimestamp }
        }
    }

    public func fetchCursor(ordering: FetchOrdering, tx: DBReadTransaction) -> CallRecordCursor? {
        return Cursor(applyOrdering(mockCallRecords, ordering: ordering))
    }

    public func fetchCursor(callStatus: CallRecord.CallStatus, ordering: FetchOrdering, tx: DBReadTransaction) -> CallRecordCursor? {
        return Cursor(applyOrdering(mockCallRecords.filter { $0.callStatus == callStatus }, ordering: ordering))
    }

    public func fetchCursor(threadRowId: Int64, ordering: FetchOrdering, tx: DBReadTransaction) -> CallRecordCursor? {
        return Cursor(applyOrdering(mockCallRecords.filter { $0.conversationId == .thread(threadRowId: threadRowId) }, ordering: ordering))
    }

    public func fetchCursor(threadRowId: Int64, callStatus: CallRecord.CallStatus, ordering: FetchOrdering, tx: DBReadTransaction) -> CallRecordCursor? {
        return Cursor(applyOrdering(mockCallRecords.filter { $0.callStatus == callStatus && $0.conversationId == .thread(threadRowId: threadRowId) }, ordering: ordering))
    }

    public func fetchCursorForUnread(callStatus: CallRecord.CallStatus, ordering: FetchOrdering, tx: DBReadTransaction) -> CallRecordCursor? {
        return Cursor(applyOrdering(mockCallRecords.filter { $0.callStatus == callStatus && $0.unreadStatus == .unread }, ordering: ordering))
    }

    public func fetchCursorForUnread(threadRowId: Int64, callStatus: CallRecord.CallStatus, ordering: FetchOrdering, tx: DBReadTransaction) -> CallRecordCursor? {
        return Cursor(applyOrdering(mockCallRecords.filter { $0.conversationId == .thread(threadRowId: threadRowId) && $0.callStatus == callStatus && $0.unreadStatus == .unread }, ordering: ordering))
    }
}

#endif
