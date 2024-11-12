//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IndividualCallRecordManagerTest: XCTestCase {
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockInteractionStore: MockInteractionStore!
    private var mockOutgoingSyncMessageManager: MockOutgoingCallEventSyncMessageManager!

    private var mockDB: InMemoryDB!
    private var individualCallRecordManager: SnoopingIndividualCallRecordManagerImpl!

    override func setUp() {
        mockCallRecordStore = MockCallRecordStore()
        mockInteractionStore = MockInteractionStore()
        mockOutgoingSyncMessageManager = {
            let mock = MockOutgoingCallEventSyncMessageManager()
            mock.expectedCallEvent = .callUpdated
            return mock
        }()

        mockDB = InMemoryDB()
        individualCallRecordManager = SnoopingIndividualCallRecordManagerImpl(
            callRecordStore: mockCallRecordStore,
            interactionStore: mockInteractionStore,
            outgoingSyncMessageManager: mockOutgoingSyncMessageManager
        )
    }

    private func createInteraction(
        callType: RPRecentCallType = .incomingIncomplete
    ) -> (TSContactThread, TSCall) {
        let thread = TSContactThread(contactAddress: .isolatedRandomForTesting())
        thread.updateRowId(.maxRandom)

        let interaction = TSCall(callType: callType, offerType: .audio, thread: thread, sentAtTimestamp: .maxRandom)
        interaction.updateRowId(.maxRandom)

        return (thread, interaction)
    }

    // MARK: - updateInteractionTypeAndRecordIfExists

    func testUpdateInteractionTypeAndRecordIfExists_noRecordExists() {
        let (thread, interaction) = createInteraction()

        mockDB.write { tx in
            individualCallRecordManager.updateInteractionTypeAndRecordIfExists(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.sqliteRowId!,
                contactThread: thread,
                newCallInteractionType: .incomingAnsweredElsewhere,
                tx: tx
            )
        }

        XCTAssertEqual(interaction.callType, .incomingAnsweredElsewhere)
        XCTAssertNil(individualCallRecordManager.didAskToUpdateRecord)
        XCTAssertNil(individualCallRecordManager.didAskToCreateRecord)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 0)
    }

    func testUpdateInteractionTypeAndRecordIfExists_recordExists() {
        let (thread, interaction) = createInteraction()

        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: .individual(.pending),
            callBeganTimestamp: interaction.timestamp
        )
        mockCallRecordStore.callRecords.append(callRecord)

        mockDB.write { tx in
            individualCallRecordManager.updateInteractionTypeAndRecordIfExists(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.sqliteRowId!,
                contactThread: thread,
                newCallInteractionType: .incomingAnsweredElsewhere,
                tx: tx
            )
        }

        XCTAssertEqual(interaction.callType, .incomingAnsweredElsewhere)
        XCTAssertEqual(individualCallRecordManager.didAskToUpdateRecord, .accepted)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 1)
    }

    // MARK: - createOrUpdateRecordForInteraction

    func testCreateOrUpdate_noRecordExists() throws {
        let (thread, interaction) = createInteraction()

        try mockDB.write { tx in
            try individualCallRecordManager.createOrUpdateRecordForInteraction(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.sqliteRowId!,
                contactThread: thread,
                contactThreadRowId: thread.sqliteRowId!,
                callId: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(individualCallRecordManager.didAskToCreateRecord, .pending)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 1)
    }

    func testCreateOrUpdate_recordExists() throws {
        let (thread, interaction) = createInteraction(callType: .incomingDeclined)
        let callId = UInt64.maxRandom

        let callRecord = CallRecord(
            callId: callId,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: .individual(.pending),
            callBeganTimestamp: interaction.timestamp
        )
        mockCallRecordStore.callRecords.append(callRecord)

        try mockDB.write { tx in
            try individualCallRecordManager.createOrUpdateRecordForInteraction(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.sqliteRowId!,
                contactThread: thread,
                contactThreadRowId: thread.sqliteRowId!,
                callId: callId,
                tx: tx
            )
        }

        XCTAssertEqual(individualCallRecordManager.didAskToUpdateRecord, .notAccepted)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 1)
    }

    func testCreateOrUpdate_nothingIfRecordRecentlyDeleted() throws {
        let (thread, interaction) = createInteraction(callType: .incomingDeclined)
        let callId = UInt64.maxRandom

        mockCallRecordStore.fetchMock = { .matchDeleted }

        try mockDB.write { tx in
            try individualCallRecordManager.createOrUpdateRecordForInteraction(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.sqliteRowId!,
                contactThread: thread,
                contactThreadRowId: thread.sqliteRowId!,
                callId: callId,
                tx: tx
            )
        }

        XCTAssertNil(individualCallRecordManager.didAskToUpdateRecord)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 0)
    }

    // MARK: - createRecordForInteraction

    func testCreate_noSyncMessage() throws {
        let (thread, interaction) = createInteraction()

        try mockDB.write { tx in
            _ = try individualCallRecordManager.createRecordForInteraction(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.sqliteRowId!,
                contactThread: thread,
                contactThreadRowId: thread.sqliteRowId!,
                callId: .maxRandom,
                callType: .audioCall,
                callDirection: .incoming,
                individualCallStatus: .accepted,
                callEventTimestamp: interaction.timestamp,
                shouldSendSyncMessage: false,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 0)
    }

    func testCreate_syncMessage() throws {
        let (thread, interaction) = createInteraction()

        try mockDB.write { tx in
            _ = try individualCallRecordManager.createRecordForInteraction(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.sqliteRowId!,
                contactThread: thread,
                contactThreadRowId: thread.sqliteRowId!,
                callId: .maxRandom,
                callType: .audioCall,
                callDirection: .incoming,
                individualCallStatus: .accepted,
                callEventTimestamp: interaction.timestamp,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 1)
    }

    // MARK: - updateRecordForInteraction

    func testUpdate_noSyncMessage() {
        let (thread, interaction) = createInteraction()
        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: .individual(.notAccepted),
            callBeganTimestamp: interaction.timestamp
        )

        mockDB.write { tx in
            individualCallRecordManager.updateRecord(
                contactThread: thread,
                existingCallRecord: callRecord,
                newIndividualCallStatus: .accepted,
                shouldSendSyncMessage: false,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.askedToUpdateRecordStatusTo, .individual(.accepted))
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 0)
    }

    /// We shouldn't send a sync message if we tried updating a record with a
    /// status that's illegal per the record's current state.
    ///
    /// In this test, we try to illegally go from "accepted" to "pending".
    func testUpdate_noSyncMessageIfStatusTransitionDisallowed() {
        let (thread, interaction) = createInteraction()
        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: .individual(.accepted),
            callBeganTimestamp: interaction.timestamp
        )

        mockDB.write { tx in
            individualCallRecordManager.updateRecord(
                contactThread: thread,
                existingCallRecord: callRecord,
                newIndividualCallStatus: .pending,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertNil(mockCallRecordStore.askedToUpdateRecordStatusTo)
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 0)
    }

    func testUpdate_syncMessage() {
        let (thread, interaction) = createInteraction()
        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: .individual(.notAccepted),
            callBeganTimestamp: interaction.timestamp
        )

        mockDB.write { tx in
            individualCallRecordManager.updateRecord(
                contactThread: thread,
                existingCallRecord: callRecord,
                newIndividualCallStatus: .accepted,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.askedToUpdateRecordStatusTo, .individual(.accepted))
        XCTAssertEqual(mockOutgoingSyncMessageManager.syncMessageSendCount, 1)
    }
}

