//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

class SignalRecipientTest: SSKBaseTest {

    private lazy var localAci = Aci.randomForTesting()
    private lazy var localPhoneNumber = E164("+16505550199")!
    private lazy var localIdentifiers = LocalIdentifiers(
        aci: localAci,
        pni: Pni.randomForTesting(),
        phoneNumber: localPhoneNumber.stringValue
    )

    override func setUp() {
        super.setUp()
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: localIdentifiers,
                tx: tx
            )
        }
    }

    func testSelfRecipientWithExistingRecord() {
        write { transaction in
            mergeHighTrust(aci: localAci, phoneNumber: localPhoneNumber, transaction: transaction)
            XCTAssertNotNil(fetchRecipient(aci: localAci, transaction: transaction))
            XCTAssertNotNil(fetchRecipient(phoneNumber: localPhoneNumber, transaction: transaction))
        }
    }

    func testRecipientWithExistingRecord() {
        let aci = Aci.randomForTesting()
        let phoneNumber = E164("+16505550101")!
        write { transaction in
            mergeHighTrust(aci: aci, phoneNumber: phoneNumber, transaction: transaction)
            XCTAssertNotNil(fetchRecipient(aci: aci, transaction: transaction))
            XCTAssertNotNil(fetchRecipient(phoneNumber: phoneNumber, transaction: transaction))
        }
    }

    // MARK: - Low Trust

    func testLowTrustPhoneNumberOnly() {
        // Phone number only recipients are recorded
        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            let phoneNumber = E164(CommonGenerator.e164())!
            _ = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx)
            XCTAssertNotNil(fetchRecipient(phoneNumber: phoneNumber, transaction: tx))
        }
    }

    func testLowTrustUUIDOnly() {
        // UUID only recipients are recorded
        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            let aci = Aci.randomForTesting()
            _ = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
            XCTAssertNotNil(fetchRecipient(aci: aci, transaction: tx))
        }
    }

    // MARK: - High Trust

    func testHighTrustUUIDOnly() {
        // UUID only recipients are recorded
        write { transaction in
            let aci = Aci.randomForTesting()
            _ = mergeHighTrust(aci: aci, phoneNumber: nil, transaction: transaction)
            XCTAssertNotNil(fetchRecipient(aci: aci, transaction: transaction))
        }
    }

    func testHighTrustFullyQualified() {
        // Fully qualified addresses are recorded in their entirety

        let aci = Aci.randomForTesting()
        let phoneNumber = E164("+16505550101")!

        let addressToBeUpdated = SignalServiceAddress(phoneNumber: phoneNumber.stringValue)
        XCTAssertNil(addressToBeUpdated.serviceId)

        write { transaction in
            let aciProfile = OWSUserProfile.getOrBuildUserProfile(
                for: .otherUser(aci),
                userProfileWriter: .tests,
                tx: transaction
            )
            aciProfile.anyInsert(transaction: transaction)
            aciProfile.update(
                isPhoneNumberShared: .setTo(true),
                userProfileWriter: .tests,
                transaction: transaction
            )
            let recipient = mergeHighTrust(aci: aci, phoneNumber: phoneNumber, transaction: transaction)
            XCTAssertEqual(recipient.aci, aci)
            XCTAssertEqual(recipient.phoneNumber?.stringValue, phoneNumber.stringValue)

            // The incomplete address is automatically filled after marking the
            // complete address as registered.
            XCTAssertEqual(addressToBeUpdated.serviceId, aci)

            XCTAssertNotNil(fetchRecipient(aci: aci, transaction: transaction))
            XCTAssertNotNil(fetchRecipient(phoneNumber: phoneNumber, transaction: transaction))
        }
    }

    func testHighTrustMergeWithInvestedPhoneNumber() {
        let recipientDatabaseTable = DependenciesBridge.shared.recipientDatabaseTable

        // If there is a UUID-only contact and a phone number-only contact, and if
        // we later find out they are the same user, we must merge them.
        let aci = Aci.randomForTesting()
        let phoneNumber = E164("+16505550101")!

        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            let uuidRecipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
            let phoneNumberRecipient = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber, tx: tx)
            let mergedRecipient = mergeHighTrust(aci: aci, phoneNumber: phoneNumber, transaction: tx)

            XCTAssertEqual(mergedRecipient.uniqueId, uuidRecipient.uniqueId)
            XCTAssertNil(recipientDatabaseTable.fetchRecipient(uniqueId: phoneNumberRecipient.uniqueId, tx: tx))
        }
    }

    func testHighTrustPhoneNumberChange() {
        let aci = Aci.randomForTesting()
        let oldPhoneNumber = E164("+16505550101")!
        let newPhoneNumber = E164("+16505550102")!
        let oldAddress = SignalServiceAddress(serviceId: aci, phoneNumber: oldPhoneNumber.stringValue)

        // Do this because of SignalServiceAddressTest.test_hashStability2().
        _ = SignalServiceAddress(serviceId: aci, phoneNumber: newPhoneNumber.stringValue)

        write { transaction in
            let oldThread = TSContactThread.getOrCreateThread(
                withContactAddress: oldAddress,
                transaction: transaction
            )

            let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
                thread: oldThread,
                authorAci: aci,
                messageBody: "Test 123"
            )
            let oldMessage = messageBuilder.build()
            oldMessage.anyInsert(transaction: transaction)

            let oldPhoneNumberProfile = OWSUserProfile.getOrBuildUserProfile(
                for: .otherUser(aci),
                userProfileWriter: .tests,
                tx: transaction
            )
            oldPhoneNumberProfile.anyInsert(transaction: transaction)
            oldPhoneNumberProfile.update(
                isPhoneNumberShared: .setTo(true),
                userProfileWriter: .tests,
                transaction: transaction
            )
            let newPhoneNumberProfile = OWSUserProfile(
                address: .otherUser(SignalServiceAddress(phoneNumber: newPhoneNumber.stringValue))
            )
            newPhoneNumberProfile.anyInsert(transaction: transaction)

            let oldAccount = SignalAccount(phoneNumber: oldAddress.phoneNumber!)
            oldAccount.anyInsert(transaction: transaction)

            mergeHighTrust(aci: aci, phoneNumber: oldPhoneNumber, transaction: transaction)
            mergeHighTrust(aci: aci, phoneNumber: newPhoneNumber, transaction: transaction)

            let newAddress = SignalServiceAddress(serviceId: aci, phoneNumber: newPhoneNumber.stringValue)

            let newThread = TSContactThread.getOrCreateThread(
                withContactAddress: newAddress,
                transaction: transaction
            )
            let newMessage = TSIncomingMessage.anyFetchIncomingMessage(
                uniqueId: oldMessage.uniqueId,
                transaction: transaction
            )!
            let newProfile = OWSUserProfile.getOrBuildUserProfile(
                for: .otherUser(aci),
                userProfileWriter: .tests,
                tx: transaction
            )
            let newAccount = SignalAccount.anyFetch(
                uniqueId: oldAccount.uniqueId,
                transaction: transaction
            )

            // We maintain the same thread, profile, interactions, etc.
            // after the phone number change. They are updated to reflect
            // the new address.
            XCTAssertEqual(oldAddress.phoneNumber, newAddress.phoneNumber)
            XCTAssertEqual(oldAddress.serviceId, newAddress.serviceId)

            XCTAssertEqual(oldThread.uniqueId, newThread.uniqueId)
            XCTAssertNil(oldThread.contactPhoneNumber)
            XCTAssertNil(newThread.contactPhoneNumber)
            XCTAssertEqual(newAddress, newThread.contactAddress)

            XCTAssertEqual(oldMessage.uniqueId, newMessage.uniqueId)
            XCTAssertEqual(newAddress, newMessage.authorAddress)
            XCTAssertNil(oldMessage.authorPhoneNumber)
            XCTAssertNil(newMessage.authorPhoneNumber)

            XCTAssertEqual(newProfile.uniqueId, oldPhoneNumberProfile.uniqueId)
            XCTAssertNil(newProfile.phoneNumber)
            XCTAssertEqual(newProfile.serviceIdString, aci.serviceIdUppercaseString)
            XCTAssertNil(OWSUserProfile.anyFetch(uniqueId: newPhoneNumberProfile.uniqueId, transaction: transaction))

            XCTAssertNil(newAccount)
        }
    }

    func testHighTrustUUIDChange() throws {
        let oldAci = Aci.randomForTesting()
        let newAci = Aci.randomForTesting()
        let phoneNumber = E164("+16505550101")!
        let oldAddress = SignalServiceAddress(serviceId: oldAci, phoneNumber: phoneNumber.stringValue)

        try write { transaction in
            var oldThread = TSContactThread.getOrCreateThread(
                withContactAddress: oldAddress,
                transaction: transaction
            )

            let messageBuilder: TSIncomingMessageBuilder = .withDefaultValues(
                thread: oldThread,
                authorAci: oldAci,
                messageBody: "Test 123"
            )
            let oldMessage = messageBuilder.build()
            oldMessage.anyInsert(transaction: transaction)

            var oldProfile = OWSUserProfile(address: .otherUser(oldAddress))
            oldProfile.anyInsert(transaction: transaction)
            oldProfile.update(
                isPhoneNumberShared: .setTo(true),
                userProfileWriter: .tests,
                transaction: transaction
            )

            let oldAccount = SignalAccount(phoneNumber: oldAddress.phoneNumber!)
            oldAccount.anyInsert(transaction: transaction)

            mergeHighTrust(aci: oldAci, phoneNumber: phoneNumber, transaction: transaction)
            mergeHighTrust(aci: newAci, phoneNumber: phoneNumber, transaction: transaction)

            let newAddress = SignalServiceAddress(serviceId: newAci, phoneNumber: phoneNumber.stringValue)

            let newThread = TSContactThread.getOrCreateThread(
                withContactAddress: newAddress,
                transaction: transaction
            )
            let newMessage = TSIncomingMessage.anyFetchIncomingMessage(
                uniqueId: oldMessage.uniqueId,
                transaction: transaction
            )!
            let newProfile = OWSUserProfile.getOrBuildUserProfile(
                for: .otherUser(newAci),
                userProfileWriter: .tests,
                tx: transaction
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
            XCTAssertNotEqual(oldAddress.serviceId, newAddress.serviceId)

            oldThread = TSContactThread.anyFetchContactThread(uniqueId: oldThread.uniqueId, transaction: transaction)!
            XCTAssertNotEqual(oldThread.uniqueId, newThread.uniqueId)
            XCTAssertNil(oldThread.contactPhoneNumber)
            XCTAssertEqual(newAddress, newThread.contactAddress)
            XCTAssertNotEqual(newAddress, oldThread.contactAddress)

            XCTAssertEqual(oldMessage.uniqueId, newMessage.uniqueId)
            XCTAssertNil(newMessage.authorPhoneNumber)
            XCTAssertNotEqual(newAddress, newMessage.authorAddress)

            oldProfile = try XCTUnwrap(OWSUserProfile.anyFetch(uniqueId: oldProfile.uniqueId, transaction: transaction))
            XCTAssertNotEqual(oldProfile.uniqueId, newProfile.uniqueId)
            XCTAssertNil(oldProfile.phoneNumber)
            XCTAssertEqual(.otherUser(newAddress), newProfile.internalAddress)
            XCTAssertNotEqual(.otherUser(newAddress), oldProfile.internalAddress)

            XCTAssertEqual(newAccount.uniqueId, oldAccount.uniqueId)
            XCTAssertEqual(newAccount.recipientPhoneNumber, phoneNumber.stringValue)
            XCTAssertEqual(newAccount.recipientServiceId, newAci)
        }
    }

    private func createGroupAndThreads(for addresses: [(aci: Aci?, phoneNumber: E164?)]) -> TSGroupThread {
        return self.write { (tx) -> TSGroupThread in
            // Create a group with all the addresses.
            let groupThread = {
                return try! GroupManager.createGroupForTests(
                    members: addresses.map { SignalServiceAddress(serviceId: $0.aci, phoneNumber: $0.phoneNumber?.stringValue) },
                    transaction: tx
                )
            }()

            // Delete the group members that were created automatically.
            try! TSGroupMember.deleteAll(tx.database)

            // And construct the TSGroupMember members using the specific identifiers
            // that were provided.
            for address in addresses {
                let groupMember = TSGroupMember(
                    address: NormalizedDatabaseRecordAddress(
                        aci: address.aci,
                        phoneNumber: address.phoneNumber?.stringValue,
                        pni: nil
                    )!,
                    groupThreadId: groupThread.uniqueId,
                    lastInteractionTimestamp: NSDate.ows_millisecondTimeStamp()
                )
                groupMember.anyInsert(transaction: tx)

                TSContactThread.getOrCreateThread(
                    withContactAddress: SignalServiceAddress(serviceId: address.aci, phoneNumber: address.phoneNumber?.stringValue),
                    transaction: tx
                )
            }
            return groupThread
        }
    }

    private func assertEqual(groupMembers: [TSGroupMember], expectedAddresses: [(aci: Aci?, phoneNumber: E164?)]) {
        let actualValues = Set(groupMembers.lazy.map {
            "\($0.serviceId?.serviceIdUppercaseString ?? "nil")-\($0.phoneNumber ?? "nil")"
        })
        let expectedValues = Set(expectedAddresses.lazy.map {
            "\($0.aci?.serviceIdUppercaseString ?? "nil")-\($0.phoneNumber?.stringValue ?? "nil")"
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
        let aci1 = Aci.randomForTesting()
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let aci2 = Aci.randomForTesting()
        let phoneNumber2 = E164(CommonGenerator.e164())!

        let groupThread = createGroupAndThreads(for: [
            (aci: aci1, phoneNumber: phoneNumber1),
            (aci: aci2, phoneNumber: phoneNumber2)
        ])

        write { tx in
            mergeHighTrust(aci: aci1, phoneNumber: phoneNumber1, transaction: tx)
            // phoneNumber2 becomes associated with aci1.
            mergeHighTrust(aci: aci1, phoneNumber: phoneNumber2, transaction: tx)
        }

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 3)
        }

        let finalGroupMembers = SSKEnvironment.shared.databaseStorageRef.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx)
        }

        // We should still have two group members: (u1, p2) and (u2, nil).
        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: aci1, phoneNumber: nil),
            (aci: aci2, phoneNumber: nil)
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
        let aci1 = Aci.randomForTesting()
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let phoneNumber2 = E164(CommonGenerator.e164())!

        let groupThread = createGroupAndThreads(for: [
            (aci: aci1, phoneNumber: phoneNumber1),
            (aci: nil, phoneNumber: phoneNumber2)
        ])

        write { tx in
            mergeHighTrust(aci: aci1, phoneNumber: phoneNumber1, transaction: tx)
            // phoneNumber2 becomes associated with aci1.
            mergeHighTrust(aci: aci1, phoneNumber: phoneNumber2, transaction: tx)
        }

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 2)
        }

        let finalGroupMembers = SSKEnvironment.shared.databaseStorageRef.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx)
        }

        // We should now have one group member: (u1, p2).
        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: aci1, phoneNumber: nil)
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
        let aci1 = Aci.randomForTesting()
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let aci2 = Aci.randomForTesting()
        let phoneNumber2 = E164(CommonGenerator.e164())!

        let groupThread = createGroupAndThreads(for: [
            (aci: aci1, phoneNumber: phoneNumber1),
            (aci: aci2, phoneNumber: phoneNumber2)
        ])

        write { tx in
            mergeHighTrust(aci: aci1, phoneNumber: phoneNumber1, transaction: tx)
            // phoneNumber1 becomes associated with aci2.
            mergeHighTrust(aci: aci2, phoneNumber: phoneNumber1, transaction: tx)
        }

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 3)
        }

        let finalGroupMembers = SSKEnvironment.shared.databaseStorageRef.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx)
        }

        // We should still have two group members: (u2, p1) and (u1, nil).
        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: aci2, phoneNumber: nil),
            (aci: aci1, phoneNumber: nil)
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
        let aci1 = Aci.randomForTesting()
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let aci2 = Aci.randomForTesting()

        let groupThread = createGroupAndThreads(for: [
            (aci: aci1, phoneNumber: phoneNumber1),
            (aci: aci2, phoneNumber: nil)
        ])

        write { tx in
            mergeHighTrust(aci: aci1, phoneNumber: phoneNumber1, transaction: tx)
            // phoneNumber1 becomes associated with aci2.
            mergeHighTrust(aci: aci2, phoneNumber: phoneNumber1, transaction: tx)
        }

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 3)
        }

        let finalGroupMembers = SSKEnvironment.shared.databaseStorageRef.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx)
        }

        // We should now have two group members: (u2, p1), (u1, nil).
        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: aci1, phoneNumber: nil),
            (aci: aci2, phoneNumber: nil)
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
        let aci1 = Aci.randomForTesting()
        let phoneNumber1 = E164(CommonGenerator.e164())!

        let groupThread = createGroupAndThreads(for: [
            (aci: aci1, phoneNumber: nil),
            (aci: nil, phoneNumber: phoneNumber1)
        ])

        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            _ = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber1, tx: tx)
            mergeHighTrust(aci: aci1, phoneNumber: nil, transaction: tx)
            mergeHighTrust(aci: aci1, phoneNumber: phoneNumber1, transaction: tx)
        }

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 2)
        }

        let finalGroupMembers = SSKEnvironment.shared.databaseStorageRef.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx)
        }

        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: aci1, phoneNumber: nil)
        ])
    }

    /// This tests an edge case around groups & merging contacts.
    ///
    /// If we merge an ACI & E164 into a single recipient, and then if another
    /// account claims that phone number, we should ensure that the original ACI
    /// is still in the group but the new ACI is not.
    func testDBMappingsEdgeCase6() {
        let aci1 = Aci.randomForTesting()
        let phoneNumber1 = E164(CommonGenerator.e164())!
        let aci2 = Aci.randomForTesting()

        let groupThread = createGroupAndThreads(for: [
            (aci: aci1, phoneNumber: nil),
            (aci: nil, phoneNumber: phoneNumber1)
        ])

        write { tx in
            let recipientFetcher = DependenciesBridge.shared.recipientFetcher
            _ = recipientFetcher.fetchOrCreate(phoneNumber: phoneNumber1, tx: tx)
            mergeHighTrust(aci: aci1, phoneNumber: nil, transaction: tx)
            mergeHighTrust(aci: aci1, phoneNumber: phoneNumber1, transaction: tx)
            mergeHighTrust(aci: aci2, phoneNumber: phoneNumber1, transaction: tx)
        }

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertEqual(TSThread.anyCount(transaction: tx), 2)
        }

        let finalGroupMembers = SSKEnvironment.shared.databaseStorageRef.read { tx in
            GroupMemberStoreImpl().sortedFullGroupMembers(in: groupThread.uniqueId, tx: tx)
        }

        assertEqual(groupMembers: finalGroupMembers, expectedAddresses: [
            (aci: aci1, phoneNumber: nil)
        ])
    }

    func testDeDupe() throws {
        let databaseQueue = DatabaseQueue()
        let deviceIdsObjC = NSOrderedSet(array: [NSNumber]())
        let encodedDevices = SDSCodableModelLegacySerializer().serializeAsLegacySDSData(property: deviceIdsObjC)
        try databaseQueue.write { db in
            try db.execute(
                sql: """
                CREATE
                    TABLE
                        IF NOT EXISTS "model_SignalRecipient" (
                            "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                            ,"recordType" INTEGER NOT NULL
                            ,"uniqueId" TEXT NOT NULL UNIQUE
                                ON CONFLICT FAIL
                            ,"devices" BLOB NOT NULL
                            ,"recipientPhoneNumber" TEXT
                            ,"recipientUUID" TEXT
                        )
                ;
                """
            )
            let aci1 = Aci.randomForTesting()
            let aci2 = Aci.randomForTesting()
            try db.execute(
                sql: "INSERT INTO model_SignalRecipient (recordType, uniqueId, recipientUUID, devices) VALUES (?, ?, ?, ?)",
                arguments: [
                    SDSRecordType.signalRecipient.rawValue,
                    UUID().uuidString,
                    aci1.serviceIdUppercaseString,
                    encodedDevices,
                ],
            )
            try db.execute(
                sql: "INSERT INTO model_SignalRecipient (recordType, uniqueId, recipientUUID, devices) VALUES (?, ?, ?, ?)",
                arguments: [
                    SDSRecordType.signalRecipient.rawValue,
                    UUID().uuidString,
                    aci1.serviceIdUppercaseString,
                    encodedDevices,
                ],
            )
            try db.execute(
                sql: "INSERT INTO model_SignalRecipient (recordType, uniqueId, recipientUUID, devices) VALUES (?, ?, ?, ?)",
                arguments: [
                    SDSRecordType.signalRecipient.rawValue,
                    UUID().uuidString,
                    aci2.serviceIdUppercaseString,
                    encodedDevices,
                ],
            )
            do {
                let tx = DBWriteTransaction(database: db)
                defer { tx.finalizeTransaction() }
                dedupeSignalRecipients(transaction: tx)
            }
            let recipientCount = try Int64.fetchOne(db, sql: "SELECT COUNT(*) FROM model_SignalRecipient")
            XCTAssertEqual(recipientCount, 2)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func mergeHighTrust(aci: Aci, phoneNumber: E164?, transaction tx: DBWriteTransaction) -> SignalRecipient {
        let recipientMerger = DependenciesBridge.shared.recipientMerger
        return recipientMerger.applyMergeFromContactSync(
            localIdentifiers: localIdentifiers,
            aci: aci,
            phoneNumber: phoneNumber,
            tx: tx
        )
    }

    private func fetchRecipient(aci: Aci, transaction tx: DBReadTransaction) -> SignalRecipient? {
        return DependenciesBridge.shared.recipientDatabaseTable
            .fetchRecipient(serviceId: aci, transaction: tx)
    }

    private func fetchRecipient(phoneNumber: E164, transaction tx: DBReadTransaction) -> SignalRecipient? {
        return DependenciesBridge.shared.recipientDatabaseTable
            .fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx)
    }
}

