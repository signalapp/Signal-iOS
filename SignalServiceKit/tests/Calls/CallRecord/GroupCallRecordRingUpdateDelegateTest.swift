//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalRingRTC
import XCTest

@testable import SignalServiceKit

private typealias GroupCallStatus = CallRecord.CallStatus.GroupCallStatus

final class GroupCallRecordRingUpdateDelegateTest: XCTestCase {
    private var mockCallRecordStore: MockCallRecordStore!
    private var mockDB: MockDB!
    private var mockGroupCallRecordManager: MockGroupCallRecordManager!
    private var mockInteractionStore: MockInteractionStore!
    private var mockThreadStore: MockThreadStore!

    private var ringUpdateHandler: GroupCallRecordRingUpdateHandler!

    override func setUp() {
        mockCallRecordStore = MockCallRecordStore()
        mockDB = MockDB()
        mockGroupCallRecordManager = MockGroupCallRecordManager()
        mockInteractionStore = MockInteractionStore()
        mockThreadStore = MockThreadStore()

        self.ringUpdateHandler = GroupCallRecordRingUpdateHandler(
            callRecordStore: mockCallRecordStore,
            groupCallRecordManager: mockGroupCallRecordManager,
            interactionStore: mockInteractionStore,
            threadStore: mockThreadStore
        )
    }

    // MARK: - Existing call records

    /// We only expect to update existing call records for a ring update in
    /// certain situations. This test assembles all possible ring updates
    /// crossed with all possible "before" call record states to create a test
    /// case "premise", then simulates those ring updates to potentially
    /// "result" in a call record update and verifies the result is as expected.
    func testReceivedRingUpdateForExisting() {
        let groupThread: TSGroupThread = .forUnitTest()
        mockThreadStore.insertThread(groupThread)

        struct Premise: Hashable {
            let ringUpdate: RingUpdate
            let existingGroupCallStatus: GroupCallStatus

            init(
                _ ringUpdate: RingUpdate,
                _ existingGroupCallStatus: GroupCallStatus
            ) {
                self.ringUpdate = ringUpdate
                self.existingGroupCallStatus = existingGroupCallStatus
            }
        }

        struct Result {
            let expectedGroupCallStatus: GroupCallStatus
            let shouldExpectRingerAci: Bool

            init(_ expectedGroupCallStatus: GroupCallStatus, _ shouldExpectRingerAci: Bool) {
                self.expectedGroupCallStatus = expectedGroupCallStatus
                self.shouldExpectRingerAci = shouldExpectRingerAci
            }
        }

        let expectedUpdates: [Premise: Result] = [
            Premise(.requested, .generic): Result(.ringing, true),
            Premise(.requested, .joined): Result(.ringingAccepted, true),

            Premise(.expiredRing, .generic): Result(.ringingMissed, true),
            Premise(.expiredRing, .ringing): Result(.ringingMissed, true),
            Premise(.expiredRing, .joined): Result(.ringingAccepted, true),

            Premise(.cancelledByRinger, .generic): Result(.ringingMissed, true),
            Premise(.cancelledByRinger, .ringing): Result(.ringingMissed, true),
            Premise(.cancelledByRinger, .joined): Result(.ringingAccepted, true),

            Premise(.busyLocally, .generic): Result(.ringingMissed, true),
            Premise(.busyLocally, .ringing): Result(.ringingMissed, true),
            Premise(.busyLocally, .joined): Result(.ringingAccepted, true),

            Premise(.busyOnAnotherDevice, .generic): Result(.ringingMissed, false),
            Premise(.busyOnAnotherDevice, .ringing): Result(.ringingMissed, false),
            Premise(.busyOnAnotherDevice, .joined): Result(.ringingAccepted, false),

            Premise(.acceptedOnAnotherDevice, .generic): Result(.ringingAccepted, false),
            Premise(.acceptedOnAnotherDevice, .joined): Result(.ringingAccepted, false),
            Premise(.acceptedOnAnotherDevice, .ringing): Result(.ringingAccepted, false),
            Premise(.acceptedOnAnotherDevice, .ringingDeclined): Result(.ringingAccepted, false),
            Premise(.acceptedOnAnotherDevice, .ringingMissed): Result(.ringingAccepted, false),

            Premise(.declinedOnAnotherDevice, .generic): Result(.ringingDeclined, false),
            Premise(.declinedOnAnotherDevice, .joined): Result(.ringingAccepted, false),
            Premise(.declinedOnAnotherDevice, .ringing): Result(.ringingDeclined, false),
            Premise(.declinedOnAnotherDevice, .ringingMissed): Result(.ringingDeclined, false),
        ]

        var allPossiblePremises = [(Int64, Premise)]()

        mockDB.write { tx in
            for ringUpdate in allRingUpdateCases {
                for groupCallStatus in GroupCallStatus.allCases {
                    let ringId: Int64 = .maxRandom

                    allPossiblePremises.append((
                        ringId,
                        Premise(ringUpdate, groupCallStatus)
                    ))

                    _ = mockCallRecordStore.insert(
                        callRecord: CallRecord(
                            callId: callIdFromRingId(ringId),
                            interactionRowId: .maxRandom,
                            threadRowId: groupThread.sqliteRowId!,
                            callType: .groupCall,
                            callDirection: .incoming,
                            callStatus: .group(groupCallStatus),
                            groupCallRingerAci: nil,
                            callBeganTimestamp: .maxRandom
                        ),
                        tx: tx
                    )
                }
            }
        }

        for (ringId, premise) in allPossiblePremises {
            if let expectedResult = expectedUpdates[premise] {
                mockGroupCallRecordManager.updateStub = { newGroupCallStatus, newGroupCallRingerAci in
                    XCTAssertEqual(
                        newGroupCallStatus,
                        expectedResult.expectedGroupCallStatus
                    )

                    if expectedResult.shouldExpectRingerAci {
                        XCTAssertNotNil(newGroupCallRingerAci)
                    } else {
                        XCTAssertNil(newGroupCallRingerAci)
                    }
                }
            } else {
                mockGroupCallRecordManager.updateStub = { (_, _) in
                    XCTFail("Shouldn't have tried to update for premise: \(premise)!")
                }
            }

            mockDB.write { tx in
                ringUpdateHandler.didReceiveRingUpdate(
                    groupId: groupThread.groupId,
                    ringId: ringId,
                    ringUpdate: premise.ringUpdate,
                    ringUpdateSender: .randomForTesting(),
                    tx: tx
                )
            }
        }
    }