// MARK: - SnoopingIndividualCallRecordManagerImpl

/// There are a couple methods on ``IndividualCallRecordManagerImpl`` that are
/// designed to feed into the "create" and "update" methods, with some special
/// logic that's bespoke to where those methods are called.
///
/// This class snoops on the "create" and "update" methods, so we can verify
/// they're being called – the real implementation of those methods are tested
/// separately.
private class SnoopingIndividualCallRecordManagerImpl: IndividualCallRecordManagerImpl {
    var didAskToCreateRecord: CallRecord.CallStatus.IndividualCallStatus?
    var didAskToUpdateRecord: CallRecord.CallStatus.IndividualCallStatus?

    override func createRecordForInteraction(individualCallInteraction: TSCall, individualCallInteractionRowId: Int64, contactThread: TSContactThread, contactThreadRowId: Int64, callId: UInt64, callType: CallRecord.CallType, callDirection: CallRecord.CallDirection, individualCallStatus: CallRecord.CallStatus.IndividualCallStatus, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) throws -> CallRecord {
        didAskToCreateRecord = individualCallStatus
        return try super.createRecordForInteraction(individualCallInteraction: individualCallInteraction, individualCallInteractionRowId: individualCallInteractionRowId, contactThread: contactThread, contactThreadRowId: contactThreadRowId, callId: callId, callType: callType, callDirection: callDirection, individualCallStatus: individualCallStatus, callEventTimestamp: callEventTimestamp, shouldSendSyncMessage: shouldSendSyncMessage, tx: tx)
    }

    override func updateRecord(contactThread: TSContactThread, existingCallRecord: CallRecord, newIndividualCallStatus: CallRecord.CallStatus.IndividualCallStatus, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) {
        didAskToUpdateRecord = newIndividualCallStatus
        super.updateRecord(contactThread: contactThread, existingCallRecord: existingCallRecord, newIndividualCallStatus: newIndividualCallStatus, shouldSendSyncMessage: shouldSendSyncMessage, tx: tx)
    }
}