final class SignalRecipient2Test: XCTestCase {
    private enum Constants {
        static let emptyDevices = "62706c6973743030d4010203040506070a582476657273696f6e592461726368697665725424746f7058246f626a6563747312000186a05f100f4e534b657965644172636869766572d1080954726f6f748001a30b0c0f55246e756c6cd10d0e5624636c6173738002d2101112135a24636c6173736e616d655824636c61737365735c4e534f726465726564536574a214155c4e534f726465726564536574584e534f626a65637408111a24293237494c5153575d6067696e79828f929f00000000000001010000000000000016000000000000000000000000000000a8"
    }

    func testDecodeStableRow() throws {
        let inMemoryDB = InMemoryDB()
        try inMemoryDB.write { tx in
            try tx.database.execute(sql: """
                INSERT INTO "model_SignalRecipient" (
                    "id", "recordType", "uniqueId", "devices", "recipientPhoneNumber", "recipientUUID", "unregisteredAtTimestamp"
                ) VALUES (
                    18,
                    31,
                    '00000000-0000-4000-8000-00000000000A',
                    X'62706c6973743030d4010203040506070a582476657273696f6e592461726368697665725424746f7058246f626a6563747312000186a05f100f4e534b657965644172636869766572d1080954726f6f748001a80b0c191a1b1c1d1e55246e756c6cd60d0e0f1011121314151617185624636c6173735b4e532e6f626a6563742e315b4e532e6f626a6563742e345b4e532e6f626a6563742e305b4e532e6f626a6563742e335b4e532e6f626a6563742e3280078003800680028005800410011002100510041006d21f2021225a24636c6173736e616d655824636c61737365735c4e534f726465726564536574a223245c4e534f726465726564536574584e534f626a65637400080011001a00240029003200370049004c00510053005c0062006f00760082008e009a00a600b200b400b600b800ba00bc00be00c000c200c400c600c800cd00d800e100ee00f100fe0000000000000201000000000000002500000000000000000000000000000107',
                    '+16505550100',
                    '00000000-0000-4000-8000-000000000000',
                    NULL
                ),
                (
                    21,
                    31,
                    '00000000-0000-4000-8000-00000000000B',
                    X'\(Constants.emptyDevices)',
                    '+16505550101',
                    '00000000-0000-4000-8000-000000000001',
                    1683679214631
                );
            """)
        }
        inMemoryDB.read { tx in
            let signalRecipients = try! SignalRecipient.fetchAll(tx.database)
            XCTAssertEqual(signalRecipients.count, 2)

            XCTAssertEqual(signalRecipients[0].id, 18)
            XCTAssertEqual(signalRecipients[0].uniqueId, "00000000-0000-4000-8000-00000000000A")
            XCTAssertEqual(signalRecipients[0].deviceIds, [1, 2, 5, 4, 6].map { DeviceId(validating: $0)! })
            XCTAssertEqual(signalRecipients[0].phoneNumber?.stringValue, "+16505550100")
            XCTAssertEqual(signalRecipients[0].phoneNumber?.isDiscoverable, false)
            XCTAssertEqual(signalRecipients[0].aciString, "00000000-0000-4000-8000-000000000000")
            XCTAssertEqual(signalRecipients[0].unregisteredAtTimestamp, nil)

            XCTAssertEqual(signalRecipients[1].id, 21)
            XCTAssertEqual(signalRecipients[1].uniqueId, "00000000-0000-4000-8000-00000000000B")
            XCTAssertEqual(signalRecipients[1].deviceIds, [])
            XCTAssertEqual(signalRecipients[1].phoneNumber?.stringValue, "+16505550101")
            XCTAssertEqual(signalRecipients[1].phoneNumber?.isDiscoverable, false)
            XCTAssertEqual(signalRecipients[1].aciString, "00000000-0000-4000-8000-000000000001")
            XCTAssertEqual(signalRecipients[1].unregisteredAtTimestamp, 1683679214631)
        }
    }

