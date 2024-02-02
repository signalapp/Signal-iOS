//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

private class MockGroupMemberUpdaterTemporaryShims: GroupMemberUpdaterTemporaryShims {
    var fetchableLatestInteractionTimestamps = [(
        groupThreadId: String,
        serviceId: String,
        interactionTimestamp: UInt64)
    ]()
    func fetchLatestInteractionTimestamp(
        groupThreadId: String,
        groupMemberAddress: SignalServiceAddress,
        transaction: DBReadTransaction
    ) -> UInt64? {
        let resultIndex = fetchableLatestInteractionTimestamps.firstIndex {
            $0.groupThreadId == groupThreadId && $0.serviceId == groupMemberAddress.serviceId?.serviceIdUppercaseString
        }
        let result = fetchableLatestInteractionTimestamps.remove(at: resultIndex!)
        return result.interactionTimestamp
    }

    var updatedGroupThreadIds = [String]()
    func didUpdateRecords(groupThreadId: String, transaction: DBWriteTransaction) {
        updatedGroupThreadIds.append(groupThreadId)
    }
}

class GroupMemberUpdaterTest: XCTestCase {
    private lazy var mockGroupMemberUpdaterTemporaryShims = MockGroupMemberUpdaterTemporaryShims()
    private lazy var mockGroupMemberStore = MockGroupMemberStore()
    private lazy var mockSignalServiceAddressCache = SignalServiceAddressCache()

    private lazy var groupMemberUpdater = GroupMemberUpdaterImpl(
        temporaryShims: mockGroupMemberUpdaterTemporaryShims,
        groupMemberStore: mockGroupMemberStore,
        signalServiceAddressCache: mockSignalServiceAddressCache
    )

