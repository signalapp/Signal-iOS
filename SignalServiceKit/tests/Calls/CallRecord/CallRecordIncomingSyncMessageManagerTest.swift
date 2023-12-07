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

    // MARK: - Individual calls

    func testUpdatesIndividualCallIfExists() {
        let callId = UInt64.maxRandom

        let contactAddress = SignalServiceAddress.isolatedRandomForTesting()
        let thread = TSContactThread(contactAddress: contactAddress)
        mockThreadStore.insertThread(thread)
        let threadRowId = thread.sqliteRowId!

        let contactServiceId = contactAddress.aci!
        let contactRecipient = SignalRecipient(aci: contactServiceId, pni: nil, phoneNumber: nil)

        let interaction = TSCall(
            callType: .outgoingMissed,
            offerType: .audio,
            thread: thread,
            sentAtTimestamp: UInt64.maxRandom
        )

        mockDB.write { tx in
            mockInteractionStore.insertInteraction(interaction, tx: tx)
            mockRecipientDatabaseTable.insertRecipient(contactRecipient, transaction: tx)
        }

        let callRecord = CallRecord(
            callId: callId,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: threadRowId,
            callType: .audioCall,
            callDirection: .outgoing,
            callStatus: .individual(.notAccepted),
            callBeganTimestamp: .maxRandomInt64Compat
        )

        mockDB.write { tx in
            _ = mockCallRecordStore.insert(callRecord: callRecord, tx: tx)
        }

        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .individual(contactServiceId: contactServiceId),
                    callId: callId,
                    callTimestamp: .maxRandom,
                    callEvent: .accepted,
                    callType: .audioCall,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(
            (mockInteractionStore.insertedInteractions.first! as! TSCall).callType,
            .outgoing
        )
        XCTAssertEqual(
            mockIndividualCallRecordManager.updatedRecords,
            [.individual(.accepted)]
        )
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 1)
    }

    func testCreatesIndividualCallIfNoneExists() {
        let callId = UInt64.maxRandom
        let contactAddress = SignalServiceAddress.isolatedRandomForTesting()
        let contactServiceId = contactAddress.aci!

        let contactThread = TSContactThread(contactAddress: contactAddress)
        mockThreadStore.insertThread(contactThread)

        mockDB.write { tx in
            let recipient = SignalRecipient(aci: contactServiceId, pni: nil, phoneNumber: nil)
            mockRecipientDatabaseTable.insertRecipient(recipient, transaction: tx)
        }

        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .individual(contactServiceId: contactServiceId),
                    callId: callId,
                    callTimestamp: .maxRandom,
                    callEvent: .accepted,
                    callType: .audioCall,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(
            (mockInteractionStore.insertedInteractions.first! as! TSCall).callType,
            .outgoing
        )
        XCTAssertEqual(
            mockIndividualCallRecordManager.createdRecords,
            [callId]
        )
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 1)
    }

    // MARK: - Group calls

    private func createGroupCallRecord(
        groupId: UInt8 = 0,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus
    ) -> (CallRecord, Data) {
        let thread = TSGroupThread.forUnitTest(groupId: groupId)
        let interaction = OWSGroupCallMessage(
            joinedMemberAcis: [], creatorAci: nil, thread: thread, sentAtTimestamp: .maxRandom
        )

        mockDB.write { tx in
            mockThreadStore.insertThread(thread)
            mockInteractionStore.insertInteraction(interaction, tx: tx)
        }

        let existingCallRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interaction.sqliteRowId!,
            threadRowId: thread.sqliteRowId!,
            callType: .groupCall,
            callDirection: callDirection,
            callStatus: .group(groupCallStatus),
            callBeganTimestamp: .maxRandom
        )

        mockDB.write { tx in
            XCTAssertTrue(mockCallRecordStore.insert(
                callRecord: existingCallRecord, tx: tx
            ))
        }

        return (existingCallRecord, thread.groupId)
    }

    func testUpdatesGroupCall_joined() {
        var updateCount = 0
        mockGroupCallRecordManager.updateGroupCallStub = { _, newGroupCallStatus in
            updateCount += 1
            XCTAssertEqual(newGroupCallStatus, .joined)
        }

        let (existingCallRecord, groupId) = createGroupCallRecord(
            callDirection: .incoming, groupCallStatus: .generic
        )

        /// A first sync message should get us to the joined state.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: groupId),
                    callId: existingCallRecord.callId,
                    callTimestamp: existingCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
                    callType: .groupCall,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// A second sync message keeps us in the joined state.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: groupId),
                    callId: existingCallRecord.callId,
                    callTimestamp: existingCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
                    callType: .groupCall,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 2)
    }

    func testUpdatesGroupCall_ringAccepted() {
        var updateCount = 0
        mockGroupCallRecordManager.updateGroupCallStub = { _, newGroupCallStatus in
            updateCount += 1
            XCTAssertEqual(newGroupCallStatus, .ringingAccepted)
        }

        let (missedCallRecord, missedGroupId) = createGroupCallRecord(
            groupId: 1, callDirection: .incoming, groupCallStatus: .incomingRingingMissed
        )

        let (declinedCallRecord, declinedGroupId) = createGroupCallRecord(
            groupId: 2, callDirection: .incoming, groupCallStatus: .ringingNotAccepted
        )

        /// Updating a ringing-missed record makes it ringing-accepted.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: missedGroupId),
                    callId: missedCallRecord.callId,
                    callTimestamp: missedCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
                    callType: .groupCall,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating a ringing-declined record makes it ringing-accepted.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: declinedGroupId),
                    callId: declinedCallRecord.callId,
                    callTimestamp: declinedCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
                    callType: .groupCall,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating an already rining-accepted record doesn't change the state.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: declinedGroupId),
                    callId: declinedCallRecord.callId,
                    callTimestamp: declinedCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
                    callType: .groupCall,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(updateCount, 3)
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 3)
    }

    func testUpdatesGroupCall_ringDeclined() {
        var updateCount = 0
        mockGroupCallRecordManager.updateGroupCallStub = { _, newGroupCallStatus in
            updateCount += 1
            XCTAssertEqual(newGroupCallStatus, .ringingNotAccepted)
        }

        let (genericCallRecord, genericGroupId) = createGroupCallRecord(
            groupId: 1, callDirection: .incoming, groupCallStatus: .generic
        )

        let (missedCallRecord, missedGroupId) = createGroupCallRecord(
            groupId: 2, callDirection: .incoming, groupCallStatus: .incomingRingingMissed
        )

        /// Updating a generic record makes it ringing-declined.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: genericGroupId),
                    callId: genericCallRecord.callId,
                    callTimestamp: genericCallRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
                    callType: .groupCall,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating a ringing-missed record makes it ringing-declined.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: missedGroupId),
                    callId: missedCallRecord.callId,
                    callTimestamp: missedCallRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
                    callType: .groupCall,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating an already-declined record keeps it declined.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: missedGroupId),
                    callId: missedCallRecord.callId,
                    callTimestamp: missedCallRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
                    callType: .groupCall,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(updateCount, 3)
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 3)
    }

    func testUpdatesGroupCall_ringDeclinedSupercededByJoin() {
        var updateCount = 0
        mockGroupCallRecordManager.updateGroupCallStub = { existingCallRecord, newGroupCallStatus in
            guard case let .group(groupCallStatus) = existingCallRecord.callStatus else {
                XCTFail("Missing group call status!")
                return
            }

            updateCount += 1
            XCTAssertEqual(newGroupCallStatus, groupCallStatus)
        }

        let (joinedCallRecord, joinedGroupId) = createGroupCallRecord(
            groupId: 1, callDirection: .incoming, groupCallStatus: .joined
        )

        let (acceptedCallRecord, acceptedGroupId) = createGroupCallRecord(
            groupId: 2, callDirection: .incoming, groupCallStatus: .ringingAccepted
        )

        /// Updating a joined record keeps it joined.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: joinedGroupId),
                    callId: joinedCallRecord.callId,
                    callTimestamp: joinedCallRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
                    callType: .groupCall,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating a ringing-accepted record keeps it ringing-accepted.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: acceptedGroupId),
                    callId: acceptedCallRecord.callId,
                    callTimestamp: acceptedCallRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
                    callType: .groupCall,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 2)
    }

    /// We should never receive a sync message for an outgoing call for which
    /// we already have a call record, because if we have a call record then we
    /// started the call and are the one sending sync messages.
    func testUpdatesGroupCall_outgoingIsIgnored() {
        mockGroupCallRecordManager.updateGroupCallStub = { (_, _) in
            XCTFail("Should never be updating!")
        }

        /// We treat all outgoing group rings as accepted because we don't track
        /// their ring state.
        let (outgoingCallRecord, outgoingGroupId) = createGroupCallRecord(
            callDirection: .outgoing, groupCallStatus: .ringingAccepted
        )

        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: outgoingGroupId),
                    callId: outgoingCallRecord.callId,
                    callTimestamp: outgoingCallRecord.callBeganTimestamp,
                    callEvent: .accepted,
                    callType: .groupCall,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )

            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                    conversationType: .group(groupId: outgoingGroupId),
                    callId: outgoingCallRecord.callId,
                    callTimestamp: outgoingCallRecord.callBeganTimestamp,
                    callEvent: .notAccepted,
                    callType: .groupCall,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 0)
    }

    func testCreatesGroupCall() {
        let groupThread = TSGroupThread.forUnitTest()
        mockThreadStore.insertThread(groupThread)

        func simulateIncoming(
            direction: CallRecord.CallDirection,
            event: CallRecordIncomingSyncMessageParams.CallEvent
        ) {
            mockDB.write { tx in
                incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                    incomingSyncMessage: CallRecordIncomingSyncMessageParams(
                        conversationType: .group(groupId: groupThread.groupId),
                        callId: .maxRandom,
                        callTimestamp: .maxRandom,
                        callEvent: event,
                        callType: .groupCall,
                        callDirection: direction
                    ),
                    syncMessageTimestamp: .maxRandom,
                    tx: tx
                )
            }
        }

        /// Outgoing and not accepted shouldn't try and create anything.
        simulateIncoming(direction: .outgoing, event: .notAccepted)

        var createCount = 0
        let expectedGroupCallStatus: Box<(
            CallRecord.CallDirection,
            CallRecord.CallStatus.GroupCallStatus
        )> = Box((.incoming, .generic))
        mockGroupCallRecordManager.createGroupCallStub = { direction, groupCallStatus in
            createCount += 1
            XCTAssertEqual(direction, expectedGroupCallStatus.wrapped.0)
            XCTAssertEqual(groupCallStatus, expectedGroupCallStatus.wrapped.1)
        }

        expectedGroupCallStatus.wrapped = (.outgoing, .ringingAccepted)
        simulateIncoming(direction: .outgoing, event: .accepted)

        expectedGroupCallStatus.wrapped = (.incoming, .joined)
        simulateIncoming(direction: .incoming, event: .accepted)

        expectedGroupCallStatus.wrapped = (.incoming, .ringingNotAccepted)
        simulateIncoming(direction: .incoming, event: .notAccepted)

        XCTAssertEqual(createCount, 3)
        XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 3)
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 3)
    }
}