    func testDecodePni() throws {
        let inMemoryDB = InMemoryDB()
        try inMemoryDB.write { tx in
            try tx.database.execute(sql: """
                INSERT INTO "model_SignalRecipient" (
                    "id", "recordType", "uniqueId", "devices", "pni"
                ) VALUES (
                    1,
                    31,
                    '00000000-0000-4000-8000-000000000000',
                    X'\(Constants.emptyDevices)',
                    'PNI:10000000-2000-4000-8000-300000000004'
                );
            """)
        }
        inMemoryDB.read { tx in
            let signalRecipients = try! SignalRecipient.fetchAll(tx.database)
            XCTAssertEqual(signalRecipients.count, 1)

            XCTAssertEqual(signalRecipients[0].id, 1)
            XCTAssertEqual(signalRecipients[0].uniqueId, "00000000-0000-4000-8000-000000000000")
            XCTAssertEqual(signalRecipients[0].deviceIds, [])
            XCTAssertEqual(signalRecipients[0].pni, Pni.constantForTesting("PNI:10000000-2000-4000-8000-300000000004"))
        }
    }

    func testEncodePni() throws {
        let inMemoryDB = InMemoryDB()
        let pni = Pni.constantForTesting("PNI:30000000-5000-4000-8000-3000000000A9")
        inMemoryDB.insert(record: SignalRecipient(aci: nil, pni: pni, phoneNumber: nil))
        inMemoryDB.read { tx in
            let db = tx.database
            let rawPniValue = try! String.fetchOne(db, sql: #"SELECT "pni" FROM "model_SignalRecipient""#)!
            XCTAssertEqual(rawPniValue, pni.serviceIdUppercaseString)
        }
    }

    func testEqualityAndHashing() {
        let someRecipient = SignalRecipient(aci: Aci.randomForTesting(), pni: nil, phoneNumber: nil, deviceIds: [1, 2].map { DeviceId(validating: $0)! })
        let copiedRecipient = someRecipient.copyRecipient()
        XCTAssertEqual(copiedRecipient, someRecipient)
        XCTAssertEqual(copiedRecipient.hashValue, someRecipient.hashValue)
        XCTAssertEqual(Set([someRecipient, copiedRecipient]).count, 1)
    }

    func testUnregisteredTimestamps() {
        let aci = Aci.randomForTesting()
        let mockDb = InMemoryDB()
        let recipientTable = RecipientDatabaseTable()
        let recipientFetcher = RecipientFetcherImpl(
            recipientDatabaseTable: recipientTable,
            searchableNameIndexer: MockSearchableNameIndexer(),
        )
        let recipientManager = SignalRecipientManagerImpl(
            phoneNumberVisibilityFetcher: MockPhoneNumberVisibilityFetcher(),
            recipientDatabaseTable: recipientTable,
            storageServiceManager: FakeStorageServiceManager()
        )
        mockDb.write { tx in
            let recipient = recipientFetcher.fetchOrCreate(serviceId: aci, tx: tx)
            XCTAssertNotNil(recipient.unregisteredAtTimestamp)

            recipientManager.markAsRegisteredAndSave(recipient, shouldUpdateStorageService: false, tx: tx)
            XCTAssertNil(recipientTable.fetchRecipient(serviceId: aci, transaction: tx)!.unregisteredAtTimestamp)

            recipientManager.markAsUnregisteredAndSave(recipient, unregisteredAt: .now, shouldUpdateStorageService: false, tx: tx)
            XCTAssertGreaterThan(recipientTable.fetchRecipient(serviceId: aci, transaction: tx)!.unregisteredAtTimestamp!, 0)

            recipientManager.markAsRegisteredAndSave(recipient, shouldUpdateStorageService: false, tx: tx)
            XCTAssertNil(recipientTable.fetchRecipient(serviceId: aci, transaction: tx)!.unregisteredAtTimestamp)
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
        let mockDb = InMemoryDB()
        let recipientTable = RecipientDatabaseTable()
        let recipientFetcher = RecipientFetcherImpl(
            recipientDatabaseTable: recipientTable,
            searchableNameIndexer: MockSearchableNameIndexer(),
        )
        let recipientManager = SignalRecipientManagerImpl(
            phoneNumberVisibilityFetcher: MockPhoneNumberVisibilityFetcher(),
            recipientDatabaseTable: recipientTable,
            storageServiceManager: FakeStorageServiceManager()
        )
        mockDb.write { tx in
            for testCase in testCases {
                let recipient = recipientFetcher.fetchOrCreate(serviceId: Aci.randomForTesting(), tx: tx)
                recipientManager.setDeviceIds(Set(testCase.initialDeviceIds.map { DeviceId(validating: $0)! }), for: recipient, shouldUpdateStorageService: false)
                recipientManager.markAsRegisteredAndSave(recipient, deviceId: DeviceId(validating: testCase.addedDeviceId)!, shouldUpdateStorageService: false, tx: tx)
                XCTAssertEqual(Set(recipient.deviceIds), Set(testCase.expectedDeviceIds.map { DeviceId(validating: $0)! }), "\(testCase)")
            }
        }
    }
}
