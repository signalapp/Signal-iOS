//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit
import GRDB

class MessageProcessingIntegrationTest: SSKBaseTestSwift {

    // MARK: - Dependencies

    var messageReceiver: OWSMessageReceiver {
        return SSKEnvironment.shared.messageReceiver
    }

    var tsAccountManager: TSAccountManager {
        return SSKEnvironment.shared.tsAccountManager
    }

    var identityManager: OWSIdentityManager {
        return SSKEnvironment.shared.identityManager
    }

    var storageCoordinator: StorageCoordinator {
        return SSKEnvironment.shared.storageCoordinator
    }

    // MARK: -

    let localE164Identifier = "+13235551234"
    let localUUID = UUID()

    let aliceE164Identifier = "+14715355555"
    var aliceClient: SignalClient!

    let bobE164Identifier = "+18083235555"
    var bobClient: SignalClient!

    let localClient = LocalSignalClient()
    let runner = TestProtocolRunner()
    lazy var fakeService = FakeService(localClient: localClient, runner: runner)

    // MARK: - Hooks

    override func setUp() {
        super.setUp()

        // use the uiDatabase to be notified of DB writes so we can verify the expected
        // changes occur
        try! databaseStorage.grdbStorage.setupUIDatabase()

        // ensure local client has necessary "registered" state
        identityManager.generateNewIdentityKey()
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)

        bobClient = FakeSignalClient.generate(e164Identifier: bobE164Identifier)
        aliceClient = FakeSignalClient.generate(e164Identifier: aliceE164Identifier)

        // for unit tests, we must manually start the decryptJobQueue
        SSKEnvironment.shared.messageDecryptJobQueue.setup()
        SSKEnvironment.shared.batchMessageProcessor.shouldProcessDuringTests = true
    }

    override func tearDown() {
        SSKEnvironment.shared.batchMessageProcessor.shouldProcessDuringTests = false
        databaseStorage.grdbStorage.testing_tearDownUIDatabase()

        super.tearDown()
    }

    // MARK: - Tests

    func test_contactMessage_e164AndUuidEnvelope() {
        storageCoordinator.useGRDBForTests()

        // Re-initialize this state now that we've just switched databases.
        identityManager.generateNewIdentityKey()
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)

        write { transaction in
            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: self.localClient,
                                        transaction: transaction)
        }

        let expectMessageProcessed = expectation(description: "message processed")

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
        guard let observer = databaseStorage.grdbStorage.uiDatabaseObserver else {
            owsFailDebug("observer was unexpectedly nil")
            return
        }
        observer.appendDatabaseWriteDelegate(databaseDelegate)

        let envelopeBuilder = try! fakeService.envelopeBuilder(fromSenderClient: bobClient, bodyText: "Those who stands for nothing will fall for anything")
        envelopeBuilder.setSourceE164(bobClient.e164Identifier!)
        envelopeBuilder.setSourceUuid(bobClient.uuidIdentifier)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        messageReceiver.handleReceivedEnvelopeData(envelopeData, serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp())

        waitForExpectations(timeout: 1.0)
    }

    func test_contactMessage_UuidOnlyEnvelope() {

        write { transaction in
            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: self.localClient,
                                        transaction: transaction)
        }

        let expectMessageProcessed = expectation(description: "message processed")

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
        guard let observer = databaseStorage.grdbStorage.uiDatabaseObserver else {
            owsFailDebug("observer was unexpectedly nil")
            return
        }
        observer.appendDatabaseWriteDelegate(snapshotDelegate)

        let envelopeBuilder = try! fakeService.envelopeBuilder(fromSenderClient: bobClient, bodyText: "Those who stands for nothing will fall for anything")
        envelopeBuilder.setSourceUuid(bobClient.uuidIdentifier)
        let envelopeData = try! envelopeBuilder.buildSerializedData()
        messageReceiver.handleReceivedEnvelopeData(envelopeData, serverDeliveryTimestamp: NSDate.ows_millisecondTimeStamp())

        waitForExpectations(timeout: 1.0)
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