// MARK: - Mocks

/// Reference-semantic box around a potentially copy-semantic value.
private class Box<T> {
    var wrapped: T
    init(_ wrapped: T) { self.wrapped = wrapped }
}

private func notImplemented() -> Never {
    owsFail("Not implemented!")
}

// MARK: MockGroupCallRecordManager

private class MockGroupCallRecordManager: GroupCallRecordManager {
    var createGroupCallStub: ((
        _ direction: CallRecord.CallDirection,
        _ groupCallStatus: CallRecord.CallStatus.GroupCallStatus
    ) -> Void)?
    func createGroupCallRecord(callId: UInt64, groupCallInteraction: OWSGroupCallMessage, groupCallInteractionRowId: Int64, groupThread: TSGroupThread, groupThreadRowId: Int64, callDirection: CallRecord.CallDirection, groupCallStatus: CallRecord.CallStatus.GroupCallStatus, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) -> CallRecord? {
        createGroupCallStub!(callDirection, groupCallStatus)
        XCTAssertFalse(shouldSendSyncMessage)
        return nil
    }

    var updateGroupCallStub: ((
        _ existingCallRecord: CallRecord,
        _ newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus
    ) -> Void)?
    func updateGroupCallRecord(groupThread: TSGroupThread, existingCallRecord: CallRecord, newCallDirection: CallRecord.CallDirection, newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) {
        updateGroupCallStub!(existingCallRecord, newGroupCallStatus)
        XCTAssertFalse(shouldSendSyncMessage)
    }

    func createOrUpdateCallRecord(callId: UInt64, groupThread: TSGroupThread, groupThreadRowId: Int64, callDirection: CallRecord.CallDirection, groupCallStatus: CallRecord.CallStatus.GroupCallStatus, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) {
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
    var markedAsReadCount = 0
    func markThingsAsReadForIncomingSyncMessage(
        callInteraction: TSInteraction & OWSReadTracking,
        thread: TSThread,
        syncMessageTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        markedAsReadCount += 1
    }
}
