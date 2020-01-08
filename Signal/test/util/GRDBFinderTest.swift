//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit
@testable import Signal
@testable import SignalMessaging

class GRDBFinderTest: SignalBaseTest {

    // MARK: - Dependencies

    var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    // MARK: -

    override func setUp() {
        super.setUp()

        storageCoordinator.useGRDBForTests()
    }

    override func tearDown() {
        super.tearDown()
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

    func testAnyLinkedDeviceReadReceiptFinder() {
        let messageIdTimestamp: UInt64 = 123456
        let readTimestamp: UInt64 = 234567

        // We'll create OWSLinkedDeviceReadReceipt for these...
        let address1 = SignalServiceAddress(phoneNumber: "+13213334444")
        let address2 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334445")
        let address3 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334446")
        let address4 = SignalServiceAddress(uuid: UUID())
        // ...but not these.
        let address5 = SignalServiceAddress(phoneNumber: "+13213334447")
        let address6 = SignalServiceAddress(uuid: UUID(), phoneNumber: "+13213334448")
        let address7 = SignalServiceAddress(uuid: UUID())

        self.write { transaction in
            OWSLinkedDeviceReadReceipt(senderAddress: address1, messageIdTimestamp: messageIdTimestamp, readTimestamp: readTimestamp).anyInsert(transaction: transaction)
            OWSLinkedDeviceReadReceipt(senderAddress: address2, messageIdTimestamp: messageIdTimestamp, readTimestamp: readTimestamp).anyInsert(transaction: transaction)
            OWSLinkedDeviceReadReceipt(senderAddress: address3, messageIdTimestamp: messageIdTimestamp, readTimestamp: readTimestamp).anyInsert(transaction: transaction)
            OWSLinkedDeviceReadReceipt(senderAddress: address4, messageIdTimestamp: messageIdTimestamp, readTimestamp: readTimestamp).anyInsert(transaction: transaction)
        }

        self.read { transaction in
            // These should exist...
            XCTAssertNotNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: address1, andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            // If we save a OWSLinkedDeviceReadReceipt with just a phone number,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: SignalServiceAddress(uuid: UUID(), phoneNumber: address1.phoneNumber!), andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            XCTAssertNotNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: address2, andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            // If we save a OWSLinkedDeviceReadReceipt with just a phone number and UUID,
            // we should later be able to look it up using just a UUID.
            XCTAssertNotNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: SignalServiceAddress(uuid: address2.uuid!), andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            // If we save a OWSLinkedDeviceReadReceipt with just a phone number and UUID,
            // we should later be able to look it up using just a phone number.
            XCTAssertNotNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: SignalServiceAddress(phoneNumber: address2.phoneNumber!), andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            XCTAssertNotNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: address3, andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            XCTAssertNotNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: SignalServiceAddress(uuid: address3.uuid!), andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            XCTAssertNotNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: SignalServiceAddress(phoneNumber: address3.phoneNumber!), andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            XCTAssertNotNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: address4, andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            // If we save a OWSLinkedDeviceReadReceipt with just a UUID,
            // we should later be able to look it up using a UUID & phone number,
            XCTAssertNotNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: SignalServiceAddress(uuid: address4.uuid!, phoneNumber: "+1666777888"), andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))

            // ...these don't.
            XCTAssertNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: address5, andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            XCTAssertNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: address6, andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            XCTAssertNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: SignalServiceAddress(uuid: address6.uuid!), andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            XCTAssertNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: SignalServiceAddress(phoneNumber: address6.phoneNumber!), andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
            XCTAssertNil(AnyLinkedDeviceReadReceiptFinder().linkedDeviceReadReceipt(for: address7, andMessageIdTimestamp: messageIdTimestamp, transaction: transaction))
        }
    }

    func testAnyMessageContentJobFinder() {

        let finder = AnyMessageContentJobFinder()

        let randomData: () -> Data = {
            return Randomness.generateRandomBytes(32)
        }

        self.write { transaction in
            finder.addJob(envelopeData: randomData(), plaintextData: randomData(), wasReceivedByUD: false, transaction: transaction)
            finder.addJob(envelopeData: randomData(), plaintextData: randomData(), wasReceivedByUD: false, transaction: transaction)
            finder.addJob(envelopeData: randomData(), plaintextData: randomData(), wasReceivedByUD: false, transaction: transaction)
            finder.addJob(envelopeData: randomData(), plaintextData: randomData(), wasReceivedByUD: false, transaction: transaction)
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
}
