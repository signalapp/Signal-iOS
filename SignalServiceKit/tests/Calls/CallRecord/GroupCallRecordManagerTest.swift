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
    private var snoopingGroupCallRecordManager: SnoopingGroupCallRecordManagerImpl!
    private var groupCallRecordManager: GroupCallRecordManagerImpl!

    override func setUp() {
        mockCallRecordStore = MockCallRecordStore()
        mockInteractionStore = MockInteractionStore()
        mockOutgoingSyncMessageManager = MockCallRecordOutgoingSyncMessageManager()
        mockTSAccountManager = MockTSAccountManager()

        mockDB = MockDB()
        snoopingGroupCallRecordManager = SnoopingGroupCallRecordManagerImpl(
            callRecordStore: mockCallRecordStore,
            interactionStore: mockInteractionStore,
            outgoingSyncMessageManager: mockOutgoingSyncMessageManager,
            tsAccountManager: mockTSAccountManager
        )
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

    // MARK: - Create or update record

    func testCreateOrUpdate_CallsCreateAndInsertsInteraction() {
        let (thread, _) = createInteraction()

        mockDB.write { tx in
            snoopingGroupCallRecordManager.createOrUpdateCallRecord(
                callId: .maxRandom,
                groupThread: thread,
                groupThreadRowId: thread.sqliteRowId!,
                callDirection: .incoming,
                groupCallStatus: .joined,
                callEventTimestamp: .maxRandomInt64Compat,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 1)
        XCTAssertTrue(snoopingGroupCallRecordManager.didAskToCreate)
    }

    func testCreateOrUpdate_CallsUpdate() {
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
            snoopingGroupCallRecordManager.createOrUpdateCallRecord(
                callId: callRecord.callId,
                groupThread: thread,
                groupThreadRowId: thread.sqliteRowId!,
                callDirection: .incoming,
                groupCallStatus: .joined,
                callEventTimestamp: .maxRandomInt64Compat,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertTrue(snoopingGroupCallRecordManager.didAskToUpdate)
    }

    // MARK: - Create group call record

    func testCreateGroupCallRecord() {
        let (thread1, interaction1) = createInteraction()
        let (thread2, interaction2) = createInteraction()

        _ = mockDB.write { tx in
            groupCallRecordManager.createGroupCallRecord(
                callId: .maxRandom,
                groupCallInteraction: interaction1,
                groupCallInteractionRowId: interaction1.sqliteRowId!,
                groupThread: thread1,
                groupThreadRowId: thread1.sqliteRowId!,
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
                groupCallInteractionRowId: interaction2.sqliteRowId!,
                groupThread: thread2,
                groupThreadRowId: thread2.sqliteRowId!,
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
                groupCallInteractionRowId: interaction.sqliteRowId!,
                groupThread: thread,
                groupThreadRowId: thread.sqliteRowId!,
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

    // MARK: Update record

    func testUpdate_Updates() {
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
                groupThreadRowId: thread.sqliteRowId!,
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

    func testUpdate_SkipsDirectionAndSyncMessage() {
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
                groupThreadRowId: thread.sqliteRowId!,
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

    func testUpdate_SkipsSyncMessageIfStatusTransitionDisallowed() {
        let (thread, interaction) = createInteraction()

        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .groupCall,
            callDirection: .incoming,
            callStatus: .group(.joined),
            callBeganTimestamp: .maxRandomInt64Compat
        )
        mockCallRecordStore.callRecords.append(callRecord)
        mockCallRecordStore.shouldAllowStatusUpdate = false

        mockDB.write { tx in
            groupCallRecordManager.createOrUpdateCallRecord(
                callId: callRecord.callId,
                groupThread: thread,
                groupThreadRowId: thread.sqliteRowId!,
                callDirection: .incoming,
                groupCallStatus: .generic,
                callEventTimestamp: callRecord.callBeganTimestamp + 5,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertNil(mockCallRecordStore.askedToUpdateRecordDirectionTo)
        XCTAssertEqual(mockCallRecordStore.askedToUpdateRecordStatusTo, .group(.generic))
        XCTAssertFalse(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    func testUpdate_UpdatesCallBeganTimestamp() {
        let (thread, interaction) = createInteraction()

        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .groupCall,
            callDirection: .incoming,
            callStatus: .group(.joined),
            callBeganTimestamp: .maxRandomInt64Compat
        )
        mockCallRecordStore.callRecords.append(callRecord)

        mockDB.write { tx in
            groupCallRecordManager.createOrUpdateCallRecord(
                callId: callRecord.callId,
                groupThread: thread,
                groupThreadRowId: thread.sqliteRowId!,
                callDirection: .incoming,
                groupCallStatus: .generic,
                callEventTimestamp: callRecord.callBeganTimestamp - 5,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.askedToUpdateTimestampTo, callRecord.callBeganTimestamp - 5)
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
/// really care to test that the `create` and `update` methods are called
/// correctly. Those methods' real implementations are tested separately.
///
/// This class snoops on those methods so we can verify they're being called.
private class SnoopingGroupCallRecordManagerImpl: GroupCallRecordManagerImpl {
    var didAskToCreate = false
    override func createGroupCallRecord(callId: UInt64, groupCallInteraction: OWSGroupCallMessage, groupCallInteractionRowId: Int64, groupThread: TSGroupThread, groupThreadRowId: Int64, callDirection: CallRecord.CallDirection, groupCallStatus: CallRecord.CallStatus.GroupCallStatus, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) -> CallRecord? {
        didAskToCreate = true
        return nil
    }

    var didAskToUpdate = false
    override func updateGroupCallRecord(groupThread: TSGroupThread, existingCallRecord: CallRecord, newCallDirection: CallRecord.CallDirection, newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) {
        didAskToUpdate = true
        return
    }
}

// MARK: - Utilities

private extension TSGroupThread {
    static func randomForTesting() -> TSGroupThread {
        return .forUnitTest(groupId: 12)
    }
}
