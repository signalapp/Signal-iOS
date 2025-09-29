//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class IncomingCallEventSyncMessageManagerTest: XCTestCase {
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockCallRecordDeleteManager: MockCallRecordDeleteManager!
    private var mockGroupCallRecordManager: MockGroupCallRecordManager!
    private var mockIndividualCallRecordManager: MockIndividualCallRecordManager!
    private var mockInteractionDeleteManager: MockInteractionDeleteManager!
    private var mockInteractionStore: MockInteractionStore!
    private var mockMarkAsReadShims: MockMarkAsReadShims!
    private var mockRecipientDatabaseTable: RecipientDatabaseTable!
    private var mockThreadStore: MockThreadStore!

    private var mockDB = InMemoryDB()
    private var incomingSyncMessageManager: IncomingCallEventSyncMessageManagerImpl!

    override func setUp() {
        mockCallRecordStore = MockCallRecordStore()
        mockCallRecordDeleteManager = MockCallRecordDeleteManager()
        mockGroupCallRecordManager = MockGroupCallRecordManager()
        mockIndividualCallRecordManager = MockIndividualCallRecordManager()
        mockInteractionDeleteManager = MockInteractionDeleteManager()
        mockInteractionStore = MockInteractionStore()
        mockMarkAsReadShims = MockMarkAsReadShims()
        mockRecipientDatabaseTable = RecipientDatabaseTable()
        mockThreadStore = MockThreadStore()

        mockCallRecordDeleteManager.markCallAsDeletedMock = { _, _ in
            XCTFail("Shouldn't be deleting!")
        }
        mockInteractionDeleteManager.deleteAlongsideCallRecordsMock = { _, _ in
            XCTFail("Shouldn't be deleting!")
        }

        incomingSyncMessageManager = IncomingCallEventSyncMessageManagerImpl(
            adHocCallRecordManager: MockAdHocCallRecordManager(),
            callLinkStore: MockCallLinkRecordStore(),
            callRecordStore: mockCallRecordStore,
            callRecordDeleteManager: mockCallRecordDeleteManager,
            groupCallRecordManager: mockGroupCallRecordManager,
            individualCallRecordManager: mockIndividualCallRecordManager,
            interactionDeleteManager: mockInteractionDeleteManager,
            interactionStore: mockInteractionStore,
            markAsReadShims: mockMarkAsReadShims,
            recipientDatabaseTable: mockRecipientDatabaseTable,
            threadStore: mockThreadStore
        )
    }

    // MARK: - Deleted calls

    func testDeleteIndividualCall() {
        let (contactServiceId, callId) = insertIndividualCallRecord()

        /// If the call record in question was already deleted, do nothing. (The
        /// delete manager mocks are set to blow up if called.)
        mockDB.write { tx in
            mockCallRecordStore.fetchMock = { .matchDeleted }
            defer { mockCallRecordStore.fetchMock = nil }

            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .individualThread(serviceId: contactServiceId, isVideo: false),
                    callId: callId.adjacent,
                    callTimestamp: .maxRandom,
                    callEvent: .deleted,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// If the call record in question is present, it should be deleted.
        mockDB.write { tx in
            var didDeleteModels = false
            mockInteractionDeleteManager.deleteAlongsideCallRecordsMock = { _, sideEffects in
                XCTAssertEqual(sideEffects.associatedCallDelete, .localDeleteOnly)
                didDeleteModels = true
            }

            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .individualThread(serviceId: contactServiceId, isVideo: false),
                    callId: callId,
                    callTimestamp: .maxRandom,
                    callEvent: .deleted,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )

            XCTAssertTrue(didDeleteModels)
        }

        /// If the call record in question does not exist, we should mark it as
        /// deleted prophylactically.
        mockDB.write { tx in
            var didCallMock = false
            mockCallRecordDeleteManager.markCallAsDeletedMock = { _, _ in
                didCallMock = true
            }

            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .individualThread(serviceId: contactServiceId, isVideo: false),
                    callId: callId.adjacent,
                    callTimestamp: .maxRandom,
                    callEvent: .deleted,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )

            XCTAssertTrue(didCallMock)
        }
    }

    func testDeleteGroupCall() {
        let (existingCallRecord, groupId) = createGroupCallRecord(
            callDirection: .incoming,
            groupCallStatus: .generic
        )

        /// If the call record in question was already deleted, do nothing. (The
        /// delete manager mocks are set to blow up if called.)
        mockDB.write { tx in
            mockCallRecordStore.fetchMock = { .matchDeleted }
            defer { mockCallRecordStore.fetchMock = nil }

            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: groupId),
                    callId: existingCallRecord.callId.adjacent,
                    callTimestamp: .maxRandom,
                    callEvent: .deleted,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// If the call record in question is present, it should be deleted.
        mockDB.write { tx in
            var didDeleteModels = false
            mockInteractionDeleteManager.deleteAlongsideCallRecordsMock = { _, sideEffects in
                XCTAssertEqual(sideEffects.associatedCallDelete, .localDeleteOnly)
                didDeleteModels = true
            }

            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: groupId),
                    callId: existingCallRecord.callId,
                    callTimestamp: .maxRandom,
                    callEvent: .deleted,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )

            XCTAssertTrue(didDeleteModels)
        }

        /// If the call record in question does not exist, we should mark it as
        /// deleted prophylactically.
        mockDB.write { tx in
            var didCallMock = false
            mockCallRecordDeleteManager.markCallAsDeletedMock = { _, _ in
                didCallMock = true
            }

            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: groupId),
                    callId: existingCallRecord.callId.adjacent,
                    callTimestamp: .maxRandom,
                    callEvent: .deleted,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )

            XCTAssertTrue(didCallMock)
        }
    }

    // MARK: - Individual calls

    private func insertIndividualCallRecord(
        callType: RPRecentCallType = .outgoingMissed,
        individualCallStatus: CallRecord.CallStatus.IndividualCallStatus = .notAccepted
    ) -> (ServiceId, UInt64) {
        let callId = UInt64.maxRandom

        let contactAddress = SignalServiceAddress.isolatedRandomForTesting()
        let thread = TSContactThread(contactAddress: contactAddress)
        mockThreadStore.insertThread(thread)
        let threadRowId = thread.sqliteRowId!

        let contactServiceId = contactAddress.aci!
        let contactRecipient = SignalRecipient(aci: contactServiceId, pni: nil, phoneNumber: nil)

        let interaction = TSCall(
            callType: callType,
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
            callStatus: .individual(individualCallStatus),
            callBeganTimestamp: .maxRandomInt64Compat
        )

        mockDB.write { tx in
            mockCallRecordStore.insert(callRecord: callRecord, tx: tx)
        }

        return (contactServiceId, callId)
    }

    func testUpdatesIndividualCallIfExists() {
        let (contactServiceId, callId) = insertIndividualCallRecord()

        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .individualThread(serviceId: contactServiceId, isVideo: false),
                    callId: callId,
                    callTimestamp: .maxRandom,
                    callEvent: .accepted,
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
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .individualThread(serviceId: contactServiceId, isVideo: false),
                    callId: callId,
                    callTimestamp: .maxRandom,
                    callEvent: .accepted,
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

    func testIgnoresIndividualCallIfRecentlyDeleted() {
        let contactAddress = SignalServiceAddress.isolatedRandomForTesting()
        let contactServiceId = contactAddress.aci!

        let contactThread = TSContactThread(contactAddress: contactAddress)
        mockThreadStore.insertThread(contactThread)

        mockDB.write { tx in
            let recipient = SignalRecipient(aci: contactServiceId, pni: nil, phoneNumber: nil)
            mockRecipientDatabaseTable.insertRecipient(recipient, transaction: tx)
        }

        mockCallRecordStore.fetchMock = { .matchDeleted }

        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .individualThread(serviceId: contactServiceId, isVideo: false),
                    callId: .maxRandom,
                    callTimestamp: .maxRandom,
                    callEvent: .accepted,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(mockInteractionStore.insertedInteractions, [])
        XCTAssertEqual(mockIndividualCallRecordManager.createdRecords, [])
        XCTAssertEqual(mockIndividualCallRecordManager.updatedRecords, [])
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 0)
    }

    // MARK: - Group calls

    private func createGroupCallRecord(
        groupId: UInt8 = 0,
        callDirection: CallRecord.CallDirection,
        groupCallStatus: CallRecord.CallStatus.GroupCallStatus
    ) -> (CallRecord, Data) {
        let thread = TSGroupThread.forUnitTest(groupId: groupId)

        let (_, interactionRowId) = mockDB.write { tx in
            mockThreadStore.insertThread(thread)
            return mockInteractionStore.insertGroupCallInteraction(
                groupThread: thread,
                callEventTimestamp: .maxRandom,
                tx: tx
            )
        }

        let existingCallRecord = CallRecord(
            callId: .maxRandom,
            interactionRowId: interactionRowId,
            threadRowId: thread.sqliteRowId!,
            callType: .groupCall,
            callDirection: callDirection,
            callStatus: .group(groupCallStatus),
            callBeganTimestamp: .maxRandom
        )

        mockDB.write { tx in
            mockCallRecordStore.insert(callRecord: existingCallRecord, tx: tx)
        }

        return (existingCallRecord, thread.groupId)
    }

    func testUpdatesGroupCall_joined() {
        var updateCount = 0
        mockGroupCallRecordManager.updateGroupCallStub = { _, _, newGroupCallStatus in
            updateCount += 1
            XCTAssertEqual(newGroupCallStatus, .joined)
        }

        let (existingCallRecord, groupId) = createGroupCallRecord(
            callDirection: .incoming, groupCallStatus: .generic
        )

        /// A first sync message should get us to the joined state.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: groupId),
                    callId: existingCallRecord.callId,
                    callTimestamp: existingCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// A second sync message keeps us in the joined state.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: groupId),
                    callId: existingCallRecord.callId,
                    callTimestamp: existingCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
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
        mockGroupCallRecordManager.updateGroupCallStub = { _, _, newGroupCallStatus in
            updateCount += 1
            XCTAssertEqual(newGroupCallStatus, .ringingAccepted)
        }

        let (missedCallRecord, missedGroupId) = createGroupCallRecord(
            groupId: 1, callDirection: .incoming, groupCallStatus: .ringingMissed
        )

        let (declinedCallRecord, declinedGroupId) = createGroupCallRecord(
            groupId: 2, callDirection: .incoming, groupCallStatus: .ringingDeclined
        )

        /// Updating a ringing-missed record makes it ringing-accepted.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: missedGroupId),
                    callId: missedCallRecord.callId,
                    callTimestamp: missedCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating a ringing-declined record makes it ringing-accepted.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: declinedGroupId),
                    callId: declinedCallRecord.callId,
                    callTimestamp: declinedCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating an already rining-accepted record doesn't change the state.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: declinedGroupId),
                    callId: declinedCallRecord.callId,
                    callTimestamp: declinedCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
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
        mockGroupCallRecordManager.updateGroupCallStub = { _, _, newGroupCallStatus in
            updateCount += 1
            XCTAssertEqual(newGroupCallStatus, .ringingDeclined)
        }

        let (genericCallRecord, genericGroupId) = createGroupCallRecord(
            groupId: 1, callDirection: .incoming, groupCallStatus: .generic
        )

        let (missedCallRecord, missedGroupId) = createGroupCallRecord(
            groupId: 2, callDirection: .incoming, groupCallStatus: .ringingMissed
        )

        /// Updating a generic record makes it ringing-declined.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: genericGroupId),
                    callId: genericCallRecord.callId,
                    callTimestamp: genericCallRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating a ringing-missed record makes it ringing-declined.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: missedGroupId),
                    callId: missedCallRecord.callId,
                    callTimestamp: missedCallRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating an already-declined record keeps it declined.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: missedGroupId),
                    callId: missedCallRecord.callId,
                    callTimestamp: missedCallRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
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
        mockGroupCallRecordManager.updateGroupCallStub = { _, _, newGroupCallStatus in
            updateCount += 1
            XCTAssertEqual(newGroupCallStatus, .ringingAccepted)
        }

        let (joinedCallRecord, joinedGroupId) = createGroupCallRecord(
            groupId: 1, callDirection: .incoming, groupCallStatus: .joined
        )

        let (acceptedCallRecord, acceptedGroupId) = createGroupCallRecord(
            groupId: 2, callDirection: .incoming, groupCallStatus: .ringingAccepted
        )

        /// Updating a joined record makes it ringing-accepted.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: joinedGroupId),
                    callId: joinedCallRecord.callId,
                    callTimestamp: joinedCallRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating a ringing-accepted record keeps it ringing-accepted.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: acceptedGroupId),
                    callId: acceptedCallRecord.callId,
                    callTimestamp: acceptedCallRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
                    callDirection: .incoming
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 2)
    }

    func testUpdatesGroupCall_outgoingAccepted() {
        var updateCount = 0
        mockGroupCallRecordManager.updateGroupCallStub = { _, newCallDirection, newGroupCallStatus in
            updateCount += 1
            XCTAssertEqual(newCallDirection, .outgoing)
            XCTAssertEqual(newGroupCallStatus, .ringingAccepted)
        }

        let (genericCallRecord, genericGroupId) = createGroupCallRecord(
            groupId: 1, callDirection: .incoming, groupCallStatus: .generic
        )

        let (joinedCallRecord, joinedGroupId) = createGroupCallRecord(
            groupId: 2, callDirection: .incoming, groupCallStatus: .joined
        )

        /// Updating a generic record reassigns the direction and status.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: genericGroupId),
                    callId: genericCallRecord.callId,
                    callTimestamp: genericCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        /// Updating a joined record reassigns the direction and status.
        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: joinedGroupId),
                    callId: joinedCallRecord.callId,
                    callTimestamp: joinedCallRecord.callBeganTimestamp - 5,
                    callEvent: .accepted,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(updateCount, 2)
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 2)
    }

    /// We should never receive a sync message for an outgoing, not-accepted
    /// call. If we do, we should ignore it.
    func testUpdatesGroupCall_outgoingNotAcceptedIsIgnored() {
        mockGroupCallRecordManager.updateGroupCallStub = { (_, _, _) in
            XCTFail("Should never be updating!")
        }

        /// We treat all outgoing group rings as accepted because we don't track
        /// their ring state.
        let (callRecord, groupId) = createGroupCallRecord(
            callDirection: .incoming, groupCallStatus: .generic
        )

        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: groupId),
                    callId: callRecord.callId,
                    callTimestamp: callRecord.callBeganTimestamp - 5,
                    callEvent: .notAccepted,
                    callDirection: .outgoing
                ),
                syncMessageTimestamp: .maxRandom,
                tx: tx
            )
        }

        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 0)
    }

    func testIgnoresGroupCallIfRecordRecentlyDeleted() {
        mockGroupCallRecordManager.updateGroupCallStub = { (_, _, _) in
            XCTFail("Should never be updating!")
        }

        mockCallRecordStore.fetchMock = { .matchDeleted }

        mockDB.write { tx in
            incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                incomingSyncMessage: IncomingCallEventSyncMessageParams(
                    conversation: .groupThread(groupId: Data()),
                    callId: .maxRandom,
                    callTimestamp: .maxRandom,
                    callEvent: .notAccepted,
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
            event: IncomingCallEventSyncMessageParams.CallEvent
        ) {
            mockDB.write { tx in
                incomingSyncMessageManager.createOrUpdateRecordForIncomingSyncMessage(
                    incomingSyncMessage: IncomingCallEventSyncMessageParams(
                        conversation: .groupThread(groupId: groupThread.groupId),
                        callId: .maxRandom,
                        callTimestamp: .maxRandom,
                        callEvent: event,
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

        expectedGroupCallStatus.wrapped = (.incoming, .ringingDeclined)
        simulateIncoming(direction: .incoming, event: .notAccepted)

        XCTAssertEqual(createCount, 3)
        XCTAssertEqual(mockInteractionStore.insertedInteractions.count, 3)
        XCTAssertEqual(mockMarkAsReadShims.markedAsReadCount, 3)
    }
}

// MARK: -

private extension UInt64 {
    /// An adjacent value to this one. Most importantly, will never be equal to
    /// this value.
    var adjacent: UInt64 {
        if self == .max {
            return self - 1
        }

        return self + 1
    }
}

// MARK: - Mocks

/// Reference-semantic box around a potentially copy-semantic value.
final private class Box<T> {
    var wrapped: T
    init(_ wrapped: T) { self.wrapped = wrapped }
}

private func notImplemented() -> Never {
    owsFail("Not implemented!")
}

// MARK: MockGroupCallRecordManager

final private class MockGroupCallRecordManager: GroupCallRecordManager {
    var createGroupCallStub: ((
        _ direction: CallRecord.CallDirection,
        _ groupCallStatus: CallRecord.CallStatus.GroupCallStatus
    ) -> Void)?
    func createGroupCallRecord(callId: UInt64, groupCallInteraction: OWSGroupCallMessage, groupCallInteractionRowId: Int64, groupThreadRowId: Int64, callDirection: CallRecord.CallDirection, groupCallStatus: CallRecord.CallStatus.GroupCallStatus, groupCallRingerAci: Aci?, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) -> CallRecord {
        createGroupCallStub!(callDirection, groupCallStatus)
        XCTAssertFalse(shouldSendSyncMessage)
        return CallRecord(callId: callId, interactionRowId: groupCallInteractionRowId, threadRowId: groupThreadRowId, callType: .groupCall, callDirection: callDirection, callStatus: .group(groupCallStatus), callBeganTimestamp: callEventTimestamp)
    }

    var updateGroupCallStub: ((
        _ existingCallRecord: CallRecord,
        _ newCallDirection: CallRecord.CallDirection,
        _ newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus
    ) -> Void)?
    func updateGroupCallRecord(existingCallRecord: CallRecord, newCallDirection: CallRecord.CallDirection, newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus, newGroupCallRingerAci: Aci?, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) {
        updateGroupCallStub!(existingCallRecord, newCallDirection, newGroupCallStatus)
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

final private class MockIndividualCallRecordManager: IndividualCallRecordManager {
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
        callEventTimestamp: UInt64,
        shouldSendSyncMessage: Bool,
        tx: DBWriteTransaction
    ) -> CallRecord {
        createdRecords.append(callId)

        return CallRecord(callId: callId, interactionRowId: individualCallInteractionRowId, threadRowId: contactThreadRowId, callType: callType, callDirection: callDirection, callStatus: .individual(individualCallStatus), callBeganTimestamp: callEventTimestamp)
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

final private class MockMarkAsReadShims: IncomingCallEventSyncMessageManagerImpl.Shims.MarkAsRead {
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
