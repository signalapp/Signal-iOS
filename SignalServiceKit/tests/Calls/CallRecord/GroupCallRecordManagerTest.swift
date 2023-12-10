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
    private var groupCallRecordManager: SnoopingGroupCallRecordManagerImpl!

    override func setUp() {
        mockCallRecordStore = MockCallRecordStore()
        mockInteractionStore = MockInteractionStore()
        mockOutgoingSyncMessageManager = MockCallRecordOutgoingSyncMessageManager()
        mockTSAccountManager = MockTSAccountManager()

        mockDB = MockDB()
        groupCallRecordManager = SnoopingGroupCallRecordManagerImpl(
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
                callEventTimestamp: .maxRandomInt64Compat,
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
                callEventTimestamp: .maxRandomInt64Compat,
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

    // MARK: - Create or update record

    func testCreateOrUpdate_CallsCreateAndInsertsInteraction() {
        let (thread, _) = createInteraction()

        mockDB.write { tx in
            groupCallRecordManager.createOrUpdateCallRecord(
                callId: .maxRandom,
                groupThread: thread,
                callDirection: .incoming,
                groupCallStatus: .joined,
                callEventTimestamp: .maxRandomInt64Compat,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 1)
        XCTAssertEqual(groupCallRecordManager.didAskToCreateRecordStatus, .joined)
    }

    func testCreateOrUpdate_Updates() {
        let (thread, interaction) = createInteraction()

        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .groupCall,
            callDirection: .incoming,
            callStatus: .group(.generic),
            callBeganTimestamp: .maxRandomInt64Compat
        )
        mockCallRecordStore.callRecords.append(callRecord)

        mockDB.write { tx in
            groupCallRecordManager.createOrUpdateCallRecord(
                callId: callRecord.callId,
                groupThread: thread,
                callDirection: .outgoing,
                groupCallStatus: .ringingAccepted,
                callEventTimestamp: callRecord.callBeganTimestamp + 5,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.askedToUpdateRecordDirectionTo, .outgoing)
        XCTAssertEqual(mockCallRecordStore.askedToUpdateRecordStatusTo, .group(.ringingAccepted))
        XCTAssertTrue(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    func testCreateOrUpdate_UpdateSkipsDirectionAndSyncMessage() {
        let (thread, interaction) = createInteraction()

        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .groupCall,
            callDirection: .incoming,
            callStatus: .group(.generic),
            callBeganTimestamp: .maxRandomInt64Compat
        )
        mockCallRecordStore.callRecords.append(callRecord)

        mockDB.write { tx in
            groupCallRecordManager.createOrUpdateCallRecord(
                callId: callRecord.callId,
                groupThread: thread,
                callDirection: .incoming,
                groupCallStatus: .joined,
                callEventTimestamp: callRecord.callBeganTimestamp + 5,
                shouldSendSyncMessage: false,
                tx: tx
            )
        }

        XCTAssertNil(mockCallRecordStore.askedToUpdateRecordDirectionTo)
        XCTAssertEqual(mockCallRecordStore.askedToUpdateRecordStatusTo, .group(.joined))
        XCTAssertFalse(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    func testCreateOrUpdate_UpdateSkipsSyncMessageIfStatusTransitionDisallowed() {
        let (thread, interaction) = createInteraction()

        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .groupCall,
            callDirection: .incoming,
            callStatus: .group(.generic),
            callBeganTimestamp: .maxRandomInt64Compat
        )
        mockCallRecordStore.callRecords.append(callRecord)
        mockCallRecordStore.shouldAllowStatusUpdate = false

        mockDB.write { tx in
            groupCallRecordManager.createOrUpdateCallRecord(
                callId: callRecord.callId,
                groupThread: thread,
                callDirection: .incoming,
                groupCallStatus: .joined,
                callEventTimestamp: callRecord.callBeganTimestamp + 5,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertNil(mockCallRecordStore.askedToUpdateRecordDirectionTo)
        XCTAssertEqual(mockCallRecordStore.askedToUpdateRecordStatusTo, .group(.joined))
        XCTAssertFalse(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    // MARK: - Update call began timestamp

    func testUpdateCallBeganTimestamp() {
        let (thread, interaction) = createInteraction()

        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .groupCall,
            callDirection: .incoming,
            callStatus: .group(.generic),
            callBeganTimestamp: 12
        )

        mockDB.write { tx in
            groupCallRecordManager.updateCallBeganTimestampIfEarlier(
                existingCallRecord: callRecord,
                callEventTimestamp: 15,
                tx: tx
            )
        }

        XCTAssertNil(mockCallRecordStore.askedToUpdateTimestampTo)

        mockDB.write { tx in
            groupCallRecordManager.updateCallBeganTimestampIfEarlier(
                existingCallRecord: callRecord,
                callEventTimestamp: 9,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.askedToUpdateTimestampTo, 9)
    }
}
// MARK: - SnoopingGroupCallRecordManagerImpl

/// In testing ``GroupCallRecordManagerImpl``'s `createOrUpdate` method, we only
/// really care to test that the `create` method is called correctly. That
/// method's real implementation is tested separately.
///
/// This calss snoops on the `create` method so we can verify it's being called.
private class SnoopingGroupCallRecordManagerImpl: GroupCallRecordManagerImpl {
    var didAskToCreateRecordStatus: CallRecord.CallStatus.GroupCallStatus?

    override func createGroupCallRecord(callId: UInt64, groupCallInteraction: OWSGroupCallMessage, groupThread: TSGroupThread, callDirection: CallRecord.CallDirection, groupCallStatus: CallRecord.CallStatus.GroupCallStatus, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) -> CallRecord? {
        didAskToCreateRecordStatus = groupCallStatus
        return super.createGroupCallRecord(callId: callId, groupCallInteraction: groupCallInteraction, groupThread: groupThread, callDirection: callDirection, groupCallStatus: groupCallStatus, callEventTimestamp: callEventTimestamp, shouldSendSyncMessage: shouldSendSyncMessage, tx: tx)
    }
}

// MARK: - Utilities

private extension TSGroupThread {
    static func randomForTesting() -> TSGroupThread {
        return .forUnitTest(groupId: 12)
    }
}
