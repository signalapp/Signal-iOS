//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class IndividualCallRecordManagerTest: XCTestCase {
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockInteractionStore: MockInteractionStore!
    private var mockOutgoingSyncMessageManager: MockCallRecordOutgoingSyncMessageManager!

    private var mockDB: MockDB!
    private var individualCallRecordManager: SnoopingIndividualCallRecordManagerImpl!

    override func setUp() {
        mockCallRecordStore = MockCallRecordStore()
        mockInteractionStore = MockInteractionStore()
        mockOutgoingSyncMessageManager = MockCallRecordOutgoingSyncMessageManager()

        mockDB = MockDB()
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
                individualCallInteractionRowId: interaction.grdbId!.int64Value,
                contactThread: thread,
                newCallInteractionType: .incomingAnsweredElsewhere,
                tx: tx
            )
        }

        XCTAssertEqual(interaction.callType, .incomingAnsweredElsewhere)
        XCTAssertNil(individualCallRecordManager.didAskToUpdateRecord)
        XCTAssertNil(individualCallRecordManager.didAskToCreateRecord)
        XCTAssertFalse(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    func testUpdateInteractionTypeAndRecordIfExists_recordExists() {
        let (thread, interaction) = createInteraction()

        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.grdbId!.int64Value,
            threadRowId: thread.grdbId!.int64Value,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: .individual(.pending)
        )
        mockCallRecordStore.callRecords.append(callRecord)

        mockDB.write { tx in
            individualCallRecordManager.updateInteractionTypeAndRecordIfExists(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.grdbId!.int64Value,
                contactThread: thread,
                newCallInteractionType: .incomingAnsweredElsewhere,
                tx: tx
            )
        }

        XCTAssertEqual(interaction.callType, .incomingAnsweredElsewhere)
        XCTAssertEqual(individualCallRecordManager.didAskToUpdateRecord, .accepted)
        XCTAssertTrue(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    // MARK: - createOrUpdateRecordForInteraction

    func testCreateOrUpdate_noRecordExists() {
        let (thread, interaction) = createInteraction()

        mockDB.write { tx in
            individualCallRecordManager.createOrUpdateRecordForInteraction(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.grdbId!.int64Value,
                contactThread: thread,
                contactThreadRowId: thread.grdbId!.int64Value,
                callId: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(individualCallRecordManager.didAskToCreateRecord, .pending)
        XCTAssertTrue(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    func testCreateOrUpdate_recordExists() {
        let (thread, interaction) = createInteraction(callType: .incomingDeclined)
        let callId = UInt64.maxRandom

        let callRecord = CallRecord(
            callId: callId,
            interactionRowId: interaction.grdbId!.int64Value,
            threadRowId: thread.grdbId!.int64Value,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: .individual(.pending)
        )
        mockCallRecordStore.callRecords.append(callRecord)

        mockDB.write { tx in
            individualCallRecordManager.createOrUpdateRecordForInteraction(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.grdbId!.int64Value,
                contactThread: thread,
                contactThreadRowId: thread.grdbId!.int64Value,
                callId: callId,
                tx: tx
            )
        }

        XCTAssertEqual(individualCallRecordManager.didAskToUpdateRecord, .notAccepted)
        XCTAssertTrue(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    // MARK: - createRecordForInteraction

    func testCreate_noSyncMessage() {
        let (thread, interaction) = createInteraction()

        mockDB.write { tx in
            individualCallRecordManager.createRecordForInteraction(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.grdbId!.int64Value,
                contactThread: thread,
                contactThreadRowId: thread.grdbId!.int64Value,
                callId: .maxRandom,
                callType: .audioCall,
                callDirection: .incoming,
                individualCallStatus: .accepted,
                shouldSendSyncMessage: false,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
        XCTAssertFalse(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    func testCreate_syncMessage() {
        let (thread, interaction) = createInteraction()

        mockDB.write { tx in
            individualCallRecordManager.createRecordForInteraction(
                individualCallInteraction: interaction,
                individualCallInteractionRowId: interaction.grdbId!.int64Value,
                contactThread: thread,
                contactThreadRowId: thread.grdbId!.int64Value,
                callId: .maxRandom,
                callType: .audioCall,
                callDirection: .incoming,
                individualCallStatus: .accepted,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.callRecords.count, 1)
        XCTAssertTrue(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    // MARK: - updateRecordForInteraction

    func testUpdate_noSyncMessage() {
        let (thread, interaction) = createInteraction()
        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: .maxRandom,
            threadRowId: .maxRandom,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: .individual(.notAccepted)
        )

        mockDB.write { tx in
            individualCallRecordManager.updateRecordForInteraction(
                individualCallInteraction: interaction,
                contactThread: thread,
                existingCallRecord: callRecord,
                newIndividualCallStatus: .accepted,
                shouldSendSyncMessage: false,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.askedToUpdateRecordTo, .individual(.accepted))
        XCTAssertFalse(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    func testUpdate_noSyncMessageIfUpdateFails() {
        mockCallRecordStore.shouldAllowStatusUpdate = false

        let (thread, interaction) = createInteraction()
        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: .maxRandom,
            threadRowId: .maxRandom,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: .individual(.notAccepted)
        )

        mockDB.write { tx in
            individualCallRecordManager.updateRecordForInteraction(
                individualCallInteraction: interaction,
                contactThread: thread,
                existingCallRecord: callRecord,
                newIndividualCallStatus: .accepted,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.askedToUpdateRecordTo, .individual(.accepted))
        XCTAssertFalse(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
    }

    func testUpdate_syncMessage() {
        let (thread, interaction) = createInteraction()
        let callRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: .maxRandom,
            threadRowId: .maxRandom,
            callType: .audioCall,
            callDirection: .incoming,
            callStatus: .individual(.notAccepted)
        )

        mockDB.write { tx in
            individualCallRecordManager.updateRecordForInteraction(
                individualCallInteraction: interaction,
                contactThread: thread,
                existingCallRecord: callRecord,
                newIndividualCallStatus: .accepted,
                shouldSendSyncMessage: true,
                tx: tx
            )
        }

        XCTAssertEqual(mockCallRecordStore.askedToUpdateRecordTo, .individual(.accepted))
        XCTAssertTrue(mockOutgoingSyncMessageManager.askedToSendSyncMessage)
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

    override func createRecordForInteraction(
        individualCallInteraction: TSCall,
        individualCallInteractionRowId: Int64,
        contactThread: TSContactThread,
        contactThreadRowId: Int64,
        callId: UInt64,
        callType: CallRecord.CallType,
        callDirection: CallRecord.CallDirection,
        individualCallStatus: CallRecord.CallStatus.IndividualCallStatus,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        didAskToCreateRecord = individualCallStatus
        super.createRecordForInteraction(
            individualCallInteraction: individualCallInteraction,
            individualCallInteractionRowId: individualCallInteractionRowId,
            contactThread: contactThread,
            contactThreadRowId: contactThreadRowId,
            callId: callId,
            callType: callType,
            callDirection: callDirection,
            individualCallStatus: individualCallStatus,
            shouldSendSyncMessage: shouldSendSyncMessage,
            tx: tx
        )
    }

    override func updateRecordForInteraction(
        individualCallInteraction: TSCall,
        contactThread: TSContactThread,
        existingCallRecord: CallRecord,
        newIndividualCallStatus: CallRecord.CallStatus.IndividualCallStatus,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        didAskToUpdateRecord = newIndividualCallStatus
        super.updateRecordForInteraction(
            individualCallInteraction: individualCallInteraction,
            contactThread: contactThread,
            existingCallRecord: existingCallRecord,
            newIndividualCallStatus: newIndividualCallStatus,
            shouldSendSyncMessage: shouldSendSyncMessage,
            tx: tx
        )
    }
}
