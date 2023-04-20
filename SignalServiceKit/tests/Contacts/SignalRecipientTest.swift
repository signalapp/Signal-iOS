//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class SignalRecipientTest: SSKBaseTestSwift {

    private lazy var localAci = ServiceId(UUID())
    private lazy var localPhoneNumber = E164("+16505550199")!
    private lazy var localIdentifiers = LocalIdentifiers(
        aci: localAci,
        pni: ServiceId(UUID()),
        phoneNumber: localPhoneNumber.stringValue
    )

    override func setUp() {
        super.setUp()
        tsAccountManager.registerForTests(withLocalNumber: localIdentifiers.phoneNumber, uuid: localIdentifiers.aci.uuidValue)
    }

    func testSelfRecipientWithExistingRecord() {
        write { transaction in
            mergeHighTrust(serviceId: localAci, phoneNumber: localPhoneNumber, transaction: transaction)
            XCTAssertNotNil(fetchRecipient(serviceId: localAci, transaction: transaction))
            XCTAssertNotNil(fetchRecipient(phoneNumber: localPhoneNumber, transaction: transaction))
        }
    }

    func testRecipientWithExistingRecord() {
        let serviceId = ServiceId(UUID())
        let phoneNumber = E164("+16505550101")!
        write { transaction in
            mergeHighTrust(serviceId: serviceId, phoneNumber: phoneNumber, transaction: transaction)
            XCTAssertNotNil(fetchRecipient(serviceId: serviceId, transaction: transaction))
            XCTAssertNotNil(fetchRecipient(phoneNumber: phoneNumber, transaction: transaction))
        }
    }

    // MARK: - Low Trust

    func testLowTrustPhoneNumberOnly() {
        // Phone number only recipients are recorded
        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            let phoneNumber = E164(CommonGenerator.e164())!
            _ = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx.asV2Write)
            XCTAssertNotNil(fetchRecipient(phoneNumber: phoneNumber, transaction: tx))
        }
    }

    func testLowTrustUUIDOnly() {
        // UUID only recipients are recorded
        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            let serviceId = ServiceId(UUID())
            _ = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx.asV2Write)
            XCTAssertNotNil(fetchRecipient(serviceId: serviceId, transaction: tx))
        }
    }

    // MARK: - High Trust

    func testHighTrustUUIDOnly() {
        // UUID only recipients are recorded
        write { transaction in
            let serviceId = ServiceId(UUID())
            _ = mergeHighTrust(serviceId: serviceId, phoneNumber: nil, transaction: transaction)
            XCTAssertNotNil(fetchRecipient(serviceId: serviceId, transaction: transaction))
        }
    }

    func testHighTrustFullyQualified() {
        // Fully qualified addresses are recorded in their entirety

        let serviceId = ServiceId(UUID())
        let phoneNumber = E164("+16505550101")!

        let addressToBeUpdated = SignalServiceAddress(phoneNumber: phoneNumber.stringValue)
        XCTAssertNil(addressToBeUpdated.serviceId)

        write { transaction in
            let recipient = mergeHighTrust(serviceId: serviceId, phoneNumber: phoneNumber, transaction: transaction)
            XCTAssertEqual(recipient.recipientUUID, serviceId.uuidValue.uuidString)
            XCTAssertEqual(recipient.recipientPhoneNumber, phoneNumber.stringValue)

            // The incomplete address is automatically filled after marking the
            // complete address as registered.
            XCTAssertEqual(addressToBeUpdated.serviceId, serviceId)

            XCTAssertNotNil(fetchRecipient(serviceId: serviceId, transaction: transaction))
            XCTAssertNotNil(fetchRecipient(phoneNumber: phoneNumber, transaction: transaction))
        }
    }

    func testHighTrustMergeWithInvestedPhoneNumber() {
        // If there is a UUID-only contact and a phone number-only contact, and if
        // we later find out they are the same user, we must merge them.
        let serviceId = ServiceId(UUID())
        let phoneNumber = E164("+16505550101")!

        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            let uuidRecipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx.asV2Write)
            let phoneNumberRecipient = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx.asV2Write)
            let mergedRecipient = mergeHighTrust(serviceId: serviceId, phoneNumber: phoneNumber, transaction: tx)

            XCTAssertEqual(mergedRecipient.uniqueId, uuidRecipient.uniqueId)
            XCTAssertNil(SignalRecipient.anyFetch(uniqueId: phoneNumberRecipient.uniqueId, transaction: tx))
        }
    }

    func testHighTrustPhoneNumberChange() {
        let aci = ServiceId(UUID())
        let oldPhoneNumber = E164("+16505550101")!
        let newPhoneNumber = E164("+16505550102")!
        let oldAddress = SignalServiceAddress(uuid: aci.uuidValue, e164: oldPhoneNumber)

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
                authedAccount: .implicit(),
                transaction: transaction
            )
            oldProfile.anyInsert(transaction: transaction)

            let oldAccount = SignalAccount(address: oldAddress)
            oldAccount.anyInsert(transaction: transaction)

            mergeHighTrust(serviceId: aci, phoneNumber: oldPhoneNumber, transaction: transaction)
            mergeHighTrust(serviceId: aci, phoneNumber: newPhoneNumber, transaction: transaction)

            let newAddress = SignalServiceAddress(uuid: aci.uuidValue, e164: newPhoneNumber)

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
                authedAccount: .implicit(),
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
        let oldAci = ServiceId(UUID())
        let newAci = ServiceId(UUID())
        let phoneNumber = E164("+16505550101")!
        let oldAddress = SignalServiceAddress(uuid: oldAci.uuidValue, e164: phoneNumber)

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
                authedAccount: .implicit(),
                transaction: transaction
            )
            oldProfile.anyInsert(transaction: transaction)

            let oldAccount = SignalAccount(address: oldAddress)
            oldAccount.anyInsert(transaction: transaction)

            mergeHighTrust(serviceId: oldAci, phoneNumber: phoneNumber, transaction: transaction)
            mergeHighTrust(serviceId: newAci, phoneNumber: phoneNumber, transaction: transaction)

            let newAddress = SignalServiceAddress(uuid: newAci.uuidValue, e164: phoneNumber)

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
                authedAccount: .implicit(),
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
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let uuid2 = UUID()
        let phoneNumber2 = E164(CommonGenerator.e164())!

        write { transaction in
            // There are TSGroupMember instances indicating that both users 1 & 2 are members of the same group.
            let groupThreadFactory = GroupThreadFactory()
            groupThreadFactory.memberAddressesBuilder = { return [] }
            let groupThread = groupThreadFactory.create(transaction: transaction)
            // We construct the TSGroupMember members using specific addresses/mappings.
            let groupMember1 = TSGroupMember(
                serviceId: ServiceId(uuid1),
                phoneNumber: phoneNumber1.stringValue,
                groupThreadId: groupThread.uniqueId,
                lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp()
            )
            groupMember1.anyInsert(transaction: transaction)
            // NOTE: This member has a uuid.
            let groupMember2 = TSGroupMember(
                serviceId: ServiceId(uuid2),
                phoneNumber: phoneNumber2.stringValue,
                groupThreadId: groupThread.uniqueId,
                lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp()
            )
            groupMember2.anyInsert(transaction: transaction)

            // We should have two group members: (u1, p1) and (u2, p2).
            XCTAssertEqual(2, GroupMemberDataStoreImpl().sortedGroupMembers(in: groupThread.uniqueId, transaction: transaction.asV2Read).count)

            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1.stringValue),
                transaction: transaction
            )
            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2.stringValue),
                transaction: transaction
            )

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))

            // User 1 has a SignalRecipient with a high-trust mapping; user 2 does not.
            mergeHighTrust(serviceId: ServiceId(uuid1), phoneNumber: phoneNumber1, transaction: transaction)

            // uuid1 becomes associated with phoneNumber2.
            mergeHighTrust(serviceId: ServiceId(uuid1), phoneNumber: phoneNumber2, transaction: transaction)

            // We should still have two group members: (u1, p2) and (u2, nil).
            XCTAssertEqual(2, GroupMemberDataStoreImpl().sortedGroupMembers(in: groupThread.uniqueId, transaction: transaction.asV2Read).count)

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
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let phoneNumber2 = E164(CommonGenerator.e164())!

        write { transaction in
            // There are TSGroupMember instances indicating that both users 1 & 2 are members of the same group.
            let groupThreadFactory = GroupThreadFactory()
            groupThreadFactory.memberAddressesBuilder = { return [] }
            let groupThread = groupThreadFactory.create(transaction: transaction)
            // We construct the TSGroupMember members using specific addresses/mappings.
            let groupMember1 = TSGroupMember(
                serviceId: ServiceId(uuid1),
                phoneNumber: phoneNumber1.stringValue,
                groupThreadId: groupThread.uniqueId,
                lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp()
            )
            groupMember1.anyInsert(transaction: transaction)
            // NOTE: This member has no uuid.
            let groupMember2 = TSGroupMember(
                serviceId: nil,
                phoneNumber: phoneNumber2.stringValue,
                groupThreadId: groupThread.uniqueId,
                lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp()
            )
            groupMember2.anyInsert(transaction: transaction)

            // We should have two group members: (u1, p1) and (nil, p2).
            XCTAssertEqual(2, GroupMemberDataStoreImpl().sortedGroupMembers(in: groupThread.uniqueId, transaction: transaction.asV2Read).count)

            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1.stringValue),
                transaction: transaction
            )
            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(phoneNumber: phoneNumber2.stringValue),
                transaction: transaction
            )

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))

            // User 1 has a SignalRecipient with a high-trust mapping; user 2 does not.
            mergeHighTrust(serviceId: ServiceId(uuid1), phoneNumber: phoneNumber1, transaction: transaction)

            // uuid1 becomes associated with phoneNumber2.
            mergeHighTrust(serviceId: ServiceId(uuid1), phoneNumber: phoneNumber2, transaction: transaction)

            // We should now have two group members: (u1, p2), (fake uuid, nil).
            XCTAssertEqual(2, GroupMemberDataStoreImpl().sortedGroupMembers(in: groupThread.uniqueId, transaction: transaction.asV2Read).count)

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
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let uuid2 = UUID()
        let phoneNumber2 = E164(CommonGenerator.e164())!

        write { transaction in
            // There are TSGroupMember instances indicating that both users 1 & 2 are members of the same group.
            let groupThreadFactory = GroupThreadFactory()
            groupThreadFactory.memberAddressesBuilder = { return [] }
            let groupThread = groupThreadFactory.create(transaction: transaction)
            // We construct the TSGroupMember members using specific addresses/mappings.
            let groupMember1 = TSGroupMember(
                serviceId: ServiceId(uuid1),
                phoneNumber: phoneNumber1.stringValue,
                groupThreadId: groupThread.uniqueId,
                lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp()
            )
            groupMember1.anyInsert(transaction: transaction)
            // NOTE: This member has a phone number.
            let groupMember2 = TSGroupMember(
                serviceId: ServiceId(uuid2),
                phoneNumber: phoneNumber2.stringValue,
                groupThreadId: groupThread.uniqueId,
                lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp()
            )
            groupMember2.anyInsert(transaction: transaction)

            // We should have two group members: (u1, p1) and (u2, p2).
            XCTAssertEqual(2, GroupMemberDataStoreImpl().sortedGroupMembers(in: groupThread.uniqueId, transaction: transaction.asV2Read).count)

            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1.stringValue),
                transaction: transaction
            )
            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2.stringValue),
                transaction: transaction
            )

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))

            // User 1 has a SignalRecipient with a high-trust mapping; user 2 does not.
            mergeHighTrust(serviceId: ServiceId(uuid1), phoneNumber: phoneNumber1, transaction: transaction)

            // uuid2 becomes associated with phoneNumber1.
            mergeHighTrust(serviceId: ServiceId(uuid2), phoneNumber: phoneNumber1, transaction: transaction)

            // We should still have two group members: (u2, p1) and (u1, nil).
            XCTAssertEqual(2, GroupMemberDataStoreImpl().sortedGroupMembers(in: groupThread.uniqueId, transaction: transaction.asV2Read).count)

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
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let uuid2 = UUID()

        write { transaction in
            // There are TSGroupMember instances indicating that both users 1 & 2 are members of the same group.
            let groupThreadFactory = GroupThreadFactory()
            groupThreadFactory.memberAddressesBuilder = { return [] }
            let groupThread = groupThreadFactory.create(transaction: transaction)
            // We construct the TSGroupMember members using specific addresses/mappings.
            let groupMember1 = TSGroupMember(
                serviceId: ServiceId(uuid1),
                phoneNumber: phoneNumber1.stringValue,
                groupThreadId: groupThread.uniqueId,
                lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp()
            )
            groupMember1.anyInsert(transaction: transaction)
            // NOTE: This member has no phone number.
            let groupMember2 = TSGroupMember(
                serviceId: ServiceId(uuid2),
                phoneNumber: nil,
                groupThreadId: groupThread.uniqueId,
                lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp()
            )
            groupMember2.anyInsert(transaction: transaction)

            // We should have two group members: (u1, p1) and (u2, nil).
            XCTAssertEqual(2, GroupMemberDataStoreImpl().sortedGroupMembers(in: groupThread.uniqueId, transaction: transaction.asV2Read).count)

            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1.stringValue),
                transaction: transaction
            )
            TSContactThread.getOrCreateThread(
                withContactAddress: SignalServiceAddress(uuid: uuid2),
                transaction: transaction
            )

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))

            // User 1 has a SignalRecipient with a high-trust mapping; user 2 does not.
            mergeHighTrust(serviceId: ServiceId(uuid1), phoneNumber: phoneNumber1, transaction: transaction)

            // uuid2 becomes associated with phoneNumber1.
            mergeHighTrust(serviceId: ServiceId(uuid2), phoneNumber: phoneNumber1, transaction: transaction)

            // We should now have two group members: (u2, p1), (fake uuid, nil).
            XCTAssertEqual(2, GroupMemberDataStoreImpl().sortedGroupMembers(in: groupThread.uniqueId, transaction: transaction.asV2Read).count)

            // We should have three threads.
            XCTAssertEqual(3, TSThread.anyCount(transaction: transaction))
        }
    }

    func testUnregisteredTimestamps() {
        let serviceId = ServiceId(UUID())
        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            let recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx.asV2Write)
            XCTAssertNotNil(recipient.unregisteredAtTimestamp)

            recipient.markAsRegistered(transaction: tx)
            XCTAssertNil(fetchRecipient(serviceId: serviceId, transaction: tx)!.unregisteredAtTimestamp)

            recipient.markAsUnregistered(transaction: tx)
            XCTAssertGreaterThan(fetchRecipient(serviceId: serviceId, transaction: tx)!.unregisteredAtTimestamp!.doubleValue, 0)

            recipient.markAsRegistered(transaction: tx)
            XCTAssertNil(fetchRecipient(serviceId: serviceId, transaction: tx)!.unregisteredAtTimestamp)
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
        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            for testCase in testCases {
                let recipient = recipientFetcher.fetchOrCreate(serviceId: ServiceId(UUID()), tx: tx.asV2Write)
                if !testCase.initialDeviceIds.isEmpty {
                    recipient.anyUpdate(transaction: tx) {
                        $0.addDevices(Set(testCase.initialDeviceIds.map { NSNumber(value: $0) }), source: .local)
                    }
                }
                recipient.markAsRegistered(deviceId: testCase.addedDeviceId, transaction: tx)
                XCTAssertEqual(recipient.deviceIds.map { Set($0) }, testCase.expectedDeviceIds, "\(testCase)")
            }
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func mergeHighTrust(serviceId: ServiceId, phoneNumber: E164?, transaction tx: SDSAnyWriteTransaction) -> SignalRecipient {
        let recipientMerger = DependenciesBridge.shared.recipientMerger
        return recipientMerger.applyMergeFromLinkedDevice(
            localIdentifiers: localIdentifiers,
            serviceId: serviceId,
            phoneNumber: phoneNumber,
            tx: tx.asV2Write
        )
    }

    private func fetchRecipient(serviceId: ServiceId, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        SignalRecipient.get(address: SignalServiceAddress(serviceId), mustHaveDevices: false, transaction: transaction)
    }

    private func fetchRecipient(phoneNumber: E164, transaction: SDSAnyReadTransaction) -> SignalRecipient? {
        SignalRecipient.get(address: SignalServiceAddress(phoneNumber), mustHaveDevices: false, transaction: transaction)
    }
}