    func testUpdateRecords() {
        let mockDB = MockDB()

        var oldGroupMembers = [(serviceId: String?, phoneNumber: String?, interactionTimestamp: UInt64)]()
        var groupThreadMembers = [(serviceId: String?, phoneNumber: String?)]()
        var signalRecipients = [(aci: String, pni: String?, phoneNumber: String)]()
        var newGroupMembers = [(serviceId: String?, phoneNumber: String?, interactionTimestamp: UInt64)]()
        var fetchableInteractionTimestamps = [(serviceId: String, interactionTimestamp: UInt64)]()

        // A bunch of ServiceIds might share a phone number in the source data. We
        // must ensure only one of these ends up with a phone number (and that it's
        // the right one that gets the phone number).
        oldGroupMembers.append(("00000000-0000-4000-8000-000000000001", nil, 1))
        oldGroupMembers.append(("00000000-0000-4000-8000-000000000002", nil, 2))
        signalRecipients.append(("00000000-0000-4000-8000-000000000002", nil, "+16505550100"))
        groupThreadMembers.append(("00000000-0000-4000-8000-000000000001", "+16505550100"))
        groupThreadMembers.append(("00000000-0000-4000-8000-000000000002", "+16505550100"))
        groupThreadMembers.append(("00000000-0000-4000-8000-000000000003", "+16505550100"))
        fetchableInteractionTimestamps.append(("00000000-0000-4000-8000-000000000003", 3))
        newGroupMembers.append(("00000000-0000-4000-8000-000000000001", nil, 1))
        newGroupMembers.append(("00000000-0000-4000-8000-000000000002", nil, 2))
        newGroupMembers.append(("00000000-0000-4000-8000-000000000003", nil, 3))

        // If two accounts are in a group and the phone number transfers between
        // them, we should also transfer it in the TSGroupMember table.
        oldGroupMembers.append(("00000000-0000-4000-8000-000000000004", nil, 4))
        oldGroupMembers.append(("00000000-0000-4000-8000-000000000005", nil, 5))
        signalRecipients.append(("00000000-0000-4000-8000-000000000005", nil, "+16505550101"))
        groupThreadMembers.append(("00000000-0000-4000-8000-000000000004", nil))
        groupThreadMembers.append(("00000000-0000-4000-8000-000000000005", "+16505550101"))
        newGroupMembers.append(("00000000-0000-4000-8000-000000000004", nil, 4))
        newGroupMembers.append(("00000000-0000-4000-8000-000000000005", nil, 5))

        // If a recipient has lost a phone number (ie no longer represented by a
        // SignalRecipient), we should remove it.
        oldGroupMembers.append(("00000000-0000-4000-8000-000000000006", nil, 6))
        groupThreadMembers.append(("00000000-0000-4000-8000-000000000006", "+16505550102"))
        newGroupMembers.append(("00000000-0000-4000-8000-000000000006", nil, 6))

        // If there's a phone number-only recipient, we should keep it around.
        oldGroupMembers.append((nil, "+16505550103", 7))
        groupThreadMembers.append((nil, "+16505550103"))
        newGroupMembers.append((nil, "+16505550103", 7))

        // If there's a group member that's already up to date, we should keep it
        // around.
        oldGroupMembers.append(("00000000-0000-4000-8000-000000000007", nil, 8))
        signalRecipients.append(("00000000-0000-4000-8000-000000000007", nil, "+16505550104"))
        groupThreadMembers.append(("00000000-0000-4000-8000-000000000007", "+16505550104"))
        newGroupMembers.append(("00000000-0000-4000-8000-000000000007", nil, 8))

        // If there's a new group member, we should fetch its latest interaction
        // timestamp.
        groupThreadMembers.append(("00000000-0000-4000-8000-000000000008", nil))
        fetchableInteractionTimestamps.append(("00000000-0000-4000-8000-000000000008", 9))
        newGroupMembers.append(("00000000-0000-4000-8000-000000000008", nil, 9))

        // If the ACI and PNI are both listed as group members, we should only
        // create a group member for the ACI one.
        signalRecipients.append(("00000000-0000-4000-8000-000000000009", "PNI:00000000-0000-4000-8000-00000000000A", "+16505550105"))
        groupThreadMembers.append(("00000000-0000-4000-8000-000000000009", "+16505550105"))
        groupThreadMembers.append(("PNI:00000000-0000-4000-8000-00000000000A", "+16505550105"))
        fetchableInteractionTimestamps.append(("00000000-0000-4000-8000-000000000009", 10))
        newGroupMembers.append(("00000000-0000-4000-8000-000000000009", nil, 10))

        // -- Set up the input data. --

        for signalRecipient in signalRecipients {
            mockSignalServiceAddressCache.updateRecipient(SignalRecipient(
                aci: Aci.constantForTesting(signalRecipient.aci),
                pni: signalRecipient.pni.map { Pni.constantForTesting($0) },
                phoneNumber: E164(signalRecipient.phoneNumber)
            ))
        }

        let groupThreadMemberAddresses = groupThreadMembers.map {
            makeAddress(serviceId: $0.serviceId, phoneNumber: $0.phoneNumber)
        }
        let groupThread = TSGroupThread.forUnitTest(groupMembers: groupThreadMemberAddresses)

        for fetchableInteractionTimestamp in fetchableInteractionTimestamps {
            mockGroupMemberUpdaterTemporaryShims.fetchableLatestInteractionTimestamps.append((
                groupThread.uniqueId,
                fetchableInteractionTimestamp.serviceId,
                fetchableInteractionTimestamp.interactionTimestamp
            ))
        }

        mockDB.write {
            for oldGroupMember in oldGroupMembers {
                mockGroupMemberStore.insert(
                    fullGroupMember: TSGroupMember(
                        address: NormalizedDatabaseRecordAddress(
                            serviceId: oldGroupMember.serviceId.map { try! ServiceId.parseFrom(serviceIdString: $0) },
                            phoneNumber: oldGroupMember.phoneNumber
                        )!,
                        groupThreadId: groupThread.uniqueId,
                        lastInteractionTimestamp: oldGroupMember.interactionTimestamp
                    ),
                    tx: $0
                )
            }
        }

        // -- Run the test. --

        mockDB.write {
            groupMemberUpdater.updateRecords(groupThread: groupThread, transaction: $0)
        }

        // -- Validate the output. --

        let groupMembers = mockDB.read {
            mockGroupMemberStore.sortedFullGroupMembers(in: groupThread.uniqueId, tx: $0)
        }

        XCTAssertEqual(groupMembers.count, newGroupMembers.count)
        for (actualGroupMember, expectedGroupMember) in zip(groupMembers, newGroupMembers.reversed()) {
            XCTAssertEqual(actualGroupMember.serviceId?.serviceIdUppercaseString, expectedGroupMember.serviceId, "\(expectedGroupMember)")
            XCTAssertEqual(actualGroupMember.phoneNumber, expectedGroupMember.phoneNumber, "\(expectedGroupMember)")
            XCTAssertEqual(actualGroupMember.lastInteractionTimestamp, expectedGroupMember.interactionTimestamp, "\(expectedGroupMember)")
        }

        XCTAssertEqual(mockGroupMemberUpdaterTemporaryShims.fetchableLatestInteractionTimestamps.count, 0)
        XCTAssertEqual(mockGroupMemberUpdaterTemporaryShims.updatedGroupThreadIds, [groupThread.uniqueId])

        // -- Make sure the algorithm is stable. --

        mockDB.write {
            groupMemberUpdater.updateRecords(groupThread: groupThread, transaction: $0)
        }

        // We just performed a redundant update, so we shouldn't notify anyone.
        XCTAssertEqual(mockGroupMemberUpdaterTemporaryShims.updatedGroupThreadIds, [groupThread.uniqueId])
    }

    // MARK: - Helpers

    private func makeAddress(serviceId: String?, phoneNumber: String?) -> SignalServiceAddress {
        return SignalServiceAddress(
            serviceId: serviceId.map { try! ServiceId.parseFrom(serviceIdString: $0) },
            phoneNumber: phoneNumber,
            cache: mockSignalServiceAddressCache,
            cachePolicy: .ignoreCache
        )
    }
}