    func testReceivedRingUpdateForExistingOutgoingCallDoesNotUpdate() {
        let ringId: Int64 = .maxRandom

        let groupThread: TSGroupThread = .forUnitTest()
        mockThreadStore.insertThread(groupThread)

        mockDB.write { tx in
            _ = mockCallRecordStore.insert(
                callRecord: CallRecord(
                    callId: callIdFromRingId(ringId),
                    interactionRowId: .maxRandom,
                    threadRowId: groupThread.sqliteRowId!,
                    callType: .groupCall,
                    callDirection: .outgoing,
                    callStatus: .group(.ringingAccepted),
                    callBeganTimestamp: .maxRandom
                ),
                tx: tx
            )
        }

        mockGroupCallRecordManager.updateStub = { (_, _) in
            XCTFail("Shouldn't be trying to update for outgoing call record!")
        }

        mockDB.write { tx in
            ringUpdateHandler.didReceiveRingUpdate(
                groupId: groupThread.groupId,
                ringId: ringId,
                ringUpdate: .expiredRing,
                ringUpdateSender: .randomForTesting(),
                tx: tx
            )
        }
    }

    // MARK: - Creating new call records

    func testReceivedRingUpdateForNewCallRecord() {
        let groupThread: TSGroupThread = .forUnitTest()
        mockThreadStore.insertThread(groupThread)

        struct Result {
            let expectedGroupCallStatus: GroupCallStatus
            let shouldExpectRingerAci: Bool

            init(_ expectedGroupCallStatus: GroupCallStatus, _ shouldExpectRingerAci: Bool) {
                self.expectedGroupCallStatus = expectedGroupCallStatus
                self.shouldExpectRingerAci = shouldExpectRingerAci
            }
        }

        let testCases: [RingUpdate: Result] = [
            .requested: Result(.ringing, true),
            .expiredRing: Result(.ringingMissed, true),
            .cancelledByRinger: Result(.ringingMissed, true),
            .busyLocally: Result(.ringingMissed, true),
            .busyOnAnotherDevice: Result(.ringingMissed, false),
            .acceptedOnAnotherDevice: Result(.ringingAccepted, false),
            .declinedOnAnotherDevice: Result(.ringingDeclined, false)
        ]

        for (idx, ringUpdate) in allRingUpdateCases.enumerated() {
            let expectedResult = testCases[ringUpdate]!

            mockGroupCallRecordManager.createStub = { groupCallStatus, groupCallRingerAci in
                XCTAssertEqual(groupCallStatus, expectedResult.expectedGroupCallStatus)

                if expectedResult.shouldExpectRingerAci {
                    XCTAssertNotNil(groupCallRingerAci)
                } else {
                    XCTAssertNil(groupCallRingerAci)
                }
            }

            mockDB.write { tx in
                ringUpdateHandler.didReceiveRingUpdate(
                    groupId: groupThread.groupId,
                    ringId: .maxRandom,
                    ringUpdate: ringUpdate,
                    ringUpdateSender: .randomForTesting(),
                    tx: tx
                )
            }

            XCTAssertEqual(mockInteractionStore.insertedInteractions.count, idx + 1)
        }
    }

