//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import LibSignalClient

@testable import SignalServiceKit

final class GroupCallRecordManagerTest: XCTestCase {
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockInteractionStore: MockInteractionStore!
    private var mockOutgoingSyncMessageManager: MockCallRecordOutgoingSyncMessageManager!
    private var mockTSAccountManager: MockTSAccountManager!

    private var mockDB: MockDB!
    private var groupCallRecordManager: GroupCallRecordManagerImpl!

    override func setUp() {
        mockCallRecordStore = MockCallRecordStore()
        mockInteractionStore = MockInteractionStore()
        mockOutgoingSyncMessageManager = MockCallRecordOutgoingSyncMessageManager()
        mockTSAccountManager = MockTSAccountManager()

        mockDB = MockDB()
        groupCallRecordManager = GroupCallRecordManagerImpl(
            callRecordStore: mockCallRecordStore,
            interactionStore: mockInteractionStore,
            outgoingSyncMessageManager: mockOutgoingSyncMessageManager,
            tsAccountManager: mockTSAccountManager
        )
    }

    private func createInteraction() -> (TSGroupThread, OWSGroupCallMessage) {
        let thread = TSGroupThread.randomForTesting()
        thread.updateRowId(.maxRandom)

        let interaction = OWSGroupCallMessage(
            joinedMemberAcis: [],
            creatorAci: nil,
            thread: thread,
            sentAtTimestamp: .maxRandom
        )
        interaction.updateRowId(.maxRandom)

        return (thread, interaction)
    }

    // MARK: - Create group call record

    func testCreateGroupCallRecord() {
        let (thread1, interaction1) = createInteraction()
        let (thread2, interaction2) = createInteraction()

        _ = mockDB.write { tx in
            groupCallRecordManager.createGroupCallRecord(
                callId: .maxRandom,
                groupCallInteraction: interaction1,
                groupThread: thread1,
                callDirection: .outgoing,
                groupCallStatus: .joined,
                shouldSendSyncMessage: false,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
        XCTAssertFalse(mockOutgoingSyncMessageManager.askedToSendSyncMessage)

        _ = mockDB.write { tx in
            groupCallRecordManager.createGroupCallRecord(
                callId: .maxRandom,
                groupCallInteraction: interaction2,
                groupThread: thread2,
                callDirection: .outgoing,
                groupCallStatus: .joined,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 2)
        XCTAssertTrue(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    func testCreateGroupCallRecordForPeek() {
        let (thread, interaction) = createInteraction()

        _ = mockDB.write { tx in
            groupCallRecordManager.createGroupCallRecordForPeek(
                callId: .maxRandom,
                groupCallInteraction: interaction,
                groupThread: thread,
                tx: tx
            )
        }

        guard let insertedCallRecord = mockCallRecordStore.callRecords.first else {
            XCTFail("Didn't insert model!")
            return
        }

        XCTAssertEqual(insertedCallRecord.callStatus, .group(.generic))
        XCTAssertEqual(insertedCallRecord.callDirection, .incoming)
        XCTAssertEqual(insertedCallRecord.callType, .groupCall)
        XCTAssertFalse(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }
}

// MARK: - Utilities

private extension TSGroupThread {
    static func randomForTesting() -> TSGroupThread {
        return .forUnitTest(groupId: 12)
    }
}
