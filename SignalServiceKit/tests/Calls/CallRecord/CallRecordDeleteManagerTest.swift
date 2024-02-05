//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class CallRecordDeleteManagerTest: XCTestCase {
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockDB: MockDB!
    private var mockDeletedCallRecordCleanupManager: MockDeletedCallRecordCleanupManager!
    private var mockDeletedCallRecordStore: MockDeletedCallRecordStore!
    private var mockInteractionStore: MockInteractionStore!

    private var deleteManager: CallRecordDeleteManagerImpl!

    override func setUp() {
        mockDB = MockDB()
        mockCallRecordStore = MockCallRecordStore()
        mockDeletedCallRecordCleanupManager = MockDeletedCallRecordCleanupManager()
        mockDeletedCallRecordStore = MockDeletedCallRecordStore()
        mockInteractionStore = MockInteractionStore()

        deleteManager = CallRecordDeleteManagerImpl(
            callRecordStore: mockCallRecordStore,
            deletedCallRecordCleanupManager: mockDeletedCallRecordCleanupManager,
            deletedCallRecordStore: mockDeletedCallRecordStore,
            interactionStore: mockInteractionStore
        )
    }

    private func insertInteraction<T: TSInteraction>(type: T.Type) -> T {
        let thread = TSThread(uniqueId: UUID().uuidString)
        let interaction = type.init(uniqueId: UUID().uuidString, thread: thread)

        mockDB.write { tx in
            mockInteractionStore.insertInteraction(interaction, tx: tx)
        }

        return interaction
    }

    @discardableResult
    private func insertCallRecord(
        interaction: TSInteraction,
        isGroup: Bool
    ) -> CallRecord {
        return mockDB.write { tx in
            let callRecord = CallRecord(
                callId: .maxRandom,
                interactionRowId: interaction.sqliteRowId!,
                threadRowId: .maxRandom,
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
        let individualCallInteraction = insertInteraction(type: TSCall.self)
        let groupCallInteraction = insertInteraction(type: OWSGroupCallMessage.self)

        insertCallRecord(interaction: individualCallInteraction, isGroup: false)
        insertCallRecord(interaction: groupCallInteraction, isGroup: true)

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 2)
        XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 0)
        XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 0)
        XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 2)

        mockDB.write { tx in
            deleteManager.deleteCallRecord(
                associatedIndividualCallInteraction: individualCallInteraction,
                tx: tx
            )

            XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 1)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 1)
            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 2)

            deleteManager.deleteCallRecord(
                associatedGroupCallInteraction: groupCallInteraction,
                tx: tx
            )

            XCTAssertEqual(mockCallRecordStore.callRecords.count, 0)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 2)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 2)
            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 2)
        }
    }

    func testDeleteCallRecordsAndAssociatedInteractions() {
        let individualCallRecord = insertCallRecord(
            interaction: insertInteraction(type: TSCall.self),
            isGroup: false
        )

        let groupCallRecord = insertCallRecord(
            interaction: insertInteraction(type: OWSGroupCallMessage.self),
            isGroup: true
        )

        let secondGroupCallRecord = insertCallRecord(
            interaction: insertInteraction(type: OWSGroupCallMessage.self),
            isGroup: true
        )

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 3)
        XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 0)
        XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 0)
        XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 3)

        mockDB.write { tx in
            deleteManager.deleteCallRecordsAndAssociatedInteractions(
                callRecords: [individualCallRecord, groupCallRecord],
                tx: tx
            )

            XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 1)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 2)
            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 1)

            deleteManager.deleteCallRecordsAndAssociatedInteractions(
                callRecords: [secondGroupCallRecord],
                tx: tx
            )

            XCTAssertEqual(mockCallRecordStore.callRecords.count, 0)
            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 2)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 3)
            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 0)
        }
    }

    func testMarkCallAsDeleted() {
        XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 0)
        XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 0)

        mockDB.write { tx in
            deleteManager.markCallAsDeleted(callId: .maxRandom, threadRowId: .maxRandom, tx: tx)

            XCTAssertEqual(mockDeletedCallRecordCleanupManager.cleanupStartCount, 1)
            XCTAssertEqual(mockDeletedCallRecordStore.deletedCallRecords.count, 1)
        }
    }
}
