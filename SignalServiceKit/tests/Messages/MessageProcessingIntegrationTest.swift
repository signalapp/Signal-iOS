//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
import GRDB
import LibSignalClient

class MessageProcessingIntegrationTest: SSKBaseTest {

    let localE164Identifier = "+13235551234"
    let localAci = Aci.randomForTesting()

    let aliceE164Identifier = "+14715355555"
    var aliceClient: TestSignalClient!

    let bobE164Identifier = "+18083235555"
    var bobClient: TestSignalClient!
    var linkedClient: TestSignalClient!

    private lazy var localClient = LocalSignalClient()
    let runner = TestProtocolRunner()
    lazy var fakeService = FakeService(localClient: localClient, runner: runner)

    // MARK: - Hooks

    override func setUp() {
        super.setUp()

        // ensure local client has necessary "registered" state
        let identityManager = DependenciesBridge.shared.identityManager
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        identityManager.generateAndPersistNewIdentityKey(for: .pni)
        SSKEnvironment.shared.databaseStorageRef.write { tx in
            (DependenciesBridge.shared.registrationStateChangeManager as! RegistrationStateChangeManagerImpl).registerForTests(
                localIdentifiers: .init(
                    aci: localAci,
                    pni: Pni.randomForTesting(),
                    e164: .init(localE164Identifier)!
                ),
                tx: tx.asV2Write
            )
        }

        bobClient = FakeSignalClient.generate(e164Identifier: bobE164Identifier)
        aliceClient = FakeSignalClient.generate(e164Identifier: aliceE164Identifier)
        linkedClient = localClient.linkedDevice(deviceID: 2)
    }

    override func tearDown() {
        try! SSKEnvironment.shared.databaseStorageRef.grdbStorage.testing_tearDownDatabaseChangeObserver()

        super.tearDown()
    }

    // MARK: - Tests

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
        SSKEnvironment.shared.databaseStorageRef.databaseChangeObserver.appendDatabaseWriteDelegate(snapshotDelegate)

        let envelopeBuilder = try! fakeService.envelopeBuilder(fromSenderClient: bobClient, bodyText: "Those who stands for nothing will fall for anything")
        envelopeBuilder.setSourceServiceID(bobClient.serviceId.serviceIdString)
        envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setServerGuid(UUID().uuidString)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        SSKEnvironment.shared.messageProcessorRef.processReceivedEnvelopeData(
            envelopeData,
            serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
            envelopeSource: .tests
        ) { error in
            switch error {
            case MessageProcessingError.replacedEnvelope?:
                XCTFail("replacedEnvelope")
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
        envelopeBuilder.setSourceServiceID(bobClient.serviceId.serviceIdString)
        envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setServerGuid(UUID().uuidString)
        envelopeBuilder.setDestinationServiceID(Aci.randomForTesting().serviceIdString)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        SSKEnvironment.shared.messageProcessorRef.processReceivedEnvelopeData(
            envelopeData,
            serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
            envelopeSource: .tests
        ) { error in
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
        let identityManager = DependenciesBridge.shared.identityManager

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
            XCTAssertFalse(identityManager.shouldSharePhoneNumber(with: bobClient.serviceId, tx: transaction.asV2Read))
        }

        let content = try! fakeService.buildContentData(bodyText: "Those who stands for nothing will fall for anything")
        let ciphertext = SSKEnvironment.shared.databaseStorageRef.write { transaction in
            try! runner.encrypt(content,
                                senderClient: bobClient,
                                recipient: localPniClient.protocolAddress,
                                context: transaction)
        }

        let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: 100)
        envelopeBuilder.setContent(Data(ciphertext.serialize()))
        envelopeBuilder.setType(.prekeyBundle)
        envelopeBuilder.setSourceServiceID(bobClient.serviceId.serviceIdString)
        envelopeBuilder.setSourceDevice(1)
        envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
        envelopeBuilder.setServerGuid(UUID().uuidString)
        envelopeBuilder.setDestinationServiceID(DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction!.pni!.serviceIdString)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        SSKEnvironment.shared.messageProcessorRef.processReceivedEnvelopeData(
            envelopeData,
            serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
            envelopeSource: .tests
        ) { error in
            switch error {
            case let error?:
                XCTFail("failure \(error)")
            case nil:
                break
            }
            self.read { transaction in
                XCTAssert(identityManager.shouldSharePhoneNumber(with: self.bobClient.serviceId, tx: transaction.asV2Read))
            }
        }
        waitForExpectations(timeout: 1.0)
    }

    func testEarlyServerGeneratedDeliveryReceipt() async throws {
        try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            try self.runner.initializePreKeys(senderClient: self.linkedClient, recipientClient: localClient, transaction: tx)
        }

        // Handle a server-generated delivery receipt "from" bob
        let timestamp = UInt64(101)

