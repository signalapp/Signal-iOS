//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit

import XCTest

final class IncomingCallLogEventSyncMessageManagerTest: XCTestCase {
    private typealias CallIdentifiers = IncomingCallLogEventSyncMessageParams.CallIdentifiers

    private var mockCallRecordConversationIdAdapter: MockCallRecordSyncMessageConversationIdAdapter!
    private var mockDeleteAllCallsJobQueue: MockDeleteAllCallsJobQueue!
    private var mockMissedCallManager: MockMissedCallManager!

    private var syncMessageManager: IncomingCallLogEventSyncMessageManagerImpl!

    override func setUp() {
        mockCallRecordConversationIdAdapter = MockCallRecordSyncMessageConversationIdAdapter()
        mockDeleteAllCallsJobQueue = MockDeleteAllCallsJobQueue()
        mockMissedCallManager = MockMissedCallManager()

        syncMessageManager = IncomingCallLogEventSyncMessageManagerImpl(
            callRecordConversationIdAdapter: mockCallRecordConversationIdAdapter,
            deleteAllCallsJobQueue: mockDeleteAllCallsJobQueue,
            missedCallManager: mockMissedCallManager
        )
    }

    private func handle(incomingSyncMessage: IncomingCallLogEventSyncMessageParams) {
        InMemoryDB().write { tx in
            syncMessageManager.handleIncomingSyncMessage(
                incomingSyncMessage: incomingSyncMessage, tx: tx
            )
        }
    }

    func testClearingWithFoundAnchor() {
        let callId: UInt64 = .maxRandom
        let timestamp: UInt64 = .maxRandomInt64Compat

        mockCallRecordConversationIdAdapter.mockHydratedCallRecord = .fixture(
            callId: callId,
            threadRowId: .maxRandom,
            callBeganTimestamp: timestamp
        )

        mockDeleteAllCallsJobQueue.deleteAllCallsMock = { beforeTimestamp in
            XCTAssertEqual(beforeTimestamp, timestamp)
        }

        handle(incomingSyncMessage: IncomingCallLogEventSyncMessageParams(
            eventType: .cleared,
            anchorCallIdentifiers: CallIdentifiers(
                callId: callId,
                conversationId: Data()
            ),
            anchorTimestamp: timestamp + 1
        ))
    }

    func testClearingWithMissingAnchor() {
        let timestamp: UInt64 = .maxRandomInt64Compat

        var deleteAttempts = 0
        mockDeleteAllCallsJobQueue.deleteAllCallsMock = { beforeTimestamp in
            deleteAttempts += 1
            XCTAssertEqual(beforeTimestamp, timestamp)
        }

        handle(incomingSyncMessage: IncomingCallLogEventSyncMessageParams(
            eventType: .cleared,
            anchorCallIdentifiers: CallIdentifiers(
                callId: .maxRandom,
                conversationId: Data()
            ),
            anchorTimestamp: timestamp
        ))

        handle(incomingSyncMessage: IncomingCallLogEventSyncMessageParams(
            eventType: .cleared,
            anchorCallIdentifiers: nil,
            anchorTimestamp: timestamp
        ))

        XCTAssertEqual(deleteAttempts, 2)
    }

    func testMarkAsReadWithFoundAnchor() {
        let callId: UInt64 = .maxRandom
        let timestamp: UInt64 = .maxRandomInt64Compat

        mockCallRecordConversationIdAdapter.mockHydratedCallRecord = .fixture(
            callId: callId,
            threadRowId: .maxRandom,
            callBeganTimestamp: timestamp
        )

        mockMissedCallManager.markUnreadCallsAsReadMock = { beforeTimestamp in
            XCTAssertEqual(beforeTimestamp, timestamp)
        }

        handle(incomingSyncMessage: IncomingCallLogEventSyncMessageParams(
            eventType: .markedAsRead,
            anchorCallIdentifiers: CallIdentifiers(
                callId: callId,
                conversationId: Data()
            ),
            anchorTimestamp: timestamp + 1
        ))
    }

    func testMarkAsReadWithMissingAnchor() {
        let timestamp: UInt64 = .maxRandomInt64Compat

        var markAsReadAttempts = 0
        mockMissedCallManager.markUnreadCallsAsReadMock = { beforeTimestamp in
            markAsReadAttempts += 1
            XCTAssertEqual(beforeTimestamp, timestamp)
        }

        handle(incomingSyncMessage: IncomingCallLogEventSyncMessageParams(
            eventType: .markedAsRead,
            anchorCallIdentifiers: CallIdentifiers(
                callId: .maxRandom,
                conversationId: Data()
            ),
            anchorTimestamp: timestamp
        ))

        handle(incomingSyncMessage: IncomingCallLogEventSyncMessageParams(
            eventType: .markedAsRead,
            anchorCallIdentifiers: nil,
            anchorTimestamp: timestamp
        ))

        XCTAssertEqual(markAsReadAttempts, 2)
    }
}

// MARK: - Mocks

private extension CallRecord {
    static func fixture(
        callId: UInt64,
        threadRowId: Int64,
        callBeganTimestamp: UInt64
    ) -> CallRecord {
        return CallRecord(
            callId: callId,
            interactionRowId: 0,
            threadRowId: threadRowId,
            callType: .groupCall,
            callDirection: .incoming,
            callStatus: .group(.generic),
            callBeganTimestamp: callBeganTimestamp
        )
    }
}

private class MockMissedCallManager: CallRecordMissedCallManager {
    func countUnreadMissedCalls(tx: DBReadTransaction) -> UInt {
        owsFail("Not implemented!")
    }

    func markUnreadCallsInConversationAsRead(beforeCallRecord: CallRecord, sendSyncMessage: Bool, tx: DBWriteTransaction) {
        // TODO: implement, because we'll need this when handling incoming sync messages
        owsFail("Not implemented!")
    }

    var markUnreadCallsAsReadMock: ((_ beforeTimestamp: UInt64?) -> Void)!
    func markUnreadCallsAsRead(beforeTimestamp: UInt64?, sendSyncMessage: Bool, tx: DBWriteTransaction) {
        XCTAssertFalse(sendSyncMessage)
        markUnreadCallsAsReadMock(beforeTimestamp)
    }
}

private class MockDeleteAllCallsJobQueue: IncomingCallLogEventSyncMessageManagerImpl.Shims.DeleteAllCallsJobQueue {
    var deleteAllCallsMock: ((_ beforeTimestamp: UInt64) -> Void)!
    func deleteAllCalls(before: CallRecordDeleteAllJobQueue.DeleteAllBeforeOptions, tx: DBWriteTransaction) {
        switch before {
        case .callRecord(let callRecord):
            deleteAllCallsMock(callRecord.callBeganTimestamp)
        case .timestamp(let timestamp):
            deleteAllCallsMock(timestamp)
        }
    }
}
