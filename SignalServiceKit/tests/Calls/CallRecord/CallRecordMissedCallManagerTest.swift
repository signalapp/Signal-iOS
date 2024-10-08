//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class CallRecordMissedCallManagerTest: XCTestCase {
    private var mockConversationIdAdapter: MockConversationIdAdapter!
    private var mockCallRecordQuerier: MockCallRecordQuerier!
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockDB: InMemoryDB!
    private var mockSyncMessageSender: MockSyncMessageSender!

    private var missedCallManager: CallRecordMissedCallManagerImpl!

    override func setUp() {
        mockConversationIdAdapter = MockConversationIdAdapter()
        mockCallRecordQuerier = MockCallRecordQuerier()
        mockCallRecordStore = MockCallRecordStore()
        mockDB = InMemoryDB()
        mockSyncMessageSender = MockSyncMessageSender()

        missedCallManager = CallRecordMissedCallManagerImpl(
            callRecordConversationIdAdapter: mockConversationIdAdapter,
            callRecordQuerier: mockCallRecordQuerier,
            callRecordStore: mockCallRecordStore,
            syncMessageSender: mockSyncMessageSender
        )
    }

    func testCountUnreadCalls() {
        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 0, unreadStatus: .read),
            .fixture(callId: 1, unreadStatus: .unread),
            .fixture(callId: 2, unreadStatus: .read),
            .fixture(callId: 3, unreadStatus: .unread),
            .fixture(callId: 4, unreadStatus: .unread),
        ]

        let unreadCount = mockDB.read { tx -> UInt in
            return missedCallManager.countUnreadMissedCalls(tx: tx)
        }

        XCTAssertEqual(unreadCount, 3)
    }

    func testMarkUnreadCallsAsRead() {
        var hasSentSyncMessage: Bool = false

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 0, unreadStatus: .unread),
            .fixture(callId: 1, unreadStatus: .read),
            .fixture(callId: 2, unreadStatus: .read),
            .fixture(callId: 3, unreadStatus: .unread),
            .fixture(callId: 4, unreadStatus: .unread),
        ]

        var markAsReadCallIds: [UInt64] = []
        mockCallRecordStore.markAsReadMock = { callRecord in
            guard let expected = markAsReadCallIds.popFirst() else {
                XCTFail("Missing expected mark as read call ID!")
                return
            }

            callRecord.unreadStatus = .read
            XCTAssertEqual(callRecord.callId, expected)
        }

        /// Test marking just one call as read, with sync message.
        do {
            defer { XCTAssertTrue(markAsReadCallIds.isEmpty) }
            markAsReadCallIds = [0]

            mockSyncMessageSender.sendSyncMessageMock = { eventType, callId in
                XCTAssertFalse(hasSentSyncMessage)
                hasSentSyncMessage = true
                XCTAssertEqual(eventType, .markedAsRead)
                // We use the first call at or before the given timestamp, read
                // or not, as the call that populates the sync message.
                XCTAssertEqual(callId, 1)
            }

            mockDB.write { tx in
                missedCallManager.markUnreadCallsAsRead(
                    beforeTimestamp: 1,
                    sendSyncMessage: false,
                    tx: tx
                )
            }
        }

        /// Test marking all remaining calls as read, no sync message.
        do {
            defer { XCTAssertTrue(markAsReadCallIds.isEmpty) }
            markAsReadCallIds = [4, 3]

            mockSyncMessageSender.sendSyncMessageMock = { eventType, callId in
                XCTFail("Shouldn't try and send!")
            }

            mockDB.write { tx in
                missedCallManager.markUnreadCallsAsRead(
                    beforeTimestamp: nil,
                    sendSyncMessage: false,
                    tx: tx
                )
            }
        }

        /// Test no sync message if nothing marked as read.
        do {
            mockSyncMessageSender.sendSyncMessageMock = { eventType, callId in
                XCTFail("Shouldn't try and send!")
            }

            mockDB.write { tx in
                missedCallManager.markUnreadCallsAsRead(
                    beforeTimestamp: nil,
                    sendSyncMessage: false,
                    tx: tx
                )
            }
        }
    }

    func testMarkUnreadCallsInConversationAsRead() {
        var hasSentSyncMessage = false

        let anchorCall1: CallRecord = .fixture(callId: 4, threadRowId: 0, unreadStatus: .unread)
        let anchorCall2: CallRecord = .fixture(callId: 8, threadRowId: 0, unreadStatus: .unread)
        let anchorCall3: CallRecord = .fixture(callId: 9, threadRowId: 0, unreadStatus: .read)

        mockCallRecordQuerier.mockCallRecords = [
            .fixture(callId: 0, threadRowId: 1, unreadStatus: .unread),
            .fixture(callId: 1, threadRowId: 1, unreadStatus: .unread),
            .fixture(callId: 2, threadRowId: 0, unreadStatus: .read),
            .fixture(callId: 3, threadRowId: 0, unreadStatus: .unread),
            anchorCall1,
            .fixture(callId: 5, threadRowId: 0, unreadStatus: .unread),
            .fixture(callId: 6, threadRowId: 1, unreadStatus: .unread),
            .fixture(callId: 7, threadRowId: 1, unreadStatus: .unread),
            anchorCall2,
            anchorCall3,
        ]

        var markAsReadCallIds: [UInt64] = []
        mockCallRecordStore.markAsReadMock = { callRecord in
            guard let expected = markAsReadCallIds.popFirst() else {
                XCTFail("Missing expected mark as read call ID!")
                return
            }

            callRecord.unreadStatus = .read
            XCTAssertEqual(callRecord.callId, expected)
        }

        /// Test marking as read with sync message.
        do {
            defer { XCTAssertTrue(markAsReadCallIds.isEmpty) }
            // Descending from the anchor.
            markAsReadCallIds = [4, 3]

            mockSyncMessageSender.sendSyncMessageMock = { eventType, callId in
                XCTAssertFalse(hasSentSyncMessage)
                hasSentSyncMessage = true
                XCTAssertEqual(eventType, .markedAsReadInConversation)
                // We use the given (and thereby newest) call to populate the
                // sync message.
                XCTAssertEqual(callId, 4)
            }

            mockDB.write { tx in
                missedCallManager.markUnreadCallsInConversationAsRead(
                    beforeCallRecord: anchorCall1,
                    sendSyncMessage: true,
                    tx: tx
                )
            }
        }

        /// Test marking as read without sync message.
        do {
            defer { XCTAssertTrue(markAsReadCallIds.isEmpty) }
            markAsReadCallIds = [8, 5]

            mockSyncMessageSender.sendSyncMessageMock = { eventType, callId in
                XCTFail("Shouldn't try and send!")
            }

            mockDB.write { tx in
                missedCallManager.markUnreadCallsInConversationAsRead(
                    beforeCallRecord: anchorCall2,
                    sendSyncMessage: false,
                    tx: tx
                )
            }
        }

        /// Test no sync message if nothing marked as read.
        do {
            mockSyncMessageSender.sendSyncMessageMock = { eventType, callId in
                XCTFail("Shouldn't try and send!")
            }

            mockDB.write { tx in
                missedCallManager.markUnreadCallsInConversationAsRead(
                    beforeCallRecord: anchorCall3,
                    sendSyncMessage: true,
                    tx: tx
                )
            }
        }
    }
}