        do {
            let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: UInt64(timestamp))
            envelopeBuilder.setType(.receipt)
            envelopeBuilder.setServerTimestamp(103)
            envelopeBuilder.setSourceDevice(2)
            envelopeBuilder.setSourceServiceID(self.bobClient.serviceId.serviceIdString)
            let envelopeData = try envelopeBuilder.buildSerializedData()
            try await withCheckedThrowingContinuation { continuation in
                SSKEnvironment.shared.messageProcessorRef.processReceivedEnvelopeData(
                    envelopeData,
                    serverDeliveryTimestamp: 102,
                    envelopeSource: .websocketUnidentified
                ) { error in
                    continuation.resume(with: error.map({ .failure($0) }) ?? .success(()))
                }
            }
        }

        await SSKEnvironment.shared.messageProcessorRef.waitForProcessingComplete().awaitable()

        // Handle a sync message
        // Build message content
        let content = try self.fakeService.buildSyncSentMessage(
            bodyText: "Hello world",
            recipient: self.bobClient.address,
            timestamp: timestamp
        )

        // Encrypt message content
        let ciphertext = try await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { tx in
            try self.runner.encrypt(content, senderClient: self.linkedClient, recipient: self.localClient.protocolAddress, context: tx)
        }

        do {
            // Build the message
            let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: timestamp)
            envelopeBuilder.setContent(Data(ciphertext.serialize()))
            envelopeBuilder.setType(.prekeyBundle)
            envelopeBuilder.setSourceServiceID(self.linkedClient.serviceId.serviceIdString)
            envelopeBuilder.setSourceDevice(2)
            envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
            envelopeBuilder.setServerGuid(UUID().uuidString)
            envelopeBuilder.setDestinationServiceID(self.localClient.serviceId.serviceIdString)
            let envelopeData = try envelopeBuilder.buildSerializedData()

            // Process the message
            try await withCheckedThrowingContinuation { continuation in
                SSKEnvironment.shared.messageProcessorRef.processReceivedEnvelopeData(
                    envelopeData,
                    serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                    envelopeSource: .tests
                ) { error in
                    continuation.resume(with: error.map({ .failure($0) }) ?? .success(()))
                }
            }
        }
        try SSKEnvironment.shared.databaseStorageRef.read { transaction in
            // Now make sure the status is delivered.
            let fetched = try InteractionFinder.interactions(
                withTimestamp: timestamp,
                filter: { _ in true },
                transaction: transaction
            ).compactMap { $0 as? TSOutgoingMessage }
            XCTAssertNotNil(fetched.first)
            let message = fetched.first!
            let recipientState = message.recipientState(for: self.bobClient.address)
            XCTAssertNotNil(recipientState)
            XCTAssertEqual(recipientState?.status, .delivered)
            let deliveryTimestamp = recipientState?.statusTimestamp
            XCTAssertNotNil(deliveryTimestamp)
            XCTAssert((deliveryTimestamp ?? 0) > 1650000000000)
        }
    }

    @MainActor
    func testEarlyUDDeliveryReceipt() async throws {
        write { transaction in
            try! self.runner.initialize(senderClient: self.linkedClient,
                                        recipientClient: localClient,
                                        transaction: transaction)
            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: self.localClient,
                                        transaction: transaction)
        }

        // Handle a UD receipt from Bob.
        // It's okay that sealed sender isn't actually being used here. It's a receipt for a message as if /sent/ by UD,
        // not /received/ by UD.
        let timestamp = UInt64(101)
        let deliveryTimestamp = UInt64(103)

        do {
            let ciphertextData = try fakeService.buildEncryptedContentData(
                fromSenderClient: self.bobClient,
                deliveryReceiptForMessage: timestamp
            )
            let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: deliveryTimestamp)
            envelopeBuilder.setContent(ciphertextData)
            envelopeBuilder.setType(.ciphertext)
            envelopeBuilder.setSourceServiceID(bobClient.serviceId.serviceIdString)
            envelopeBuilder.setSourceDevice(1)
            envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
            envelopeBuilder.setServerGuid(UUID().uuidString)
            envelopeBuilder.setDestinationServiceID(self.localClient.serviceId.serviceIdString)
            let envelopeData = try envelopeBuilder.buildSerializedData()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                SSKEnvironment.shared.messageProcessorRef.processReceivedEnvelopeData(
                    envelopeData,
                    serverDeliveryTimestamp: 102,
                    envelopeSource: .websocketUnidentified
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
        }

        do {
            // Handle a sync message
            // Build message content
            let content = try! self.fakeService.buildSyncSentMessage(bodyText: "Hello world",
                                                                     recipient: self.bobClient.address,
                                                                     timestamp: timestamp)

            // Encrypt message content
            let ciphertext = SSKEnvironment.shared.databaseStorageRef.write { transaction in
                try! self.runner.encrypt(content,
                                         senderClient: self.linkedClient,
                                         recipient: self.localClient.protocolAddress,
                                         context: transaction)
            }

            // Build the message
            let envelopeBuilder = SSKProtoEnvelope.builder(timestamp: timestamp)
            envelopeBuilder.setContent(Data(ciphertext.serialize()))
            envelopeBuilder.setType(.ciphertext)
            envelopeBuilder.setSourceServiceID(self.linkedClient.serviceId.serviceIdString)
            envelopeBuilder.setSourceDevice(2)
            envelopeBuilder.setServerTimestamp(NSDate.ows_millisecondTimeStamp())
            envelopeBuilder.setServerGuid(UUID().uuidString)
            envelopeBuilder.setDestinationServiceID(self.localClient.serviceId.serviceIdString)
            let envelopeData = try! envelopeBuilder.buildSerializedData()

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Process the message
                SSKEnvironment.shared.messageProcessorRef.processReceivedEnvelopeData(
                    envelopeData,
                    serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp(),
                    envelopeSource: .tests
                ) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                }
            }
            self.read { transaction in
                // Now make sure the status is delivered.
                let fetched = try! InteractionFinder.interactions(
                    withTimestamp: timestamp,
                    filter: { _ in true },
                    transaction: transaction
                ).compactMap { $0 as? TSOutgoingMessage }
                XCTAssertNotNil(fetched.first)
                let message = fetched.first!
                let recipientState = message.recipientState(for: self.bobClient.address)
                XCTAssertNotNil(recipientState)
                XCTAssertEqual(recipientState?.status, .delivered)
                let actualDeliveryTimestamp = recipientState?.statusTimestamp
                XCTAssertNotNil(actualDeliveryTimestamp)
                XCTAssertEqual(actualDeliveryTimestamp, deliveryTimestamp)
            }
        }
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
