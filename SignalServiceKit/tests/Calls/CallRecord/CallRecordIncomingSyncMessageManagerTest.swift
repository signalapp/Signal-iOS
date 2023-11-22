//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class CallRecordIncomingSyncMessageManagerTest: XCTestCase {
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockGroupCallRecordManager: MockGroupCallRecordManager!
    private var mockIndividualCallRecordManager: MockIndividualCallRecordManager!
    private var mockInteractionStore: MockInteractionStore!
    private var mockMarkAsReadShims: MockMarkAsReadShims!
    private var mockRecipientDatabaseTable: MockRecipientDatabaseTable!
    private var mockThreadStore: MockThreadStore!

    private var mockDB = MockDB()
    private var incomingSyncMessageManager: CallRecordIncomingSyncMessageManagerImpl!

    override func setUp() {
        mockCallRecordStore = MockCallRecordStore()
        mockGroupCallRecordManager = MockGroupCallRecordManager()
        mockIndividualCallRecordManager = MockIndividualCallRecordManager()
        mockInteractionStore = MockInteractionStore()
        mockMarkAsReadShims = MockMarkAsReadShims()
        mockRecipientDatabaseTable = MockRecipientDatabaseTable()
        mockThreadStore = MockThreadStore()

        incomingSyncMessageManager = CallRecordIncomingSyncMessageManagerImpl(
            callRecordStore: mockCallRecordStore,
            groupCallRecordManager: mockGroupCallRecordManager,
            individualCallRecordManager: mockIndividualCallRecordManager,
            interactionStore: mockInteractionStore,
            markAsReadShims: mockMarkAsReadShims,
            recipientDatabaseTable: mockRecipientDatabaseTable,
            threadStore: mockThreadStore
        )
    }

    func testUpdatesIndividualCallIfExists() {
        let callId = UInt64.maxRandom
        let interactionRowId = Int64.maxRandom

        let contactAddress = SignalServiceAddress.isolatedRandomForTesting()
        let thread = TSContactThread(contactAddress: contactAddress)
        mockThreadStore.insertThread(thread)
        let threadRowId = thread.sqliteRowId!

        let callRecord = CallRecord(
            callId: callId,
            interactionRowId: interactionRowId,
            threadRowId: threadRowId,
            callType: .audioCall,
            callDirection: .outgoing,
            callStatus: .individual(.notAccepted),
            callBeganTimestamp: .maxRandomInt64Compat
        )

        let contactServiceId = contactAddress.aci!
        let contactRecipient = SignalRecipient(aci: contactServiceId, pni: nil, phoneNumber: nil)

        let interaction = TSCall(
            callType: .outgoingMissed,
            offerType: .audio,
            thread: thread,
            sentAtTimestamp: UInt64.maxRandom
        )
        interaction.updateRowId(interactionRowId)

        mockCallRecordStore.callRecords.append(callRecord)
        mockDB.write { tx in
            mockRecipientDatabaseTable.insertRecipient(contactRecipient, transaction: tx)
        }
        mockInteractionStore.insertedInteractions.append(interaction)

        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    callId: callId,
                    conversationParams: .oneToOne(
                        contactServiceId: contactServiceId,
                        individualCallStatus: .accepted,
                        individualCallInteractionType: .incomingAnsweredElsewhere
                    ),
                    callTimestamp: .maxRandom,
                    callType: .audioCall,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(
            (mockInteractionStore.insertedInteractions.first! as! TSCall).callType,
            .incomingAnsweredElsewhere
        )
        XCTAssertEqual(
            mockIndividualCallRecordManager.updatedRecords,
            [.individual(.accepted)]
        )
        XCTAssertTrue(mockMarkAsReadShims.hasMarkedAsRead)
    }

    func testCreatesIndividualCallIfNoneExists() {
        let callId = UInt64.maxRandom
        let contactAddress = SignalServiceAddress.isolatedRandomForTesting()
        let contactServiceId = contactAddress.aci!

        let contactThread = TSContactThread(contactAddress: contactAddress)
        mockDB.write { tx in
            let recipient = SignalRecipient(aci: contactServiceId, pni: nil, phoneNumber: nil)
            mockRecipientDatabaseTable.insertRecipient(recipient, transaction: tx)
        }

        mockThreadStore.insertThread(contactThread)

        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    callId: callId,
                    conversationParams: .oneToOne(
                        contactServiceId: contactServiceId,
                        individualCallStatus: .accepted,
                        individualCallInteractionType: .incomingAnsweredElsewhere
                    ),
                    callTimestamp: .maxRandom,
                    callType: .audioCall,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(
            (mockInteractionStore.insertedInteractions.first! as! TSCall).callType,
            .incomingAnsweredElsewhere
        )
        XCTAssertEqual(
            mockIndividualCallRecordManager.createdRecords,
            [callId]
        )
        XCTAssertTrue(mockMarkAsReadShims.hasMarkedAsRead)
    }
}

// MARK: - Mocks

private func notImplemented() -> Never {
    owsFail("Not implemented!")
}

// MARK: MockGroupCallRecordManager

private class MockGroupCallRecordManager: GroupCallRecordManager {
    func createGroupCallRecord(callId: UInt64, groupCallInteraction: OWSGroupCallMessage, groupThread: TSGroupThread, callDirection: CallRecord.CallDirection, groupCallStatus: CallRecord.CallStatus.GroupCallStatus, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) -> CallRecord? {
        notImplemented()
    }

    func createOrUpdateCallRecord(callId: UInt64, groupThread: TSGroupThread, callDirection: CallRecord.CallDirection, groupCallStatus: CallRecord.CallStatus.GroupCallStatus, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) {
        notImplemented()
    }

    func updateCallBeganTimestampIfEarlier(existingCallRecord: CallRecord, callEventTimestamp: UInt64, tx: DBWriteTransaction) {
        notImplemented()
    }
}

// MARK: MockIndividualCallRecordManager

private class MockIndividualCallRecordManager: IndividualCallRecordManager {
    var createdRecords = [UInt64]()
    var updatedRecords = [CallRecord.CallStatus]()

    func createRecordForInteraction(
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
        createdRecords.append(callId)
    }

    func updateRecord(
        contactThread: TSContactThread,
        existingCallRecord: CallRecord,
        newIndividualCallStatus: CallRecord.CallStatus.IndividualCallStatus,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) {
        updatedRecords.append(.individual(newIndividualCallStatus))
    }

    func updateInteractionTypeAndRecordIfExists(individualCallInteraction: TSCall, individualCallInteractionRowId: Int64, contactThread: TSContactThread, newCallInteractionType: RPRecentCallType, tx: DBWriteTransaction) {
        notImplemented()
    }

    func createOrUpdateRecordForInteraction(individualCallInteraction: TSCall, individualCallInteractionRowId: Int64, contactThread: TSContactThread, contactThreadRowId: Int64, callId: UInt64, tx: DBWriteTransaction) {
        notImplemented()
    }
}

// MARK: MarkAsReadShims

private class MockMarkAsReadShims: CallRecordIncomingSyncMessageManagerImpl.Shims.MarkAsRead {
    var hasMarkedAsRead = false

    func markThingsAsReadForIncomingSyncMessage(
        callInteraction: TSInteraction & OWSReadTracking,
        thread: TSThread,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        hasMarkedAsRead = true
    }
}
