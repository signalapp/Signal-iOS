//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
import GRDB
import LibSignalClient

class MessageProcessingIntegrationTest: SSKBaseTestSwift {

    let localE164Identifier = "+13235551234"
    let localUUID = UUID()

    let aliceE164Identifier = "+14715355555"
    var aliceClient: TestSignalClient!

    let bobE164Identifier = "+18083235555"
    var bobClient: TestSignalClient!
    var linkedClient: TestSignalClient!

    let localClient = LocalSignalClient()
    let runner = TestProtocolRunner()
    lazy var fakeService = FakeService(localClient: localClient, runner: runner)

    // MARK: - Hooks

    override func setUp() {
        super.setUp()

        // Use DatabaseChangeObserver to be notified of DB writes so we
        // can verify the expected changes occur.
        try! databaseStorage.grdbStorage.setupDatabaseChangeObserver()

        // ensure local client has necessary "registered" state
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        identityManager.generateAndPersistNewIdentityKey(for: .pni)
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID, pni: UUID())

        bobClient = FakeSignalClient.generate(e164Identifier: bobE164Identifier)
        aliceClient = FakeSignalClient.generate(e164Identifier: aliceE164Identifier)
        linkedClient = localClient.linkedDevice(deviceID: 2)
    }

    override func tearDown() {
        databaseStorage.grdbStorage.testing_tearDownDatabaseChangeObserver()

        super.tearDown()
    }

    // MARK: - Tests

    func test_contactMessage_e164AndUuidEnvelope() {
        write { transaction in
            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: self.localClient,
                                        transaction: transaction)
        }

        // Wait until message processing has completed, otherwise future
        // tests may break as we try and drain the processing queue.
        let expectFlushNotification = expectation(description: "queue flushed")
        NotificationCenter.default.observe(once: MessageProcessor.messageProcessorDidDrainQueue).done { _ in
            expectFlushNotification.fulfill()
        }

        let expectMessageProcessed = expectation(description: "message processed")
        // This test fulfills an expectation when a write to the database causes the desired state to be reached.
        // However, there may still be writes to the database in flight, and the *next* write will also probably
        // be in the desired state, resulting in the expectation being fulfilled again.
        expectMessageProcessed.assertForOverFulfill = false

        read { transaction in
            XCTAssertEqual(0, TSMessage.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))
        }

        let databaseDelegate = DatabaseWriteBlockDelegate { _ in
            self.read { transaction in
                // Each time a write occurs, check to see if we've achieved the expected DB state.
                //
                // There are multiple writes that occur before the desired state is achieved, but
                // this block is called after each one, so it must be forgiving for the prior writes.
                if let message = TSMessage.anyFetchAll(transaction: transaction).first as? TSIncomingMessage {
                    XCTAssertEqual(1, TSMessage.anyCount(transaction: transaction))
                    XCTAssertEqual(message.authorAddress, self.bobClient.address)
                    XCTAssertNotEqual(message.authorAddress, self.aliceClient.address)
                    XCTAssertEqual(message.body, "Those who stands for nothing will fall for anything")
                    XCTAssertEqual(1, TSThread.anyCount(transaction: transaction))
                    guard let thread = TSThread.anyFetchAll(transaction: transaction).first as? TSContactThread else {
                        XCTFail("thread was unexpectedly nil")
                        return
                    }
                    XCTAssertEqual(thread.contactAddress, self.bobClient.address)
                    XCTAssertNotEqual(thread.contactAddress, self.aliceClient.address)
                    expectMessageProcessed.fulfill()
                }
            }
        }
        guard let observer = databaseStorage.grdbStorage.databaseChangeObserver else {
            owsFailDebug("observer was unexpectedly nil")
            return
        }
        observer.appendDatabaseWriteDelegate(databaseDelegate)

        let envelopeBuilder = try! fakeService.envelopeBuilder(fromSenderClient: bobClient, bodyText: "Those who stands for nothing will fall for anything")
        envelopeBuilder.setSourceUuid(bobClient.uuidIdentifier)
        envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setServerGuid(UUID().uuidString)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        messageProcessor.processEncryptedEnvelopeData(envelopeData,
                                                      serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                      envelopeSource: .tests) { error in
            switch error {
            case MessageProcessingError.duplicatePendingEnvelope?:
                XCTFail("duplicatePendingEnvelope")
            case .some:
                XCTFail("failure")
            case nil:
                break
            }
        }

        waitForExpectations(timeout: 1.0)
    }

    func test_contactMessage_UuidOnlyEnvelope() {
        write { transaction in
            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: self.localClient,
                                        transaction: transaction)
        }

        // Wait until message processing has completed, otherwise future
        // tests may break as we try and drain the processing queue.
        let expectFlushNotification = expectation(description: "queue flushed")
        NotificationCenter.default.observe(once: MessageProcessor.messageProcessorDidDrainQueue).done { _ in
            expectFlushNotification.fulfill()
        }

        let expectMessageProcessed = expectation(description: "message processed")
        // This test fulfills an expectation when a write to the database causes the desired state to be reached.
        // However, there may still be writes to the database in flight, and the *next* write will also probably
        // be in the desired state, resulting in the expectation being fulfilled again.
        expectMessageProcessed.assertForOverFulfill = false

        read { transaction in
            XCTAssertEqual(0, TSMessage.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))
        }

        let snapshotDelegate = DatabaseWriteBlockDelegate { _ in
            self.read { transaction in
                // Each time a write occurs, check to see if we've achieved the expected DB state.
                //
                // There are multiple writes that occur before the desired state is achieved, but
                // this block is called after each one, so it must be forgiving for the prior writes.
                if let message = TSMessage.anyFetchAll(transaction: transaction).first as? TSIncomingMessage {
                    XCTAssertEqual(1, TSMessage.anyCount(transaction: transaction))
                    XCTAssertEqual(message.authorAddress, self.bobClient.address)
                    XCTAssertNotEqual(message.authorAddress, self.aliceClient.address)
                    XCTAssertEqual(message.body, "Those who stands for nothing will fall for anything")
                    XCTAssertEqual(1, TSThread.anyCount(transaction: transaction))
                    guard let thread = TSThread.anyFetchAll(transaction: transaction).first as? TSContactThread else {
                        XCTFail("thread was unexpectedly nil")
                        return
                    }
                    XCTAssertEqual(thread.contactAddress, self.bobClient.address)
                    XCTAssertNotEqual(thread.contactAddress, self.aliceClient.address)

                    expectMessageProcessed.fulfill()
                }
            }
        }
        guard let observer = databaseStorage.grdbStorage.databaseChangeObserver else {
            owsFailDebug("observer was unexpectedly nil")
            return
        }
        observer.appendDatabaseWriteDelegate(snapshotDelegate)

        let envelopeBuilder = try! fakeService.envelopeBuilder(fromSenderClient: bobClient, bodyText: "Those who stands for nothing will fall for anything")
        envelopeBuilder.setSourceUuid(bobClient.uuidIdentifier)
        envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setServerGuid(UUID().uuidString)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        messageProcessor.processEncryptedEnvelopeData(envelopeData,
                                                      serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                      envelopeSource: .tests) { error in
            switch error {
            case MessageProcessingError.duplicatePendingEnvelope?:
                XCTFail("duplicatePendingEnvelope")
            case .some:
                XCTFail("failure")
            case nil:
                break
            }
        }
        waitForExpectations(timeout: 1.0)
    }

    func testWrongDestinationUuid() {
        write { transaction in
            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: self.localClient,
                                        transaction: transaction)
        }

        // Wait until message processing has completed, otherwise future
        // tests may break as we try and drain the processing queue.
        let expectFlushNotification = expectation(description: "queue flushed")
        NotificationCenter.default.observe(once: MessageProcessor.messageProcessorDidDrainQueue).done { _ in
            expectFlushNotification.fulfill()
        }

        let envelopeBuilder = try! fakeService.envelopeBuilder(fromSenderClient: bobClient, bodyText: "Those who stands for nothing will fall for anything")
        envelopeBuilder.setSourceUuid(bobClient.uuidIdentifier)
        envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setServerGuid(UUID().uuidString)
        envelopeBuilder.setDestinationUuid(UUID().uuidString)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        messageProcessor.processEncryptedEnvelopeData(envelopeData,
                                                      serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                      envelopeSource: .tests) { error in
            switch error {
            case MessageProcessingError.wrongDestinationUuid?:
                break
            case let error?:
                XCTFail("unexpected error \(error)")
            case nil:
                XCTFail("should have failed")
            }
        }
        waitForExpectations(timeout: 1.0)
    }

    func testPniMessage() {
        let localPniClient = LocalSignalClient(identity: .pni)
        write { transaction in
            try! self.runner.initializePreKeys(senderClient: self.bobClient,
                                               recipientClient: localPniClient,
                                               transaction: transaction)
        }

        // Wait until message processing has completed, otherwise future
        // tests may break as we try and drain the processing queue.
        _ = expectation(forNotification: MessageProcessor.messageProcessorDidDrainQueue, object: nil)

        read { transaction in
            XCTAssertEqual(0, TSMessage.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))
            XCTAssertFalse(self.identityManager.shouldSharePhoneNumber(with: bobClient.address,
                                                                       transaction: transaction))
        }

        let content = try! fakeService.buildContentData(bodyText: "Those who stands for nothing will fall for anything")
        let ciphertext = databaseStorage.write { transaction in
            try! runner.encrypt(content,
                                senderClient: bobClient,
                                recipient: localPniClient.protocolAddress,
                                context: transaction)
        }

        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: 100)
        envelopeBuilder.setContent(Data(ciphertext.serialize()))
        envelopeBuilder.setType(.prekeyBundle)
        envelopeBuilder.setSourceUuid(bobClient.uuidIdentifier)
        envelopeBuilder.setSourceDevice(1)
        envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setServerGuid(UUID().uuidString)
        envelopeBuilder.setDestinationUuid(tsAccountManager.localPni!.uuidString)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        messageProcessor.processEncryptedEnvelopeData(envelopeData,
                                                      serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                      envelopeSource: .tests) { error in
            switch error {
            case let error?:
                XCTFail("failure \(error)")
            case nil:
                break
            }
            self.read { transaction in
                XCTAssert(self.identityManager.shouldSharePhoneNumber(with: self.bobClient.address,
                                                                      transaction: transaction))
            }
        }
        waitForExpectations(timeout: 1.0)
    }

    func testEarlyServerGeneratedDeliveryReceipt() throws {
        write { transaction in
            try! self.runner.initializePreKeys(senderClient: self.linkedClient,
                                               recipientClient: localClient,
                                               transaction: transaction)
        }

        let expectation = expectation(description: "message processed")

        // Handle a server-generated delivery receipt "from" bob
        let timestamp = UInt64(101)

        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: UInt64(timestamp))
        envelopeBuilder.setType(.receipt)
        envelopeBuilder.setServerTimestamp(103)
        envelopeBuilder.setSourceDevice(2)
        envelopeBuilder.setSourceUuid(self.bobClient.uuidIdentifier)
        let envelopeData = try envelopeBuilder.buildSerializedData()
        messageProcessor.processEncryptedEnvelopeData(envelopeData,
                                                      serverDeliveryTimestamp: 102,
                                                      envelopeSource: .websocketUnidentified) { error in
            XCTAssertNil(error)

            // Handle a sync message
            // Build message content
            let content = try! self.fakeService.buildSyncSentMessage(bodyText: "Hello world",
                                                                     recipient: self.bobClient.address,
                                                                     timestamp: timestamp)

            // Encrypt message content
            let ciphertext = self.databaseStorage.write { transaction in
                try! self.runner.encrypt(content,
                                         senderClient: self.linkedClient,
                                         recipient: self.localClient.protocolAddress,
                                         context: transaction)
            }

            // Build the message
            let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: timestamp)
            envelopeBuilder.setContent(Data(ciphertext.serialize()))
            envelopeBuilder.setType(.prekeyBundle)
            envelopeBuilder.setSourceUuid(self.linkedClient.uuidIdentifier)
            envelopeBuilder.setSourceDevice(2)
            envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
            envelopeBuilder.setServerGuid(UUID().uuidString)
            envelopeBuilder.setDestinationUuid(self.localClient.uuidIdentifier)
            let envelopeData = try! envelopeBuilder.buildSerializedData()

            // Process the message
            self.messageProcessor.processEncryptedEnvelopeData(envelopeData,
                                                               serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                               envelopeSource: .tests) { error in
                switch error {
                case let error?:
                    XCTFail("failure \(error)")
                case nil:
                    self.read { transaction in
                        // Now make sure the status is delivered.
                        let fetched = try! InteractionFinder.interactions(withTimestamp: timestamp,
                                                                          filter: { _ in true },
                                                                          transaction: transaction).compactMap { $0 as? TSOutgoingMessage }
                        XCTAssertNotNil(fetched.first)
                        let message = fetched.first!
                        let deliveryTimestamp = message.recipientAddressStates?[self.bobClient.address]?.deliveryTimestamp
                        XCTAssertNotNil(deliveryTimestamp)
                        XCTAssertGreaterThan(deliveryTimestamp!.uintValue, 1650000000000)
                        expectation.fulfill()
                    }
                }
            }
        }

        wait(for: [expectation], timeout: IsDebuggerAttached() ? .infinity : 1.0)
    }

    func testEarlyUDDeliveryReceipt() throws {
        write { transaction in
            try! self.runner.initialize(senderClient: self.linkedClient,
                                        recipientClient: localClient,
                                        transaction: transaction)
            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: self.localClient,
                                        transaction: transaction)
        }

        let expectation = expectation(description: "message processed")

        // Handle a UD receipt from Bob.
        // It's okay that sealed sender isn't actually being used here. It's a receipt for a message as if /sent/ by UD,
        // not /received/ by UD.
        let timestamp = UInt64(101)

        let ciphertextData = try fakeService.buildEncryptedContentData(fromSenderClient: self.bobClient,
                                                                       deliveryReceiptForMessage: timestamp)
        let deliveryTimestamp = UInt64(103)
        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: deliveryTimestamp)
        envelopeBuilder.setContent(ciphertextData)
        envelopeBuilder.setType(.ciphertext)
        envelopeBuilder.setSourceUuid(bobClient.uuidIdentifier)
        envelopeBuilder.setSourceDevice(1)
        envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setServerGuid(UUID().uuidString)
        envelopeBuilder.setDestinationUuid(self.localClient.uuidIdentifier)
        let envelopeData = try envelopeBuilder.buildSerializedData()

        messageProcessor.processEncryptedEnvelopeData(envelopeData,
                                                      serverDeliveryTimestamp: 102,
                                                      envelopeSource: .websocketUnidentified) { error in
            XCTAssertNil(error)

            // Handle a sync message
            // Build message content
            let content = try! self.fakeService.buildSyncSentMessage(bodyText: "Hello world",
                                                                     recipient: self.bobClient.address,
                                                                     timestamp: timestamp)

            // Encrypt message content
            let ciphertext = self.databaseStorage.write { transaction in
                try! self.runner.encrypt(content,
                                         senderClient: self.linkedClient,
                                         recipient: self.localClient.protocolAddress,
                                         context: transaction)
            }

            // Build the message
            let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: timestamp)
            envelopeBuilder.setContent(Data(ciphertext.serialize()))
            envelopeBuilder.setType(.ciphertext)
            envelopeBuilder.setSourceUuid(self.linkedClient.uuidIdentifier)
            envelopeBuilder.setSourceDevice(2)
            envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
            envelopeBuilder.setServerGuid(UUID().uuidString)
            envelopeBuilder.setDestinationUuid(self.localClient.uuidIdentifier)
            let envelopeData = try! envelopeBuilder.buildSerializedData()

            // Process the message
            self.messageProcessor.processEncryptedEnvelopeData(envelopeData,
                                                               serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                                                               envelopeSource: .tests) { error in
                switch error {
                case let error?:
                    XCTFail("failure \(error)")
                case nil:
                    self.read { transaction in
                        // Now make sure the status is delivered.
                        let fetched = try! InteractionFinder.interactions(withTimestamp: timestamp,
                                                                          filter: { _ in true },
                                                                          transaction: transaction).compactMap { $0 as? TSOutgoingMessage }
                        XCTAssertNotNil(fetched.first)
                        let message = fetched.first!
                        let actualDeliveryTimestamp = message.recipientAddressStates?[self.bobClient.address]?.deliveryTimestamp
                        XCTAssertNotNil(actualDeliveryTimestamp)
                        XCTAssertEqual(actualDeliveryTimestamp!.uint64Value, deliveryTimestamp)
                        expectation.fulfill()
                    }
                }
            }
        }

        wait(for: [expectation], timeout: IsDebuggerAttached() ? .infinity : 1.0)
    }
}

// MARK: - Helpers

class DatabaseWriteBlockDelegate {
    let block: (Database) -> Void
    init(block: @escaping (Database) -> Void) {
        self.block = block
    }
}

extension DatabaseWriteBlockDelegate: DatabaseWriteDelegate {

    func databaseDidChange(with event: DatabaseEvent) { /* no-op */ }
    func databaseDidCommit(db: Database) {
        block(db)
    }
    func databaseDidRollback(db: Database) { /* no-op */ }
}