// MARK: - Mocks

private extension CallRecord {
    static func fixture(
        callId: UInt64,
        threadRowId: Int64? = nil,
        unreadStatus: CallRecord.CallUnreadStatus
    ) -> CallRecord {
        let callStatus: CallRecord.CallStatus = {
            switch unreadStatus {
            case .read:
                return .individual(.accepted)
            case .unread:
                return .individual(.incomingMissed)
            }
        }()

        return CallRecord(
            callId: callId,
            interactionRowId: .maxRandom,
            threadRowId: threadRowId ?? .maxRandom,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: callStatus,
            callBeganTimestamp: callId
        )
    }
}

private class MockConversationIdAdapter: CallRecordSyncMessageConversationIdAdapter {
    func hydrate(conversationId: Data, callId: UInt64, tx: DBReadTransaction) throws -> CallRecord? {
        owsFail("Not implemented!")
    }

    func getConversationId(callRecord: CallRecord, tx: DBReadTransaction) throws -> Data {
        return Aci.randomForTesting().serviceIdBinary.asData
    }
}

private class MockSyncMessageSender: CallRecordMissedCallManagerImpl.Shims.SyncMessageSender {
    var sendSyncMessageMock: ((
        _ eventType: OutgoingCallLogEventSyncMessage.CallLogEvent.EventType,
        _ callId: UInt64
    ) -> Void)!
    func sendCallLogEventSyncMessage(
        eventType: OutgoingCallLogEventSyncMessage.CallLogEvent.EventType,
        callId: UInt64,
        conversationId: Data,
        timestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        sendSyncMessageMock(eventType, callId)
    }
}
