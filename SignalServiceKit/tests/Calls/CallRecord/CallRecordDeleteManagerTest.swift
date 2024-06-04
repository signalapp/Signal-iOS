//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class CallRecordDeleteManagerTest: XCTestCase {
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockOutgoingCallEventSyncMessageManager: MockOutgoingCallEventSyncMessageManager!
    private var mockDB: MockDB!
    private var mockDeletedCallRecordCleanupManager: MockDeletedCallRecordCleanupManager!
    private var mockDeletedCallRecordStore: MockDeletedCallRecordStore!
    private var mockThreadStore: MockThreadStore!

    private var deleteManager: CallRecordDeleteManagerImpl!

    override func setUp() {
        mockDB = MockDB()
        mockCallRecordStore = MockCallRecordStore()
        mockOutgoingCallEventSyncMessageManager = {
            let mock = MockOutgoingCallEventSyncMessageManager()
            mock.expectedCallEvent = .callDeleted
            return mock
        }()
        mockDeletedCallRecordCleanupManager = MockDeletedCallRecordCleanupManager()
        mockDeletedCallRecordStore = MockDeletedCallRecordStore()
        mockThreadStore = MockThreadStore()

        deleteManager = CallRecordDeleteManagerImpl(
            callRecordStore: mockCallRecordStore,
            outgoingCallEventSyncMessageManager: mockOutgoingCallEventSyncMessageManager,
            deletedCallRecordCleanupManager: mockDeletedCallRecordCleanupManager,
            deletedCallRecordStore: mockDeletedCallRecordStore,
            threadStore: mockThreadStore
        )
    }

    private func insertInteraction<I: TSInteraction, T: TSThread>(
        type: I.Type,
        threadType: T.Type
    ) -> (I, T) {
        let thread = threadType.init(uniqueId: UUID().uuidString)
        let interaction = type.init(uniqueId: UUID().uuidString, thread: thread)

        mockDB.write { tx in
            mockThreadStore.insertThread(thread)
            MockInteractionStore().insertInteraction(interaction, tx: tx)
        }

        return (interaction, thread)
    }

    @discardableResult
    private func insertCallRecord(
        interaction: TSInteraction,
        thread: TSThread,
        isGroup: Bool
    ) -> CallRecord {
        return mockDB.write { tx in
            let callRecord = CallRecord(
                callId: .maxRandom,
                interactionRowId: interaction.sqliteRowId!,
                threadRowId: thread.sqliteRowId!,
                callType: isGroup ? .groupCall : .audioCall,
                callDirection: .incoming,
                callStatus: isGroup ? .group(.generic) : .individual(.accepted),
                callBeganTimestamp: .maxRandom
            )

            mockCallRecordStore.insert(callRecord: callRecord, tx: tx)
            return callRecord
        }
    }

    func testDeleteViaAssociatedInteractions() {
        let (individualCallInteraction1, contactThread1) = insertInteraction(type: TSCall.self, threadType: TSContactThread.self)
        let (individualCallInteraction2, contactThread2) = insertInteraction(type: TSCall.self, threadType: TSContactThread.self)
        let (groupCallInteraction1, groupThread1) = insertInteraction(type: OWSGroupCallMessage.self, threadType: TSGroupThread.self)
        let (groupCallInteraction2, groupThread2) = insertInteraction(type: OWSGroupCallMessage.self, threadType: TSGroupThread.self)

        let individualCallRecord1 = insertCallRecord(interaction: individualCallInteraction1, thread: contactThread1, isGroup: false)
        let individualCallRecord2 = insertCallRecord(interaction: individualCallInteraction2, thread: contactThread2, isGroup: false)
        let groupCallRecord1 = insertCallRecord(interaction: groupCallInteraction1, thread: groupThread1, isGroup: true)
        let groupCallRecord2 = insertCallRecord(interaction: groupCallInteraction2, thread: groupThread2, isGroup: true)

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 4)
        XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 0)
        XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 0)
        XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 0)

        mockDB.write { tx in
            deleteManager.deleteCallRecord(
                individualCallRecord1,
                sendSyncMessageOnDelete: false,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 3)
            XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 0)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 1)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 1)

            deleteManager.deleteCallRecord(
                individualCallRecord2,
                sendSyncMessageOnDelete: true,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 2)
            XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 1)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 2)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 2)

            deleteManager.deleteCallRecord(
                groupCallRecord1,
                sendSyncMessageOnDelete: false,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
            XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 1)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 3)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 3)

            deleteManager.deleteCallRecord(
                groupCallRecord2,
                sendSyncMessageOnDelete: true,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 0)
            XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 2)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 4)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 4)
        }
    }

    func testMarkCallAsDeleted() {
        XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 0)
        XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 0)
        XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 0)

        mockDB.write { tx in
            deleteManager.markCallAsDeleted(callId: .maxRandom, threadRowId: .maxRandom, tx: tx)

            XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 0)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 1)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 1)
        }
    }
}
