//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

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
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)
    }

    func testAnyThreadFinder() {

        // Contact Threads
        let address1 = SignalServiceAddress(phoneNumber: "+13213334444")
        let address2 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334445")
        let address3 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334446")
        let address4 = SignalServiceAddress(uuid: UUID())
        let address5 = SignalServiceAddress(phoneNumber: "+13213334447")
        let address6 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334448")
        let address7 = SignalServiceAddress(uuid: UUID())
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

        self.read { transaction in
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address1, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address2, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address3, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address4, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address5, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address6, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address7, transaction: transaction))
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

        self.read { transaction in
            XCTAssertNotNil(AnyContactThreadFinder().contactThread(for: address1, transaction: transaction))
            XCTAssertNotNil(AnyContactThreadFinder().contactThread(for: address2, transaction: transaction))
            XCTAssertNotNil(AnyContactThreadFinder().contactThread(for: address3, transaction: transaction))
            XCTAssertNotNil(AnyContactThreadFinder().contactThread(for: address4, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address5, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address6, transaction: transaction))
            XCTAssertNil(AnyContactThreadFinder().contactThread(for: address7, transaction: transaction))
        }
    }

    func testAnySignalAccountFinder() {

        // We'll create SignalAccount for these...
        let address1 = SignalServiceAddress(phoneNumber: "+13213334444")
        let address2 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334445")
        let address3 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334446")
        let address4 = SignalServiceAddress(uuid: UUID())
        // ...but not these.
        let address5 = SignalServiceAddress(phoneNumber: "+13213334447")
        let address6 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334448")
        let address7 = SignalServiceAddress(uuid: UUID())

        self.write { transaction in
            SignalAccount(address: address1).anyInsert(transaction: transaction)
            SignalAccount(address: address2).anyInsert(transaction: transaction)
            SignalAccount(address: address3).anyInsert(transaction: transaction)
            SignalAccount(address: address4).anyInsert(transaction: transaction)
        }

        self.read { transaction in
            // These should exist...
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: address1, transaction: transaction))
            // If we save a SignalAccount with just a phone number,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: UUID(), phoneNumber: address1.phoneNumber!), transaction: transaction))
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: address2, transaction: transaction))
            // If we save a SignalAccount with just a phone number and UUID,
            // we should later be able to look it up using just a UUID.
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address2.uuid!), transaction: transaction))
            // If we save a SignalAccount with just a phone number and UUID,
            // we should later be able to look it up using just a phone number.
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address2.phoneNumber!), transaction: transaction))
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: address3, transaction: transaction))
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address3.uuid!), transaction: transaction))
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address3.phoneNumber!), transaction: transaction))
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: address4, transaction: transaction))
            // If we save a SignalAccount with just a UUID,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address4.uuid!, phoneNumber: "+1666777888"), transaction: transaction))

            // ...these don't.
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address5, transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address6, transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(uuid: address6.uuid!), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: SignalServiceAddress(phoneNumber: address6.phoneNumber!), transaction: transaction))
            XCTAssertNil(AnySignalAccountFinder().signalAccount(for: address7, transaction: transaction))
        }
    }

    func testAnySignalRecipientFinder() {

        // We'll create SignalRecipient for these...
        let address1 = SignalServiceAddress(phoneNumber: "+13213334444")
        let address2 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334445")
        let address3 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334446")
        let address4 = SignalServiceAddress(uuid: UUID())
        // ...but not these.
        let address5 = SignalServiceAddress(phoneNumber: "+13213334447")
        let address6 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334448")
        let address7 = SignalServiceAddress(uuid: UUID())

        self.write { transaction in
            SignalRecipient(address: address1).anyInsert(transaction: transaction)
            SignalRecipient(address: address2).anyInsert(transaction: transaction)
            SignalRecipient(address: address3).anyInsert(transaction: transaction)
            SignalRecipient(address: address4).anyInsert(transaction: transaction)
        }

        self.read { transaction in
            // These should exist...
            XCTAssertNotNil(AnySignalRecipientFinder().signalRecipient(for: address1, transaction: transaction))
            // If we save a SignalRecipient with just a phone number,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(AnySignalRecipientFinder().signalRecipient(for: SignalServiceAddress(uuid: UUID(), phoneNumber: address1.phoneNumber!), transaction: transaction))
            XCTAssertNotNil(AnySignalRecipientFinder().signalRecipient(for: address2, transaction: transaction))
            // If we save a SignalRecipient with just a phone number and UUID,
            // we should later be able to look it up using just a UUID.
            XCTAssertNotNil(AnySignalRecipientFinder().signalRecipient(for: SignalServiceAddress(uuid: address2.uuid!), transaction: transaction))
            // If we save a SignalRecipient with just a phone number and UUID,
            // we should later be able to look it up using just a phone number.
            XCTAssertNotNil(AnySignalRecipientFinder().signalRecipient(for: SignalServiceAddress(phoneNumber: address2.phoneNumber!), transaction: transaction))
            XCTAssertNotNil(AnySignalRecipientFinder().signalRecipient(for: address3, transaction: transaction))
            XCTAssertNotNil(AnySignalRecipientFinder().signalRecipient(for: SignalServiceAddress(uuid: address3.uuid!), transaction: transaction))
            XCTAssertNotNil(AnySignalRecipientFinder().signalRecipient(for: SignalServiceAddress(phoneNumber: address3.phoneNumber!), transaction: transaction))
            XCTAssertNotNil(AnySignalRecipientFinder().signalRecipient(for: address4, transaction: transaction))
            // If we save a SignalRecipient with just a UUID,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(AnySignalRecipientFinder().signalRecipient(for: SignalServiceAddress(uuid: address4.uuid!, phoneNumber: "+1666777888"), transaction: transaction))

            // ...these don't.
            XCTAssertNil(AnySignalRecipientFinder().signalRecipient(for: address5, transaction: transaction))
            XCTAssertNil(AnySignalRecipientFinder().signalRecipient(for: address6, transaction: transaction))
            XCTAssertNil(AnySignalRecipientFinder().signalRecipient(for: SignalServiceAddress(uuid: address6.uuid!), transaction: transaction))
            XCTAssertNil(AnySignalRecipientFinder().signalRecipient(for: SignalServiceAddress(phoneNumber: address6.phoneNumber!), transaction: transaction))
            XCTAssertNil(AnySignalRecipientFinder().signalRecipient(for: address7, transaction: transaction))
        }
    }

    func testAnyMessageContentJobFinder() {

        let finder = AnyMessageContentJobFinder()

        let randomData: () -> Data = {
            return Randomness.generateRandomBytes(32)
        }

        self.write { transaction in
            for _ in (0..<4) {
                finder.addJob(envelopeData: randomData(),
                              plaintextData: randomData(),
                              wasReceivedByUD: false,
                              serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                              transaction: transaction)
            }
        }

        self.read { transaction in
            XCTAssertEqual(2, finder.nextJobs(batchSize: 2, transaction: transaction).count)
            XCTAssertEqual(4, finder.nextJobs(batchSize: 10, transaction: transaction).count)
            XCTAssertEqual(4, finder.jobCount(transaction: transaction))
        }

        self.write { transaction in
            let batch = finder.nextJobs(batchSize: 10, transaction: transaction)
            let firstJob = batch[0]
            finder.removeJobs(withUniqueIds: [firstJob.uniqueId], transaction: transaction)
        }

        self.read { transaction in
            XCTAssertEqual(2, finder.nextJobs(batchSize: 2, transaction: transaction).count)
            XCTAssertEqual(3, finder.nextJobs(batchSize: 10, transaction: transaction).count)
            XCTAssertEqual(3, finder.jobCount(transaction: transaction))
        }
    }

    func testAnyUserProfileFinder_missingAndStaleUserProfiles() {

        let dateWithOffsetFromNow = { (offset: TimeInterval) -> Date in
            return Date(timeInterval: offset, since: Date())
        }

        let finder = AnyUserProfileFinder()

        var expectedAddresses = Set<SignalServiceAddress>()
        self.write { transaction in
            let buildUserProfile = { () -> OWSUserProfile in
                let address = CommonGenerator.address(hasPhoneNumber: true)
                return OWSUserProfile.getOrBuild(for: address, transaction: transaction)
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
                                   transaction: transaction)
            }

            do {
                // This profile is _not_ expected; lastMessagingDate is nil.
                let userProfile = buildUserProfile()
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMinuteInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
            }

            do {
                // This profile is _not_ expected; lastMessagingDate is old.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-2 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
            }

            do {
                // This profile is _not_ expected; lastMessagingDate is old.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-2 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
            }

            do {
                // This profile is _not_ expected; lastMessagingDate is old.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-2 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMinuteInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
            }

            do {
                // This profile is expected; lastMessagingDate is recent and lastFetchDate is nil.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-1 * kHourInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
                expectedAddresses.insert(userProfile.address)
                userProfile.logDates(prefix: "Expected profile")
            }

            do {
                // This profile is expected; lastMessagingDate is recent and lastFetchDate is old.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-1 * kHourInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMonthInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
                expectedAddresses.insert(userProfile.address)
                userProfile.logDates(prefix: "Expected profile")
            }

            do {
                // This profile is _not_ expected; lastFetchDate is recent.
                let userProfile = buildUserProfile()
                userProfile.update(lastMessagingDate: dateWithOffsetFromNow(-1 * kHourInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
                userProfile.update(lastFetchDate: dateWithOffsetFromNow(-1 * kMinuteInterval),
                                   userProfileWriter: .metadataUpdate,
                                   transaction: transaction)
            }
        }

        var missingAndStaleAddresses = Set<SignalServiceAddress>()
        self.read { transaction in
            OWSUserProfile.anyEnumerate(transaction: transaction) { (userProfile: OWSUserProfile, _) in
                userProfile.logDates(prefix: "Considering profile")
            }

            finder.enumerateMissingAndStaleUserProfiles(transaction: transaction) { (userProfile: OWSUserProfile) in
                userProfile.logDates(prefix: "Missing or stale profile")
                XCTAssertFalse(missingAndStaleAddresses.contains(userProfile.address))
                missingAndStaleAddresses.insert(userProfile.address)
            }
        }

        Logger.verbose("expectedAddresses: \(expectedAddresses)")
        Logger.verbose("missingAndStaleAddresses: \(missingAndStaleAddresses)")
        XCTAssertEqual(expectedAddresses, missingAndStaleAddresses)
    }
}
