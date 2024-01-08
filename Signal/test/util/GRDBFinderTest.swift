//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit
@testable import Signal
@testable import SignalMessaging

class GRDBFinderTest: SignalBaseTest {
    override func setUp() {
        super.setUp()

        // ensure local client has necessary "registered" state
        let localE164Identifier = "+13235551234"
        let localUUID = UUID()
        databaseStorage.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .init(
                    aci: .init(fromUUID: localUUID),
                    pni: nil,
                    e164: E164(localE164Identifier)!
                ),
                tx: tx.asV2Write
            )
        }
    }

    func testThreadFinder() {

        // Contact Threads
        let address1 = SignalServiceAddress(phoneNumber: "+13213334444")
        let address2 = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+13213334445")
        let address3 = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+13213334446")
        let address4 = SignalServiceAddress.randomForTesting()
        let address5 = SignalServiceAddress(phoneNumber: "+13213334447")
        let address6 = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+13213334448")
        let address7 = SignalServiceAddress.randomForTesting()
        let contactThread1 = TSContactThread(contactAddress: address1)
        let contactThread2 = TSContactThread(contactAddress: address2)
        let contactThread3 = TSContactThread(contactAddress: address3)
        let contactThread4 = TSContactThread(contactAddress: address4)
        // Group Threads
        let createGroupThread: () -> TSGroupThread = {
            var groupThread: TSGroupThread!
            self.write { transaction in
                groupThread = try! GroupManager.createGroupForTests(members: [address1],
                                                                    name: "Test Group",
                                                                    transaction: transaction)
            }
            return groupThread
        }

        self.read { tx in
            XCTAssertNil(ContactThreadFinder().contactThread(for: address1, tx: tx))
            XCTAssertNil(ContactThreadFinder().contactThread(for: address2, tx: tx))
            XCTAssertNil(ContactThreadFinder().contactThread(for: address3, tx: tx))
            XCTAssertNil(ContactThreadFinder().contactThread(for: address4, tx: tx))
            XCTAssertNil(ContactThreadFinder().contactThread(for: address5, tx: tx))
            XCTAssertNil(ContactThreadFinder().contactThread(for: address6, tx: tx))
            XCTAssertNil(ContactThreadFinder().contactThread(for: address7, tx: tx))
        }

        _ = createGroupThread()
        _ = createGroupThread()
        _ = createGroupThread()
        _ = createGroupThread()

        self.write { transaction in
            contactThread1.anyInsert(transaction: transaction)
            contactThread2.anyInsert(transaction: transaction)
            contactThread3.anyInsert(transaction: transaction)
            contactThread4.anyInsert(transaction: transaction)
        }

        self.read { tx in
            XCTAssertNotNil(ContactThreadFinder().contactThread(for: address1, tx: tx))
            XCTAssertNotNil(ContactThreadFinder().contactThread(for: address2, tx: tx))
            XCTAssertNotNil(ContactThreadFinder().contactThread(for: address3, tx: tx))
            XCTAssertNotNil(ContactThreadFinder().contactThread(for: address4, tx: tx))
            XCTAssertNil(ContactThreadFinder().contactThread(for: address5, tx: tx))
            XCTAssertNil(ContactThreadFinder().contactThread(for: address6, tx: tx))
            XCTAssertNil(ContactThreadFinder().contactThread(for: address7, tx: tx))
        }
    }

    func testSignalAccountFinder() {

        // We'll create SignalAccount for these...
        let address1 = SignalServiceAddress(phoneNumber: "+13213334444")
        let address2 = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+13213334445")
        let address3 = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+13213334446")
        let address4 = SignalServiceAddress.randomForTesting()
        // ...but not these.
        let address5 = SignalServiceAddress(phoneNumber: "+13213334447")
        let address6 = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+13213334448")
        let address7 = SignalServiceAddress.randomForTesting()

        self.write { transaction in
            SignalAccount(address: address1).anyInsert(transaction: transaction)
            SignalAccount(address: address2).anyInsert(transaction: transaction)
            SignalAccount(address: address3).anyInsert(transaction: transaction)
            SignalAccount(address: address4).anyInsert(transaction: transaction)
        }

        self.read { tx in
            // These should exist...
            XCTAssertNotNil(SignalAccountFinder().signalAccount(for: address1, tx: tx))
            // If we save a SignalAccount with just a phone number,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(SignalAccountFinder().signalAccount(for: SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: address1.phoneNumber!), tx: tx))
            XCTAssertNotNil(SignalAccountFinder().signalAccount(for: address2, tx: tx))
            // If we save a SignalAccount with just a phone number and UUID,
            // we should later be able to look it up using just a UUID.
            XCTAssertNotNil(SignalAccountFinder().signalAccount(for: SignalServiceAddress(address2.serviceId!), tx: tx))
            // If we save a SignalAccount with just a phone number and UUID,
            // we should later be able to look it up using just a phone number.
            XCTAssertNotNil(SignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address2.phoneNumber!), tx: tx))
            XCTAssertNotNil(SignalAccountFinder().signalAccount(for: address3, tx: tx))
            XCTAssertNotNil(SignalAccountFinder().signalAccount(for: SignalServiceAddress(address3.serviceId!), tx: tx))
            XCTAssertNotNil(SignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address3.phoneNumber!), tx: tx))
            XCTAssertNotNil(SignalAccountFinder().signalAccount(for: address4, tx: tx))
            // If we save a SignalAccount with just a UUID,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(SignalAccountFinder().signalAccount(for: SignalServiceAddress(serviceId: address4.serviceId!, phoneNumber: "+1666777888"), tx: tx))

            // ...these don't.
            XCTAssertNil(SignalAccountFinder().signalAccount(for: address5, tx: tx))
            XCTAssertNil(SignalAccountFinder().signalAccount(for: address6, tx: tx))
            XCTAssertNil(SignalAccountFinder().signalAccount(for: SignalServiceAddress(address6.serviceId!), tx: tx))
            XCTAssertNil(SignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address6.phoneNumber!), tx: tx))
            XCTAssertNil(SignalAccountFinder().signalAccount(for: address7, tx: tx))
        }
    }

    func testSignalRecipientFinder() {

        // We'll create SignalRecipient for these...
        let address1 = SignalServiceAddress(phoneNumber: "+13213334444")
        let address2 = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+13213334445")
        let address3 = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+13213334446")
        let address4 = SignalServiceAddress.randomForTesting()
        // ...but not these.
        let address5 = SignalServiceAddress(phoneNumber: "+13213334447")
        let address6 = SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: "+13213334448")
        let address7 = SignalServiceAddress.randomForTesting()

        self.write { transaction in
            [address1, address2, address3, address4].forEach {
                SignalRecipient(aci: $0.aci, pni: nil, phoneNumber: $0.e164)
                    .anyInsert(transaction: transaction)
            }
        }

        self.read { tx in
            // These should exist...
            XCTAssertNotNil(SignalRecipientFinder().signalRecipient(for: address1, tx: tx))
            // If we save a SignalRecipient with just a phone number,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(SignalRecipientFinder().signalRecipient(for: SignalServiceAddress(serviceId: Aci.randomForTesting(), phoneNumber: address1.phoneNumber!), tx: tx))
            XCTAssertNotNil(SignalRecipientFinder().signalRecipient(for: address2, tx: tx))
            // If we save a SignalRecipient with just a phone number and UUID,
            // we should later be able to look it up using just a UUID.
            XCTAssertNotNil(SignalRecipientFinder().signalRecipient(for: SignalServiceAddress(address2.serviceId!), tx: tx))
            // If we save a SignalRecipient with just a phone number and UUID,
            // we should later be able to look it up using just a phone number.
            XCTAssertNotNil(SignalRecipientFinder().signalRecipient(for: SignalServiceAddress(phoneNumber: address2.phoneNumber!), tx: tx))
            XCTAssertNotNil(SignalRecipientFinder().signalRecipient(for: address3, tx: tx))
            XCTAssertNotNil(SignalRecipientFinder().signalRecipient(for: SignalServiceAddress(address3.serviceId!), tx: tx))
            XCTAssertNotNil(SignalRecipientFinder().signalRecipient(for: SignalServiceAddress(phoneNumber: address3.phoneNumber!), tx: tx))
            XCTAssertNotNil(SignalRecipientFinder().signalRecipient(for: address4, tx: tx))
            // If we save a SignalRecipient with just a UUID,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(SignalRecipientFinder().signalRecipient(for: SignalServiceAddress(serviceId: address4.serviceId!, phoneNumber: "+1666777888"), tx: tx))

            // ...these don't.
            XCTAssertNil(SignalRecipientFinder().signalRecipient(for: address5, tx: tx))
            XCTAssertNil(SignalRecipientFinder().signalRecipient(for: address6, tx: tx))
            XCTAssertNil(SignalRecipientFinder().signalRecipient(for: SignalServiceAddress(address6.serviceId!), tx: tx))
            XCTAssertNil(SignalRecipientFinder().signalRecipient(for: SignalServiceAddress(phoneNumber: address6.phoneNumber!), tx: tx))
            XCTAssertNil(SignalRecipientFinder().signalRecipient(for: address7, tx: tx))
        }
    }

    func testUserProfileFinder_missingAndStaleUserProfiles() {

        let dateWithOffsetFromNow = { (offset: TimeInterval) -> Date in
            return Date(timeInterval: offset, since: Date())
        }

        let finder = UserProfileFinder()

        var expectedAddresses = Set<SignalServiceAddress>()
        self.write { transaction in
            let buildUserProfile = { () -> OWSUserProfile in
                let address = CommonGenerator.address(hasPhoneNumber: true)
                return OWSUserProfile.getOrBuildUserProfile(for: address, authedAccount: .implicit(), transaction: transaction)
            }

            do {
                // This profile is _not_ expected; lastMessagingDate is nil.
                _ = buildUserProfile()
            }

            do {
                // This profile is _not_ expected; lastMessagingDate is nil.
                let userProfile = buildUserProfile()
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
            }

            do {
                // This profile is _not_ expected; lastMessagingDate is nil.
                let userProfile = buildUserProfile()
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMinuteInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
            }

            do {
                // This profile is _not_ expected; lastMessagingDate is old.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-2 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
            }

            do {
                // This profile is _not_ expected; lastMessagingDate is old.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-2 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
            }

            do {
                // This profile is _not_ expected; lastMessagingDate is old.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-2 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMinuteInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
            }

            do {
                // This profile is expected; lastMessagingDate is recent and lastFetchDate is nil.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-1 * kHourInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
                expectedAddresses.insert(userProfile.address)
            }

            do {
                // This profile is expected; lastMessagingDate is recent and lastFetchDate is old.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-1 * kHourInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
                expectedAddresses.insert(userProfile.address)
            }

            do {
                // This profile is _not_ expected; lastFetchDate is recent.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-1 * kHourInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMinuteInterval),
                                   userProfileWriter: .metadataUpdate,
                                   authedAccount: .implicit(),
                                   transaction: transaction)
            }
        }

        var missingAndStaleAddresses = Set<SignalServiceAddress>()
        self.read { transaction in
            finder.enumerateMissingAndStaleUserProfiles(transaction: transaction) { (userProfile: OWSUserProfile) in
                XCTAssertFalse(missingAndStaleAddresses.contains(userProfile.address))
                missingAndStaleAddresses.insert(userProfile.address)
            }
        }

        XCTAssertEqual(expectedAddresses, missingAndStaleAddresses)
    }
}
