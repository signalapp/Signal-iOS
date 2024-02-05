//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class CallRecordDeleteManagerTest: XCTestCase {
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockCallRecordOutgoingSyncMessageManager: MockCallRecordOutgoingSyncMessageManager!
    private var mockDB: MockDB!
    private var mockDeletedCallRecordCleanupManager: MockDeletedCallRecordCleanupManager!
    private var mockDeletedCallRecordStore: MockDeletedCallRecordStore!
    private var mockInteractionStore: MockInteractionStore!
    private var mockThreadStore: MockThreadStore!

    private var deleteManager: CallRecordDeleteManagerImpl!

    override func setUp() {
        mockDB = MockDB()
        mockCallRecordStore = MockCallRecordStore()
        mockCallRecordOutgoingSyncMessageManager = {
            let mock = MockCallRecordOutgoingSyncMessageManager()
            mock.expectedCallEvent = .callDeleted
            return mock
        }()
        mockDeletedCallRecordCleanupManager = MockDeletedCallRecordCleanupManager()
        mockDeletedCallRecordStore = MockDeletedCallRecordStore()
        mockInteractionStore = MockInteractionStore()
        mockThreadStore = MockThreadStore()

        deleteManager = CallRecordDeleteManagerImpl(
            callRecordStore: mockCallRecordStore,
            callRecordOutgoingSyncMessageManager: mockCallRecordOutgoingSyncMessageManager,
            deletedCallRecordCleanupManager: mockDeletedCallRecordCleanupManager,
            deletedCallRecordStore: mockDeletedCallRecordStore,
            interactionStore: mockInteractionStore,
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
            mockInteractionStore.insertInteraction(interaction, tx: tx)
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

        insertCallRecord(interaction: individualCallInteraction1, thread: contactThread1, isGroup: false)
        insertCallRecord(interaction: individualCallInteraction2, thread: contactThread2, isGroup: false)
        insertCallRecord(interaction: groupCallInteraction1, thread: groupThread1, isGroup: true)
        insertCallRecord(interaction: groupCallInteraction2, thread: groupThread2, isGroup: true)

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 4)
        XCTAssertEqual(mockCallRecordOutgoingSyncMessageManager.syncMessageSendCount, 0)
        XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 0)
        XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 0)
        XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 4)

        mockDB.write { tx in
            deleteManager.deleteCallRecord(
                associatedIndividualCallInteraction: individualCallInteraction1,
                sendSyncMessageOnDelete: false,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 3)
            XCTAssertEqual(mockCallRecordOutgoingSyncMessageManager.syncMessageSendCount, 0)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 1)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 1)
            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 4)

            deleteManager.deleteCallRecord(
                associatedIndividualCallInteraction: individualCallInteraction2,
                sendSyncMessageOnDelete: true,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 2)
            XCTAssertEqual(mockCallRecordOutgoingSyncMessageManager.syncMessageSendCount, 1)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 2)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 2)
            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 4)

            deleteManager.deleteCallRecord(
                associatedGroupCallInteraction: groupCallInteraction1,
                sendSyncMessageOnDelete: false,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
            XCTAssertEqual(mockCallRecordOutgoingSyncMessageManager.syncMessageSendCount, 1)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 3)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 3)
            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 4)

            deleteManager.deleteCallRecord(
                associatedGroupCallInteraction: groupCallInteraction2,
                sendSyncMessageOnDelete: true,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 0)
            XCTAssertEqual(mockCallRecordOutgoingSyncMessageManager.syncMessageSendCount, 2)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 4)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 4)
            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 4)
        }
    }

    func testDeleteCallRecordsAndAssociatedInteractions() {
        let (individualCallInteraction, contactThread) = insertInteraction(type: TSCall.self, threadType: TSContactThread.self)
        let individualCallRecord = insertCallRecord(
            interaction: individualCallInteraction,
            thread: contactThread,
            isGroup: false
        )

        let (groupCallInteraction1, groupThread1) = insertInteraction(type: OWSGroupCallMessage.self, threadType: TSGroupThread.self)
        let groupCallRecord1 = insertCallRecord(
            interaction: groupCallInteraction1,
            thread: groupThread1,
            isGroup: true
        )

        let (groupCallInteraction2, groupThread2) = insertInteraction(type: OWSGroupCallMessage.self, threadType: TSGroupThread.self)
        let groupCallRecord2 = insertCallRecord(
            interaction: groupCallInteraction2,
            thread: groupThread2,
            isGroup: true
        )

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 3)
        XCTAssertEqual(mockCallRecordOutgoingSyncMessageManager.syncMessageSendCount, 0)
        XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 0)
        XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 0)
        XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 3)

        mockDB.write { tx in
            deleteManager.deleteCallRecordsAndAssociatedInteractions(
                callRecords: [individualCallRecord, groupCallRecord1],
                sendSyncMessageOnDelete: true,
                tx: tx
            )

            XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
            XCTAssertEqual(mockCallRecordOutgoingSyncMessageManager.syncMessageSendCount, 2)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 1)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 2)
            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 1)

            deleteManager.deleteCallRecordsAndAssociatedInteractions(
                callRecords: [groupCallRecord2],
                sendSyncMessageOnDelete: false,
                tx: tx
            )

            XCTAssertEqual(mockCallRecordStore.callRecords.count, 0)
            XCTAssertEqual(mockCallRecordOutgoingSyncMessageManager.syncMessageSendCount, 2)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 2)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 3)
            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 0)
        }
    }

    func testMarkCallAsDeleted() {
        XCTAssertEqual(mockCallRecordOutgoingSyncMessageManager.syncMessageSendCount, 0)
        XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 0)
        XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 0)

        mockDB.write { tx in
            deleteManager.markCallAsDeleted(callId: .maxRandom, threadRowId: .maxRandom, tx: tx)

            XCTAssertEqual(mockCallRecordOutgoingSyncMessageManager.syncMessageSendCount, 0)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 1)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 1)
        }
    }
}
