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

    private func createGroupAndThreads(for addresses: [(aci: ServiceId?, phoneNumber: E164?)]) -> TSGroupThread {
        return self.write { (tx) -> TSGroupThread in
            // Create a group with all the addresses.
            let groupThread = {
                let factory = GroupThreadFactory()
                factory.memberAddressesBuilder = {
                    return addresses.map { SignalServiceAddress(uuid: $0.aci?.uuidValue, e164: $0.phoneNumber) }
                }
                return factory.create(transaction: tx)
            }()
            // Delete the group members that were created automatically.
            TSGroupMember.anyRemoveAllWithInstantiation(transaction: tx)
            // And construct the TSGroupMember members using the specific identifiers
            // that were provided.
            for address in addresses {
                let groupMember = TSGroupMember(
                    serviceId: address.aci,
                    phoneNumber: address.phoneNumber?.stringValue,
                    groupThreadId: groupThread.uniqueId,
                    lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp()
                )
                groupMember.anyInsert(transaction: tx)

                TSContactThread.getOrCreateThread(
                    withContactAddress: SignalServiceAddress(uuid: address.aci?.uuidValue, e164: address.phoneNumber),
                    transaction: tx
                )
            }
            return groupThread
        }
    }

    private func assertEqual(groupMembers: [TSGroupMember], expectedAddresses: [(aci: ServiceId?, phoneNumber: E164?)]) {
        let actualValues = Set(groupMembers.lazy.map {
            "\($0.serviceId?.uuidValue.uuidString ?? "nil")-\($0.phoneNumber ?? "nil")"
        })
        let expectedValues = Set(expectedAddresses.lazy.map {
            "\($0.aci?.uuidValue.uuidString ?? "nil")-\($0.phoneNumber?.stringValue ?? "nil")"
        })
        XCTAssertEqual(actualValues, expectedValues)
    }

    // This tests an edge case around uuid<->phone number mapping changes.
    //
    // * There _is_ a SignalRecipient with (u1, p1).
    // * There _is no_ SignalRecipient with u2 or p2.
    // * There is a group g1.
    // * There is a TSGroupMember with (u1, p1, g1).
    // * There is a TSGroupMember with (u2, p2, g1).
    // * p2 becomes associated with u1.
    //
    // Therefore:
    //
    // * p2 must be mapped from u2 -> u1, but there is no existing phoneNumberInstance for p2.
    // * SignalRecipient.clearDBMappings(forPhoneNumber:) must clean up p2 before
    //   SignalRecipient.changePhoneNumber() is called on uuidInstance for u1.
    // * Otherwise we'll end up with two TSGroupMembers with (p2, g1) which violates
    //   a uniqueness constraint.
    func testDBMappingsEdgeCase1() {
        let uuid1 = ServiceId(UUID())
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let uuid2 = ServiceId(UUID())
        let phoneNumber2 = E164(CommonGenerator.e164())!

        let groupThread = createGroupAndThreads(for: [
            (aci: uuid1, phoneNumber: phoneNumber1),
            (aci: uuid2, phoneNumber: phoneNumber2)
        ])

        write { tx in
            mergeHighTrust(serviceId: uuid1, phoneNumber: phoneNumber1, transaction: tx)
            // phoneNumber2 becomes associated with uuid1.
            mergeHighTrust(serviceId: uuid1, phoneNumber: phoneNumber2, transaction: tx)
        }

        databaseStorage.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 3)
        }

        let finalGroupMembers = databaseStorage.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx.asV2Read)
        }

        // We should still have two group members: (u1, p2) and (u2, nil).
        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: uuid1, phoneNumber: phoneNumber2),
            (aci: uuid2, phoneNumber: nil)
        ])
    }

    // This tests an edge case around uuid<->phone number mapping changes.
    //
    // * There _is_ a SignalRecipient with (u1, p1).
    // * There _is no_ SignalRecipient with u2 or p2.
    // * There is a group g1.
    // * There is a TSGroupMember with (u1, p1, g1).
    // * There is a TSGroupMember with (nil, p2, g1).
    // * p2 becomes associated with u1.
    //
    // Therefore:
    //
    // * p2 must be mapped to u1, but there is no existing phoneNumberInstance for p2.
    // * SignalRecipient.clearDBMappings(forPhoneNumber:) must clean up p2 before
    //   SignalRecipient.changePhoneNumber() is called on uuidInstance for u1.
    // * Otherwise we'll end up with two TSGroupMembers with (p2, g1) which violates
    //   a uniqueness constraint.
    func testDBMappingsEdgeCase2() {
        let uuid1 = ServiceId(UUID())
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let phoneNumber2 = E164(CommonGenerator.e164())!

        let groupThread = createGroupAndThreads(for: [
            (aci: uuid1, phoneNumber: phoneNumber1),
            (aci: nil, phoneNumber: phoneNumber2)
        ])

        write { tx in
            mergeHighTrust(serviceId: uuid1, phoneNumber: phoneNumber1, transaction: tx)
            // phoneNumber2 becomes associated with uuid1.
            mergeHighTrust(serviceId: uuid1, phoneNumber: phoneNumber2, transaction: tx)
        }

        databaseStorage.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 3)
        }

        let finalGroupMembers = databaseStorage.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx.asV2Read)
        }

        // We should now have one group member: (u1, p2).
        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: uuid1, phoneNumber: phoneNumber2)
        ])
    }

    // This tests an edge case around uuid<->phone number mapping changes.
    //
    // * There _is_ a SignalRecipient with (u1, p1).
    // * There _is no_ SignalRecipient with u2 or p2.
    // * There is a group g1.
    // * There is a TSGroupMember with (u1, p1, g1).
    // * There is a TSGroupMember with (u2, p2, g1).
    // * p1 becomes associated with u2.
    //
    // Therefore:
    //
    // * p1 must be mapped from u1 -> u2, but there is no existing uuidInstance for u2.
    // * SignalRecipient.clearDBMappings(forUuid:) must clean up u2 before
    //   SignalRecipient.changePhoneNumber() is called on phoneNumberInstance for p1.
    // * Otherwise we'll end up with two TSGroupMembers with (p1, g1) which violates
    //   a uniqueness constraint.
    func testDBMappingsEdgeCase3() {
        let uuid1 = ServiceId(UUID())
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let uuid2 = ServiceId(UUID())
        let phoneNumber2 = E164(CommonGenerator.e164())!

        let groupThread = createGroupAndThreads(for: [
            (aci: uuid1, phoneNumber: phoneNumber1),
            (aci: uuid2, phoneNumber: phoneNumber2)
        ])

        write { tx in
            mergeHighTrust(serviceId: uuid1, phoneNumber: phoneNumber1, transaction: tx)
            // phoneNumber1 becomes associated with uuid2.
            mergeHighTrust(serviceId: uuid2, phoneNumber: phoneNumber1, transaction: tx)
        }

        databaseStorage.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 3)
        }

        let finalGroupMembers = databaseStorage.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx.asV2Read)
        }

        // We should still have two group members: (u2, p1) and (u1, nil).
        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: uuid2, phoneNumber: phoneNumber1),
            (aci: uuid1, phoneNumber: nil)
        ])
    }

    // This tests an edge case around uuid<->phone number mapping changes.
    //
    // * There _is_ a SignalRecipient with (u1, p1).
    // * There _is no_ SignalRecipient with u2 or p2.
    // * There is a group g1.
    // * There is a TSGroupMember with (u1, p1, g1).
    // * There is a TSGroupMember with (u2, nil, g1).
    // * p1 becomes associated with u2.
    //
    // Therefore:
    //
    // * p1 must be mapped from u1 -> u2, but there is no existing uuidInstance for u2.
    // * SignalRecipient.clearDBMappings(forUuid:) must clean up u2 before
    //   SignalRecipient.changePhoneNumber() is called on phoneNumberInstance for p1.
    // * Otherwise we'll end up with two TSGroupMembers with (p1, g1) which violates
    //   a uniqueness constraint.
    func testDBMappingsEdgeCase4() {
        let uuid1 = ServiceId(UUID())
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let uuid2 = ServiceId(UUID())

        let groupThread = createGroupAndThreads(for: [
            (aci: uuid1, phoneNumber: phoneNumber1),
            (aci: uuid2, phoneNumber: nil)
        ])

        write { tx in
            mergeHighTrust(serviceId: uuid1, phoneNumber: phoneNumber1, transaction: tx)
            // phoneNumber1 becomes associated with uuid2.
            mergeHighTrust(serviceId: uuid2, phoneNumber: phoneNumber1, transaction: tx)
        }

        databaseStorage.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 3)
        }

        let finalGroupMembers = databaseStorage.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx.asV2Read)
        }

        // We should now have two group members: (u2, p1), (u1, nil).
        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: uuid1, phoneNumber: nil),
            (aci: uuid2, phoneNumber: phoneNumber1)
        ])
    }

    /// This tests an edge case around groups & merging contacts.
    ///
    /// If a phone number and UUID are both part of a group, and if we later
    /// learn that they refer to the same account, we'll end up with a
    /// "duplicate" group member.
    ///
    /// This should only be possible in GV1 groups -- in GV2, every member
    /// should have a UUID, and that requirement would put us back in
    /// testDBMappingsEdgeCase4 territory.
    func testDBMappingsEdgeCase5() {
        let uuid1 = ServiceId(UUID())
        let phoneNumber1 = E164(CommonGenerator.e164())!

        let groupThread = createGroupAndThreads(for: [
            (aci: uuid1, phoneNumber: nil),
            (aci: nil, phoneNumber: phoneNumber1)
        ])

        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            _ = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber1, tx: tx.asV2Write)
            mergeHighTrust(serviceId: uuid1, phoneNumber: nil, transaction: tx)
            mergeHighTrust(serviceId: uuid1, phoneNumber: phoneNumber1, transaction: tx)
        }

        databaseStorage.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 3)
        }

        let finalGroupMembers = databaseStorage.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx.asV2Read)
        }

        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: uuid1, phoneNumber: phoneNumber1)
        ])
    }

    /// This tests an edge case around groups & merging contacts.
    ///
    /// If we merge an ACI & E164 into a single recipient, and then if another
    /// account claims that phone number, we should ensure that the original ACI
    /// is still in the group but the new ACI is not.
    func testDBMappingsEdgeCase6() {
        let uuid1 = ServiceId(UUID())
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let uuid2 = ServiceId(UUID())

        let groupThread = createGroupAndThreads(for: [
            (aci: uuid1, phoneNumber: nil),
            (aci: nil, phoneNumber: phoneNumber1)
        ])

        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            _ = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber1, tx: tx.asV2Write)
            mergeHighTrust(serviceId: uuid1, phoneNumber: nil, transaction: tx)
            mergeHighTrust(serviceId: uuid1, phoneNumber: phoneNumber1, transaction: tx)
            mergeHighTrust(serviceId: uuid2, phoneNumber: phoneNumber1, transaction: tx)
        }

        databaseStorage.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 3)
        }

        let finalGroupMembers = databaseStorage.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx.asV2Read)
        }

        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: uuid1, phoneNumber: nil)
        ])
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
