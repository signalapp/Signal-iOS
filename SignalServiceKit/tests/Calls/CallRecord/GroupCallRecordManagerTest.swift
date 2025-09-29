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
    private var mockOutgoingSyncMessageManager: MockOutgoingCallEventSyncMessageManager!

    private var mockDB: InMemoryDB!
    private var snoopingGroupCallRecordManager: SnoopingGroupCallRecordManagerImpl!
    private var groupCallRecordManager: GroupCallRecordManagerImpl!

    override func setUp() {
        mockCallRecordStore = MockCallRecordStore()
        mockInteractionStore = MockInteractionStore()
        mockOutgoingSyncMessageManager = {
            let mock = MockOutgoingCallEventSyncMessageManager()
            mock.expectedCallEvent = .callUpdated
            return mock
        }()

        mockDB = InMemoryDB()
        snoopingGroupCallRecordManager = SnoopingGroupCallRecordManagerImpl(
            callRecordStore: mockCallRecordStore,
            interactionStore: mockInteractionStore,
            outgoingSyncMessageManager: mockOutgoingSyncMessageManager
        )
        groupCallRecordManager = GroupCallRecordManagerImpl(
            callRecordStore: mockCallRecordStore,
            interactionStore: mockInteractionStore,
            outgoingSyncMessageManager: mockOutgoingSyncMessageManager
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

    func testCreateOrUpdate_CallsCreateAndInsertsInteraction() throws {
        let (thread, _) = createInteraction()

        try mockDB.write { tx in
            try snoopingGroupCallRecordManager.createOrUpdateCallRecord(
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

    func testCreateOrUpdate_CallsUpdate() throws {
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

        try mockDB.write { tx in
            try snoopingGroupCallRecordManager.createOrUpdateCallRecord(
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

    func testCreateOrUpdate_DoesNothingIfRecentlyDeleted() throws {
        let (thread, _) = createInteraction()

        mockCallRecordStore.fetchMock = { .matchDeleted }

        try mockDB.write { tx in
            try snoopingGroupCallRecordManager.createOrUpdateCallRecord(
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

        XCTAssertFalse(snoopingGroupCallRecordManager.didAskToUpdate)
    }

    // MARK: - Create group call record

    func testCreateGroupCallRecord() throws {
        let (thread1, interaction1) = createInteraction()
        let (thread2, interaction2) = createInteraction()

        _ = try mockDB.write { tx in
            try groupCallRecordManager.createGroupCallRecord(
                callId: .maxRandom,
                groupCallInteraction: interaction1,
                groupCallInteractionRowId: interaction1.sqliteRowId!,
                groupThreadRowId: thread1.sqliteRowId!,
                callDirection: .outgoing,
                groupCallStatus: .joined,
                groupCallRingerAci: nil,
                callEventTimestamp: .maxRandomInt64Compat,
                shouldSendSyncMessage: false,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 0)

        _ = try mockDB.write { tx in
            try groupCallRecordManager.createGroupCallRecord(
                callId: .maxRandom,
                groupCallInteraction: interaction2,
                groupCallInteractionRowId: interaction2.sqliteRowId!,
                groupThreadRowId: thread2.sqliteRowId!,
                callDirection: .incoming,
                groupCallStatus: .ringing,
                groupCallRingerAci: .randomForTesting(),
                callEventTimestamp: .maxRandomInt64Compat,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 2)
        XCTAssertNotNil(mockCallRecordStore.callRecords[1].groupCallRingerAci)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 1)
    }

    func testCreateGroupCallRecordForPeek() throws {
        let (thread, interaction) = createInteraction()

        _ = try mockDB.write { tx in
            try groupCallRecordManager.createGroupCallRecordForPeek(
                callId: .maxRandom,
                groupCallInteraction: interaction,
                groupCallInteractionRowId: interaction.sqliteRowId!,
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
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 0)
    }

    // MARK: Update record

    func testUpdate_Updates() throws {
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

        try mockDB.write { tx in
            try groupCallRecordManager.createOrUpdateCallRecord(
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
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 1)
    }

    func testUpdate_SkipsDirectionAndSyncMessage() throws {
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

        try mockDB.write { tx in
            try groupCallRecordManager.createOrUpdateCallRecord(
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
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 0)
    }

    /// We shouldn't send a sync message if we tried updating a record with a
    /// status that's illegal per the record's current state.
    ///
    /// In this test, we try to illegally go from "joined" to "generic".
    func testUpdate_SkipsSyncMessageIfStatusTransitionDisallowed() throws {
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

        try mockDB.write { tx in
            try groupCallRecordManager.createOrUpdateCallRecord(
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
        XCTAssertNil(mockCallRecordStore.askedToUpdateRecordStatusTo)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 0)
    }

    func testUpdate_UpdatesCallBeganTimestamp() throws {
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

        try mockDB.write { tx in
            try groupCallRecordManager.createOrUpdateCallRecord(
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

        XCTAssertEqual(mockCallRecordStore.askedToUpdateCallBeganTimestampTo, callRecord.callBeganTimestamp - 5)
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

        XCTAssertNil(mockCallRecordStore.askedToUpdateCallBeganTimestampTo)

        mockDB.write { tx in
            groupCallRecordManager.updateCallBeganTimestampIfEarlier(
                existingCallRecord: callRecord,
                callEventTimestamp: 9,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.askedToUpdateCallBeganTimestampTo, 9)
    }
}
// MARK: - SnoopingGroupCallRecordManagerImpl

/// In testing ``GroupCallRecordManagerImpl``'s `createOrUpdate` method, we only
/// really care to test that the `create` and `update` methods are called
/// correctly. Those methods' real implementations are tested separately.
///
/// This class snoops on those methods so we can verify they're being called.
final private class SnoopingGroupCallRecordManagerImpl: GroupCallRecordManagerImpl {
    var didAskToCreate = false
    override func createGroupCallRecord(callId: UInt64, groupCallInteraction: OWSGroupCallMessage, groupCallInteractionRowId: Int64, groupThreadRowId: Int64, callDirection: CallRecord.CallDirection, groupCallStatus: CallRecord.CallStatus.GroupCallStatus, groupCallRingerAci: Aci?, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) -> CallRecord {
        didAskToCreate = true
        return CallRecord(callId: callId, interactionRowId: groupCallInteractionRowId, threadRowId: groupThreadRowId, callType: .groupCall, callDirection: callDirection, callStatus: .group(groupCallStatus), callBeganTimestamp: callEventTimestamp)
    }

    var didAskToUpdate = false
    override func updateGroupCallRecord(existingCallRecord: CallRecord, newCallDirection: CallRecord.CallDirection, newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus, newGroupCallRingerAci: Aci?, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) {
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