    // MARK: -

    private var allRingUpdateCases: [RingUpdate] {
        var ringUpdates = [RingUpdate]()

        var rawValue: Int32 = 0
        while let ringUpdate = RingUpdate(rawValue: rawValue) {
            ringUpdates.append(ringUpdate)
            rawValue += 1
        }

        return ringUpdates
    }
}

// MARK: - Mocks

private func notImplemented() -> Never { return owsFail("Not implemented!") }

// MARK: MockGroupCallRecordManager

private class MockGroupCallRecordManager: GroupCallRecordManager {
    var createStub: ((
        _ groupCallStatus: GroupCallStatus,
        _ groupCallRingerAci: Aci?
    ) -> Void)?
    func createGroupCallRecord(callId: UInt64, groupCallInteraction: OWSGroupCallMessage, groupCallInteractionRowId: Int64, groupThread: TSGroupThread, groupThreadRowId: Int64, callDirection: CallRecord.CallDirection, groupCallStatus: CallRecord.CallStatus.GroupCallStatus, groupCallRingerAci: Aci?, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) -> CallRecord? {
        createStub!(groupCallStatus, groupCallRingerAci)
        return nil
    }

    var updateStub: ((
        _ newGroupCallStatus: GroupCallStatus,
        _ newGroupCallRingerAci: Aci?
    ) -> Void)?
    func updateGroupCallRecord(groupThread: TSGroupThread, existingCallRecord: CallRecord, newCallDirection: CallRecord.CallDirection, newGroupCallStatus: CallRecord.CallStatus.GroupCallStatus, newGroupCallRingerAci: Aci?, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) {
        updateStub!(newGroupCallStatus, newGroupCallRingerAci)
    }

    func createOrUpdateCallRecord(callId: UInt64, groupThread: TSGroupThread, groupThreadRowId: Int64, callDirection: CallRecord.CallDirection, groupCallStatus: CallRecord.CallStatus.GroupCallStatus, callEventTimestamp: UInt64, shouldSendSyncMessage: Bool, tx: DBWriteTransaction) { notImplemented() }
    func updateCallBeganTimestampIfEarlier(existingCallRecord: CallRecord, callEventTimestamp: UInt64, tx: DBWriteTransaction) { notImplemented() }
}
