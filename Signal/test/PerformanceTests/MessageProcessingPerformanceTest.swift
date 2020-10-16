//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit
import GRDB

class MessageProcessingPerformanceTest: PerformanceBaseTest {

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

    var dbObserverBlock: (() -> Void)?

    private var dbObserver: BlockObserver?

    // MARK: - Hooks

    override func setUp() {
        super.setUp()

        storageCoordinator.useGRDBForTests()
        try! databaseStorage.grdbStorage.setupUIDatabase()

        // for unit tests, we must manually start the decryptJobQueue
        SSKEnvironment.shared.messageDecryptJobQueue.setup()

        let dbObserver = BlockObserver(block: { [weak self] in self?.dbObserverBlock?() })
        self.dbObserver = dbObserver
        databaseStorage.appendUIDatabaseSnapshotDelegate(dbObserver)
    }

    override func tearDown() {
        super.tearDown()
        self.dbObserver = nil
    }

    // MARK: - Tests

    func testGRDBPerf_messageProcessing() {
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            processIncomingMessages()
        }
        databaseStorage.grdbStorage.testing_tearDownUIDatabase()
    }

    func processIncomingMessages() {
        // ensure local client has necessary "registered" state
        identityManager.generateNewIdentityKey()
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)

        // use the uiDatabase to be notified of DB writes so we can verify the expected
        // changes occur
        bobClient = FakeSignalClient.generate(e164Identifier: bobE164Identifier)
        aliceClient = FakeSignalClient.generate(e164Identifier: aliceE164Identifier)

        write { transaction in
            XCTAssertEqual(0, TSMessage.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))

            try! self.runner.initialize(senderClient: self.bobClient,
                                        recipientClient: self.localClient,
                                        transaction: transaction)
        }

        let buildEnvelopeData = { () -> Data in
            let envelopeBuilder = try! self.fakeService.envelopeBuilder(fromSenderClient: self.bobClient)
            envelopeBuilder.setSourceE164(self.bobClient.e164Identifier!)
            return try! envelopeBuilder.buildSerializedData()
        }

        let envelopeCount: Int = DebugFlags.fastPerfTests ? 5 : 500
        let envelopeDatas: [Data] = (0..<envelopeCount).map { _ in buildEnvelopeData() }

        let expectMessagesProcessed = expectation(description: "messages processed")
        let hasFulfilled = AtomicBool(false)
        let fulfillOnce = {
            if hasFulfilled.tryToSetFlag() {
                expectMessagesProcessed.fulfill()
            }
        }

        self.dbObserverBlock = {
            let messageCount = self.databaseStorage.read { transaction in
                return TSInteraction.anyCount(transaction: transaction)
            }
            if messageCount == envelopeDatas.count {
                fulfillOnce()
            }
        }

        startMeasuring()
        for envelopeData in envelopeDatas {
            messageReceiver.handleReceivedEnvelopeData(envelopeData, serverDeliveryTimestamp: 0)
        }

        waitForExpectations(timeout: 15.0) { _ in
            self.stopMeasuring()

            self.dbObserverBlock = nil
            self.write { transaction in
                TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
                TSThread.anyRemoveAllWithInstantation(transaction: transaction)
                SSKMessageDecryptJobRecord.anyRemoveAllWithInstantation(transaction: transaction)
                OWSMessageContentJob.anyRemoveAllWithInstantation(transaction: transaction)
                OWSRecipientIdentity.anyRemoveAllWithInstantation(transaction: transaction)
            }
        }
    }
}

private class BlockObserver: UIDatabaseSnapshotDelegate {
    let block: () -> Void
    init(block: @escaping () -> Void) {
        self.block = block
    }

    func uiDatabaseSnapshotWillUpdate() {
        AssertIsOnMainThread()
    }

    func uiDatabaseSnapshotDidUpdate(databaseChanges: UIDatabaseChanges) {
        block()
    }

    func uiDatabaseSnapshotDidUpdateExternally() {
        block()
    }

    func uiDatabaseSnapshotDidReset() {
        block()
    }
}
