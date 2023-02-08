//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class SignalRecipientTest: SSKBaseTestSwift {

    lazy var localAddress = CommonGenerator.address()

    override func setUp() {
        super.setUp()

        tsAccountManager.registerForTests(withLocalNumber: localAddress.phoneNumber!, uuid: localAddress.uuid!)
    }

    func testSelfRecipientWithExistingRecord() {
        write { transaction in
            createHighTrustRecipient(for: self.localAddress, transaction: transaction)
            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(self.localAddress, transaction: transaction))
        }
    }

    func testRecipientWithExistingRecord() {
        let recipient = CommonGenerator.address()
        write { transaction in
            createHighTrustRecipient(for: recipient, transaction: transaction)
            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(recipient, transaction: transaction))
        }
    }

    // MARK: - Low Trust

    func testLowTrustPhoneNumberOnly() {
        // Phone number only recipients are recorded
        let recipient = CommonGenerator.address(hasUUID: false)
        write { transaction in
            createLowTrustRecipient(for: recipient, transaction: transaction)
            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(recipient, transaction: transaction))
        }
    }

    func testLowTrustUUIDOnly() {
        // UUID only recipients are recorded
        let recipient = CommonGenerator.address(hasPhoneNumber: false)
        write { transaction in
            createLowTrustRecipient(for: recipient, transaction: transaction)
            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(recipient, transaction: transaction))
        }
    }

    func testLowTrustFullyQualified() {
        // Fully qualified addresses only record their UUID

        let recipientAddress = CommonGenerator.address()
        let recipientAddressWithoutUUID = SignalServiceAddress(phoneNumber: recipientAddress.phoneNumber!)

        XCTAssertNil(recipientAddressWithoutUUID.uuid)

        write { transaction in
            let recipient = createLowTrustRecipient(for: recipientAddress, transaction: transaction)

            // The impartial address is *not* automatically filled
            // after marking the complete address as registered.
            XCTAssertNil(recipientAddressWithoutUUID.uuid)

            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(
                recipientAddress,
                transaction: transaction
            ))
            XCTAssertFalse(SignalRecipient.isRegisteredRecipient(
                recipientAddressWithoutUUID,
                transaction: transaction
            ))

            XCTAssertEqual(recipient.recipientUUID, recipientAddress.uuidString)
            XCTAssertNil(recipient.recipientPhoneNumber)
        }
    }

    // MARK: - High Trust

    func testHighTrustPhoneNumberOnly() {
        // Phone number only recipients are recorded
        let recipient = CommonGenerator.address(hasUUID: false)
        write { transaction in
            createHighTrustRecipient(for: recipient, transaction: transaction)
            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(recipient, transaction: transaction))
        }
    }

    func testHighTrustUUIDOnly() {
        // UUID only recipients are recorded
        let recipient = CommonGenerator.address(hasPhoneNumber: false)
        write { transaction in
            createHighTrustRecipient(for: recipient, transaction: transaction)
            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(recipient, transaction: transaction))
        }
    }

    func testHighTrustFullyQualified() {
        // Fully qualified addresses are recorded in their entirety

        let recipientAddress = CommonGenerator.address()
        let recipientAddressWithoutUUID = SignalServiceAddress(phoneNumber: recipientAddress.phoneNumber!)

        XCTAssertNil(recipientAddressWithoutUUID.uuid)

        write { transaction in
            let recipient = createHighTrustRecipient(for: recipientAddress, transaction: transaction)

            // The impartial address is automatically filled
            // after marking the complete address as registered.
            XCTAssertEqual(recipientAddressWithoutUUID.uuid, recipientAddress.uuid)

            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(
                recipientAddress,
                transaction: transaction
            ))
            XCTAssertTrue(SignalRecipient.isRegisteredRecipient(
                recipientAddressWithoutUUID,
                transaction: transaction
            ))

            XCTAssertEqual(recipient.recipientUUID, recipientAddress.uuidString)
            XCTAssertEqual(recipient.recipientPhoneNumber, recipientAddress.phoneNumber)
        }
    }

    func testHighTrustMergeWithInvestedPhoneNumber() {
        // If there is a UUID only contact and a phone number only contact,
        // and then we later find out they are the same user we must merge
        // the two recipients together.
        let uuidOnlyAddress = CommonGenerator.address(hasPhoneNumber: false)
        let phoneNumberOnlyAddress = CommonGenerator.address(hasUUID: false)
        let address = SignalServiceAddress(uuid: uuidOnlyAddress.uuid!, phoneNumber: phoneNumberOnlyAddress.phoneNumber!)

        write { transaction in
            let uuidRecipient = createHighTrustRecipient(for: uuidOnlyAddress, transaction: transaction)
            let phoneNumberRecipient = createHighTrustRecipient(for: phoneNumberOnlyAddress, transaction: transaction)
            let mergedRecipient = createHighTrustRecipient(for: address, transaction: transaction)

            // TODO: test this more thoroughly. right now just confirming we prefer
            // the UUID recipient when no other info is available

            XCTAssertEqual(mergedRecipient.uniqueId, uuidRecipient.uniqueId)
        }
    }

    func testHighTrustPhoneNumberChange() {
        let oldAddress = CommonGenerator.address()

        write { transaction in
            let oldThread = TSContactThread.getOrCreateThread(
                withContactAddress: oldAddress,
                transaction: transaction
            )

            let messageBuilder = TSIncomingMessageBuilder(
                thread: oldThread,
                authorAddress: oldAddress,
                messageBody: "Test 123"
            )
            let oldMessage = messageBuilder.build()
            oldMessage.anyInsert(transaction: transaction)

            let oldProfile = OWSUserProfile.getOrBuild(
                for: oldAddress,
                   transaction: transaction
            )
            // TODO: It's weird to me that getOrBuild doesn't
            // save the profile if it builds it. Maybe this is
            // a bug?
            oldProfile.anyInsert(transaction: transaction)

            let oldAccount = SignalAccount(address: oldAddress)
            oldAccount.anyInsert(transaction: transaction)
            createHighTrustRecipient(for: oldAddress, transaction: transaction)

            let newAddress = SignalServiceAddress(uuid: oldAddress.uuid!, phoneNumber: CommonGenerator.e164())
            createHighTrustRecipient(for: newAddress, transaction: transaction)

            let newThread = TSContactThread.getOrCreateThread(
                withContactAddress: newAddress,
                transaction: transaction
            )
            let newMessage = TSIncomingMessage.anyFetchIncomingMessage(
                uniqueId: oldMessage.uniqueId,
                transaction: transaction
            )!
            let newProfile = OWSUserProfile.getOrBuild(
                for: newAddress,
                   transaction: transaction
            )
            let newAccount = SignalAccount.anyFetch(
                uniqueId: oldAccount.uniqueId,
                transaction: transaction
            )!

            // We maintain the same thread, profile, interactions, etc.
            // after the phone number change. They are updated to reflect
            // the new address.
            XCTAssertEqual(oldAddress.phoneNumber, newAddress.phoneNumber)
            XCTAssertEqual(oldAddress.uuid, newAddress.uuid)

            XCTAssertEqual(oldThread.uniqueId, newThread.uniqueId)
            XCTAssertNotEqual(oldThread.contactPhoneNumber, newThread.contactPhoneNumber)
            XCTAssertEqual(newAddress, newThread.contactAddress)

            XCTAssertEqual(oldMessage.uniqueId, newMessage.uniqueId)
            XCTAssertNotEqual(oldMessage.authorPhoneNumber, newMessage.authorPhoneNumber)
            XCTAssertEqual(newAddress, newMessage.authorAddress)

            XCTAssertEqual(oldProfile.uniqueId, newProfile.uniqueId)
            XCTAssertNotEqual(oldProfile.recipientPhoneNumber, newProfile.recipientPhoneNumber)
            XCTAssertEqual(newAddress, newProfile.address)

            XCTAssertEqual(oldAccount.uniqueId, newAccount.uniqueId)
            XCTAssertNotEqual(oldAccount.recipientPhoneNumber, newAccount.recipientPhoneNumber)
            XCTAssertEqual(newAddress, newAccount.recipientAddress)
        }
    }

    func testHighTrustUUIDChange() {
        let oldAddress = CommonGenerator.address()

        write { transaction in
            let oldThread = TSContactThread.getOrCreateThread(
                withContactAddress: oldAddress,
                transaction: transaction
            )

            let messageBuilder = TSIncomingMessageBuilder(
                thread: oldThread,
                authorAddress: oldAddress,
                messageBody: "Test 123"
            )
            let oldMessage = messageBuilder.build()
            oldMessage.anyInsert(transaction: transaction)

            let oldProfile = OWSUserProfile.getOrBuild(
                for: oldAddress,
                   transaction: transaction
            )
            // TODO: It's weird to me that getOrBuild doesn't
            // save the profile if it builds it. Maybe this is
            // a bug?
            oldProfile.anyInsert(transaction: transaction)

            let oldAccount = SignalAccount(address: oldAddress)
            oldAccount.anyInsert(transaction: transaction)
            createHighTrustRecipient(for: oldAddress, transaction: transaction)

            let newAddress = SignalServiceAddress(uuid: UUID(), phoneNumber: oldAddress.phoneNumber!)
            createHighTrustRecipient(for: newAddress, transaction: transaction)

            let newThread = TSContactThread.getOrCreateThread(
                withContactAddress: newAddress,
                transaction: transaction
            )
            let newMessage = TSIncomingMessage.anyFetchIncomingMessage(
                uniqueId: oldMessage.uniqueId,
                transaction: transaction
            )!
            let newProfile = OWSUserProfile.getOrBuild(
                for: newAddress,
                   transaction: transaction
            )
            let newAccount = SignalAccount.anyFetch(
                uniqueId: oldAccount.uniqueId,
                transaction: transaction
            )!

            // When the UUID changes, we treat it as a new account. Old data
            // should remain associated with the old UUID, but have the phone
            // number stripped.
            XCTAssertNil(oldAddress.phoneNumber)
            XCTAssertNotEqual(oldAddress.phoneNumber, newAddress.phoneNumber)
            XCTAssertNotEqual(oldAddress.uuid, newAddress.uuid)

            oldThread.anyReload(transaction: transaction)
            XCTAssertNotEqual(oldThread.uniqueId, newThread.uniqueId)
            XCTAssertNil(oldThread.contactPhoneNumber)
            XCTAssertEqual(newAddress, newThread.contactAddress)
            XCTAssertNotEqual(newAddress, oldThread.contactAddress)

            XCTAssertEqual(oldMessage.uniqueId, newMessage.uniqueId)
            XCTAssertNil(newMessage.authorPhoneNumber)
            XCTAssertNotEqual(newAddress, newMessage.authorAddress)

            oldProfile.anyReload(transaction: transaction)
            XCTAssertNotEqual(oldProfile.uniqueId, newProfile.uniqueId)
            XCTAssertNil(oldProfile.recipientPhoneNumber)
            XCTAssertEqual(newAddress, newProfile.address)
            XCTAssertNotEqual(newAddress, oldProfile.address)

            XCTAssertEqual(oldAccount.uniqueId, newAccount.uniqueId)
            XCTAssertNil(newAccount.recipientPhoneNumber)
            XCTAssertNotEqual(newAddress, newAccount.recipientAddress)
        }
    }

    // This tests an edge case around uuid<->phone number mapping changes.
    //
    // * There _is_ a SignalRecipient with (u1, p1).
    // * There _is no_ SignalRecipient with u1 or p2.
    // * There is a group g1.
    // * There is a TSGroupMember with (u1, p1, g1).
    // * There is a TSGroupMember with (u2, p2, g1).
    // * u1 becomes associated with p2.
    //
    // Therefore:
    //
    // * p2 must be mapped from u2 -> u1, but there is no existing phoneNumberInstance for p2.
    // * SignalRecipient.clearDBMappings(forPhoneNumber:) must clean up p2 before
    //   SignalRecipient.changePhoneNumber() is called on uuidInstance for u1.
    // * Otherwise we'll end up with two TSGroupMembers with (p2, g1) which violates
    //   a uniqueness constraint.
    func testDBMappingsEdgeCase1() {
        let uuid1 = UUID()
        let phoneNumber1 = CommonGenerator.e164()
        let uuid2 = UUID()
        let phoneNumber2 = CommonGenerator.e164()

        write { transaction in
            // There are TSGroupMember instances indicating that both users 1 & 2 are members of the same group.
            let groupThreadFactory = GroupThreadFactory()
            groupThreadFactory.memberAddressesBuilder = { return [] }
            let groupThread = groupThreadFactory.create(transaction: transaction)
            // We construct the TSGroupMember members using specific addresses/mappings.
            let groupMember1 = TSGroupMember(address: SignalServiceAddress(uuid: uuid1,
                                                                           phoneNumber: phoneNumber1),
                                             groupThreadId: groupThread.uniqueId,
                                             lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp())
            groupMember1.anyInsert(transaction: transaction)
            // NOTE: This member has a uuid.
            let groupMember2 = TSGroupMember(address: SignalServiceAddress(uuid: uuid2,
                                                                           phoneNumber: phoneNumber2),
                                             groupThreadId: groupThread.uniqueId,
                                             lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp())
            groupMember2.anyInsert(transaction: transaction)

            // We should have two group members: (u1, p1) and (u2, p2).
            XCTAssertEqual(2, TSGroupMember.groupMembers(in: groupThread.uniqueId, transaction: transaction).count)

            TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(uuid: uuid1,
                                                                                       phoneNumber: phoneNumber1),
                                              transaction: transaction)
            TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(uuid: uuid2,
                                                                                       phoneNumber: phoneNumber2),
                                              transaction: transaction)

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))

            // User 1 has a SignalRecipient with a high-trust mapping; user 2 does not.
            createHighTrustRecipient(for: SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1), transaction: transaction)

            // uuid1 becomes associated with phoneNumber2.
            createHighTrustRecipient(for: SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2), transaction: transaction)

            // We should still have two group members: (u1, p2) and (u2, nil).
            XCTAssertEqual(2, TSGroupMember.groupMembers(in: groupThread.uniqueId, transaction: transaction).count)

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))
        }
    }

    // This tests an edge case around uuid<->phone number mapping changes.
    //
    // * There _is_ a SignalRecipient with (u1, p1).
    // * There _is no_ SignalRecipient with u1 or p2.
    // * There is a group g1.
    // * There is a TSGroupMember with (u1, p1, g1).
    // * There is a TSGroupMember with (nil, p2, g1).
    // * u1 becomes associated with p2.
    //
    // Therefore:
    //
    // * p2 must be mapped to u1, but there is no existing phoneNumberInstance for p2.
    // * SignalRecipient.clearDBMappings(forPhoneNumber:) must clean up p2 before
    //   SignalRecipient.changePhoneNumber() is called on uuidInstance for u1.
    // * Otherwise we'll end up with two TSGroupMembers with (p2, g1) which violates
    //   a uniqueness constraint.
    func testDBMappingsEdgeCase2() {
        let uuid1 = UUID()
        let phoneNumber1 = CommonGenerator.e164()
        let phoneNumber2 = CommonGenerator.e164()

        write { transaction in
            // There are TSGroupMember instances indicating that both users 1 & 2 are members of the same group.
            let groupThreadFactory = GroupThreadFactory()
            groupThreadFactory.memberAddressesBuilder = { return [] }
            let groupThread = groupThreadFactory.create(transaction: transaction)
            // We construct the TSGroupMember members using specific addresses/mappings.
            let groupMember1 = TSGroupMember(address: SignalServiceAddress(uuid: uuid1,
                                                                           phoneNumber: phoneNumber1),
                                             groupThreadId: groupThread.uniqueId,
                                             lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp())
            groupMember1.anyInsert(transaction: transaction)
            // NOTE: This member has no uuid.
            let groupMember2 = TSGroupMember(address: SignalServiceAddress(phoneNumber: phoneNumber2),
                                             groupThreadId: groupThread.uniqueId,
                                             lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp())
            groupMember2.anyInsert(transaction: transaction)

            // We should have two group members: (u1, p1) and (nil, p2).
            XCTAssertEqual(2, TSGroupMember.groupMembers(in: groupThread.uniqueId, transaction: transaction).count)

            TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(uuid: uuid1,
                                                                                       phoneNumber: phoneNumber1),
                                              transaction: transaction)
            TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(phoneNumber: phoneNumber2),
                                              transaction: transaction)

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))

            // User 1 has a SignalRecipient with a high-trust mapping; user 2 does not.
            createHighTrustRecipient(for: SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1), transaction: transaction)

            // uuid1 becomes associated with phoneNumber2.
            createHighTrustRecipient(for: SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2), transaction: transaction)

            // We should now have two group members: (u1, p2), (fake uuid, nil).
            XCTAssertEqual(2, TSGroupMember.groupMembers(in: groupThread.uniqueId, transaction: transaction).count)

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))
        }
    }

    // This tests an edge case around uuid<->phone number mapping changes.
    //
    // * There _is_ a SignalRecipient with (u1, p1).
    // * There _is no_ SignalRecipient with u1 or p2.
    // * There is a group g1.
    // * There is a TSGroupMember with (u1, p1, g1).
    // * There is a TSGroupMember with (u2, p2, g1).
    // * u2 becomes associated with p1.
    //
    // Therefore:
    //
    // * p1 must be mapped from u1 -> u2, but there is no existing uuidInstance for u2.
    // * SignalRecipient.clearDBMappings(forUuid:) must clean up u2 before
    //   SignalRecipient.changePhoneNumber() is called on phoneNumberInstance for p1.
    // * Otherwise we'll end up with two TSGroupMembers with (p1, g1) which violates
    //   a uniqueness constraint.
    func testDBMappingsEdgeCase3() {
        let uuid1 = UUID()
        let phoneNumber1 = CommonGenerator.e164()
        let uuid2 = UUID()
        let phoneNumber2 = CommonGenerator.e164()

        write { transaction in
            // There are TSGroupMember instances indicating that both users 1 & 2 are members of the same group.
            let groupThreadFactory = GroupThreadFactory()
            groupThreadFactory.memberAddressesBuilder = { return [] }
            let groupThread = groupThreadFactory.create(transaction: transaction)
            // We construct the TSGroupMember members using specific addresses/mappings.
            let groupMember1 = TSGroupMember(address: SignalServiceAddress(uuid: uuid1,
                                                                           phoneNumber: phoneNumber1),
                                             groupThreadId: groupThread.uniqueId,
                                             lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp())
            groupMember1.anyInsert(transaction: transaction)
            // NOTE: This member has a phone number.
            let groupMember2 = TSGroupMember(address: SignalServiceAddress(uuid: uuid2,
                                                                           phoneNumber: phoneNumber2),
                                             groupThreadId: groupThread.uniqueId,
                                             lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp())
            groupMember2.anyInsert(transaction: transaction)

            // We should have two group members: (u1, p1) and (u2, p2).
            XCTAssertEqual(2, TSGroupMember.groupMembers(in: groupThread.uniqueId, transaction: transaction).count)

            TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(uuid: uuid1,
                                                                                       phoneNumber: phoneNumber1),
                                              transaction: transaction)
            TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(uuid: uuid2,
                                                                                       phoneNumber: phoneNumber2),
                                              transaction: transaction)

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))

            // User 1 has a SignalRecipient with a high-trust mapping; user 2 does not.
            createHighTrustRecipient(for: SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1), transaction: transaction)

            // uuid2 becomes associated with phoneNumber1.
            createHighTrustRecipient(for: SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber1), transaction: transaction)

            // We should still have two group members: (u2, p1) and (u1, nil).
            XCTAssertEqual(2, TSGroupMember.groupMembers(in: groupThread.uniqueId, transaction: transaction).count)

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))
        }
    }

    // This tests an edge case around uuid<->phone number mapping changes.
    //
    // * There _is_ a SignalRecipient with (u1, p1).
    // * There _is no_ SignalRecipient with u1 or p2.
    // * There is a group g1.
    // * There is a TSGroupMember with (u1, p1, g1).
    // * There is a TSGroupMember with (u2, p2, g1).
    // * u2 becomes associated with p1.
    //
    // Therefore:
    //
    // * p1 must be mapped from u1 -> u2, but there is no existing uuidInstance for u2.
    // * SignalRecipient.clearDBMappings(forUuid:) must clean up u2 before
    //   SignalRecipient.changePhoneNumber() is called on phoneNumberInstance for p1.
    // * Otherwise we'll end up with two TSGroupMembers with (p1, g1) which violates
    //   a uniqueness constraint.
    func testDBMappingsEdgeCase4() {
        let uuid1 = UUID()
        let phoneNumber1 = CommonGenerator.e164()
        let uuid2 = UUID()

        write { transaction in
            // There are TSGroupMember instances indicating that both users 1 & 2 are members of the same group.
            let groupThreadFactory = GroupThreadFactory()
            groupThreadFactory.memberAddressesBuilder = { return [] }
            let groupThread = groupThreadFactory.create(transaction: transaction)
            // We construct the TSGroupMember members using specific addresses/mappings.
            let groupMember1 = TSGroupMember(address: SignalServiceAddress(uuid: uuid1,
                                                                           phoneNumber: phoneNumber1),
                                             groupThreadId: groupThread.uniqueId,
                                             lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp())
            groupMember1.anyInsert(transaction: transaction)
            // NOTE: This member has no phone number.
            let groupMember2 = TSGroupMember(address: SignalServiceAddress(uuid: uuid2),
                                             groupThreadId: groupThread.uniqueId,
                                             lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp())
            groupMember2.anyInsert(transaction: transaction)

            // We should have two group members: (u1, p1) and (u2, nil).
            XCTAssertEqual(2, TSGroupMember.groupMembers(in: groupThread.uniqueId, transaction: transaction).count)

            TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(uuid: uuid1,
                                                                                       phoneNumber: phoneNumber1),
                                              transaction: transaction)
            TSContactThread.getOrCreateThread(withContactAddress: SignalServiceAddress(uuid: uuid2),
                                              transaction: transaction)

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))

            // User 1 has a SignalRecipient with a high-trust mapping; user 2 does not.
            createHighTrustRecipient(for: SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1), transaction: transaction)

            // uuid2 becomes associated with phoneNumber1.
            createHighTrustRecipient(for: SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber1), transaction: transaction)

            // We should now have two group members: (u2, p1), (fake uuid, nil).
            XCTAssertEqual(2, TSGroupMember.groupMembers(in: groupThread.uniqueId, transaction: transaction).count)

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))
        }
    }

    func testUnregisteredTimestamps() {
        let address = CommonGenerator.address()

        write {
            let registeredRecipient = createHighTrustRecipient(for: address, transaction: $0)
            XCTAssertNil(registeredRecipient.unregisteredAtTimestamp)

            SignalRecipient.fetchOrCreate(for: address, trustLevel: .low, transaction: $0)
                .markAsUnregistered(transaction: $0)

            let unregisteredRecipient = AnySignalRecipientFinder().signalRecipient(for: address, transaction: $0)
            XCTAssert(unregisteredRecipient!.unregisteredAtTimestamp!.uint64Value > 0)

            let reregisteredRecipient = createHighTrustRecipient(for: address, transaction: $0)
            XCTAssertNil(reregisteredRecipient.unregisteredAtTimestamp)
        }
    }

    func testMarkAsRegistered() {
        struct TestCase {
            var initialDeviceIds: Set<UInt32>
            var addedDeviceId: UInt32
            var expectedDeviceIds: Set<UInt32>
        }
        let testCases: [TestCase] = [
            TestCase(initialDeviceIds: [], addedDeviceId: 1, expectedDeviceIds: [1]),
            TestCase(initialDeviceIds: [], addedDeviceId: 2, expectedDeviceIds: [1, 2]),
            TestCase(initialDeviceIds: [1], addedDeviceId: 1, expectedDeviceIds: [1]),
            TestCase(initialDeviceIds: [1], addedDeviceId: 2, expectedDeviceIds: [1, 2]),
            TestCase(initialDeviceIds: [2], addedDeviceId: 1, expectedDeviceIds: [1, 2]),
            TestCase(initialDeviceIds: [2], addedDeviceId: 2, expectedDeviceIds: [1, 2]),
            TestCase(initialDeviceIds: [3], addedDeviceId: 1, expectedDeviceIds: [1, 3]),
            TestCase(initialDeviceIds: [3], addedDeviceId: 2, expectedDeviceIds: [1, 2, 3]),
            TestCase(initialDeviceIds: [1, 2], addedDeviceId: 1, expectedDeviceIds: [1, 2]),
            TestCase(initialDeviceIds: [1, 2], addedDeviceId: 2, expectedDeviceIds: [1, 2]),
            TestCase(initialDeviceIds: [1, 2, 3], addedDeviceId: 1, expectedDeviceIds: [1, 2, 3]),
            TestCase(initialDeviceIds: [1, 2, 3], addedDeviceId: 2, expectedDeviceIds: [1, 2, 3])
        ]
        write { transaction in
            for testCase in testCases {
                let recipient = SignalRecipient.fetchOrCreate(
                    for: CommonGenerator.address(),
                    trustLevel: .low,
                    transaction: transaction
                )
                if !testCase.initialDeviceIds.isEmpty {
                    recipient.anyUpdate(transaction: transaction) {
                        $0.addDevices(Set(testCase.initialDeviceIds.map { NSNumber(value: $0) }), source: .local)
                    }
                }
                recipient.markAsRegistered(deviceId: testCase.addedDeviceId, transaction: transaction)
                XCTAssertEqual(recipient.deviceIds.map { Set($0) }, testCase.expectedDeviceIds, "\(testCase)")
            }
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func createLowTrustRecipient(for address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) -> SignalRecipient {
        let result = SignalRecipient.fetchOrCreate(for: address, trustLevel: .low, transaction: transaction)
        result.markAsRegistered(transaction: transaction)
        return result
    }

    @discardableResult
    private func createHighTrustRecipient(for address: SignalServiceAddress, transaction: SDSAnyWriteTransaction) -> SignalRecipient {
        let result = SignalRecipient.fetchOrCreate(for: address, trustLevel: .high, transaction: transaction)
        result.markAsRegistered(transaction: transaction)
        return result
    }
}
