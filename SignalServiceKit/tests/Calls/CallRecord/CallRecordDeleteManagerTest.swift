//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class CallRecordDeleteManagerTest: XCTestCase {
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockOutgoingCallEventSyncMessageManager: MockOutgoingCallEventSyncMessageManager!
    private var mockDB: InMemoryDB!
    private var mockDeletedCallRecordCleanupManager: MockDeletedCallRecordCleanupManager!
    private var mockDeletedCallRecordStore: MockDeletedCallRecordStore!
    private var mockThreadStore: MockThreadStore!

    private var deleteManager: CallRecordDeleteManagerImpl!

    override func setUp() {
        mockDB = InMemoryDB()
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

    private func insertIndividualCallInteraction() -> (TSCall, TSContactThread) {
        let thread = TSContactThread(contactUUID: UUID().uuidString, contactPhoneNumber: nil)
        let interaction = TSCall(callType: .outgoing, offerType: .audio, thread: thread, sentAtTimestamp: 0)

        mockDB.write { tx in
            mockThreadStore.insertThread(thread)
            MockInteractionStore().insertInteraction(interaction, tx: tx)
        }

        return (interaction, thread)
    }

    private func insertGroupCallInteraction() -> (OWSGroupCallMessage, TSGroupThread) {
        let thread = TSGroupThread(groupModel: try! TSGroupModelBuilder().buildAsV2())
        let interaction = OWSGroupCallMessage(joinedMemberAcis: [], creatorAci: nil, thread: thread, sentAtTimestamp: 0)

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
        let (individualCallInteraction1, contactThread1) = insertIndividualCallInteraction()
        let (individualCallInteraction2, contactThread2) = insertIndividualCallInteraction()
        let (groupCallInteraction1, groupThread1) = insertGroupCallInteraction()
        let (groupCallInteraction2, groupThread2) = insertGroupCallInteraction()

        let individualCallRecord1 = insertCallRecord(interaction: individualCallInteraction1, thread: contactThread1, isGroup: false)
        let individualCallRecord2 = insertCallRecord(interaction: individualCallInteraction2, thread: contactThread2, isGroup: false)
        let groupCallRecord1 = insertCallRecord(interaction: groupCallInteraction1, thread: groupThread1, isGroup: true)
        let groupCallRecord2 = insertCallRecord(interaction: groupCallInteraction2, thread: groupThread2, isGroup: true)

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 4)
        XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 0)
        XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 0)
        XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 0)

        mockDB.write { tx in
            deleteManager.deleteCallRecords(
                [individualCallRecord1],
                sendSyncMessageOnDelete: false,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 3)
            XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 0)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 1)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 1)

            deleteManager.deleteCallRecords(
                [individualCallRecord2],
                sendSyncMessageOnDelete: true,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 2)
            XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 1)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 2)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 2)

            deleteManager.deleteCallRecords(
                [groupCallRecord1],
                sendSyncMessageOnDelete: false,
                tx: tx
            )
            XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
            XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 1)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 3)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 3)

            deleteManager.deleteCallRecords(
                [groupCallRecord2],
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
            deleteManager.markCallAsDeleted(callId: .maxRandom, conversationId: .thread(threadRowId: .maxRandom), tx: tx)

            XCTAssertEqual(mockOutgoingCallEventSyncMessageManager.syncMessageSendCount, 0)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 1)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 1)
        }
    }
}
