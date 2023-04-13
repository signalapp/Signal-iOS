//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
import GRDB

class MessageSendingPerformanceTest: PerformanceBaseTest {

    // MARK: -

    let stubbableNetworkManager = StubbableNetworkManager()

    var dbObserverBlock: (() -> Void)?
    private var dbObserver: BlockObserver?

    let localE164Identifier = "+13235551234"
    let localUUID = UUID()

    let localClient = LocalSignalClient()
    let runner = TestProtocolRunner()

    // MARK: - Hooks

    override func setUp() {
        super.setUp()

        let sskEnvironment = SSKEnvironment.shared
        sskEnvironment.setNetworkManagerForUnitTests(self.stubbableNetworkManager)

        // use the *real* message sender to measure its perf
        sskEnvironment.setMessageSenderForUnitTests(MessageSender())
        Self.sskJobQueues.messageSenderJobQueue.setup()

        try! databaseStorage.grdbStorage.setup()

        // Observe DB changes so we can know when all the async processing is done
        let dbObserver = BlockObserver(block: { self.dbObserverBlock?() })
        self.dbObserver = dbObserver
        databaseStorage.appendDatabaseChangeDelegate(dbObserver)
    }

    override func tearDown() {
        dbObserver = nil
        super.tearDown()
    }

    // MARK: -

    func testPerf_messageSending_contactThread() {
        // This is an example of a performance test case.
        try! databaseStorage.grdbStorage.setupDatabaseChangeObserver()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            sendMessages_contactThread()
        }
        databaseStorage.grdbStorage.testing_tearDownDatabaseChangeObserver()
    }

    func testPerf_messageSending_groupThread() {
        // This is an example of a performance test case.
        try! databaseStorage.grdbStorage.setupDatabaseChangeObserver()
        measureMetrics(XCTestCase.defaultPerformanceMetrics, automaticallyStartMeasuring: false) {
            sendMessages_groupThread()
        }
        databaseStorage.grdbStorage.testing_tearDownDatabaseChangeObserver()
    }

    func sendMessages_groupThread() {
        // ensure local client has necessary "registered" state
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)

        // Session setup
        let groupMemberClients: [FakeSignalClient] = (0..<5).map { _ in
            return FakeSignalClient.generate(e164Identifier: CommonGenerator.e164())
        }

        for client in groupMemberClients {
            write { transaction in
                try! self.runner.initialize(senderClient: self.localClient,
                                            recipientClient: client,
                                            transaction: transaction)
            }
        }

        let threadFactory = GroupThreadFactory()
        threadFactory.memberAddressesBuilder = {
            groupMemberClients.map { $0.address }
        }

        let thread: TSGroupThread = databaseStorage.write { transaction in
            XCTAssertEqual(0, TSMessage.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))
            return threadFactory.create(transaction: transaction)
        }

        sendMessages(thread: thread)
    }

    func sendMessages_contactThread() {
        // ensure local client has necessary "registered" state
        identityManager.generateAndPersistNewIdentityKey(for: .aci)
        tsAccountManager.registerForTests(withLocalNumber: localE164Identifier, uuid: localUUID)

        // Session setup
        let bobClient = FakeSignalClient.generate(e164Identifier: "+18083235555")

        write { transaction in
            XCTAssertEqual(0, TSMessage.anyCount(transaction: transaction))
            XCTAssertEqual(0, TSThread.anyCount(transaction: transaction))

            try! self.runner.initialize(senderClient: self.localClient,
                                        recipientClient: bobClient,
                                        transaction: transaction)
        }

        let threadFactory = ContactThreadFactory()
        threadFactory.contactAddressBuilder = { bobClient.address }
        let thread = threadFactory.create()

        sendMessages(thread: thread)
    }

    func sendMessages(thread: TSThread) {
        let totalNumberToSend = DebugFlags.fastPerfTests ? 5 : 50
        let expectMessagesSent = expectation(description: "messages sent")
        let hasFulfilled = AtomicBool(false)
        let fulfillOnce = {
            if hasFulfilled.tryToSetFlag() {
                expectMessagesSent.fulfill()
            }
        }

        self.dbObserverBlock = {
            let (messageCount, attemptingOutCount): (UInt, Int) = self.databaseStorage.read { transaction in
                let messageCount = TSInteraction.anyCount(transaction: transaction)
                let attemptingOutCount = InteractionFinder.attemptingOutInteractionIds(transaction: transaction).count
                return (messageCount, attemptingOutCount)
            }

            if messageCount == totalNumberToSend && attemptingOutCount == 0 {
                fulfillOnce()
            }
        }

        startMeasuring()

        for _ in (0..<totalNumberToSend) {
            // Each is intentionally in a separate transaction, to be closer to the app experience
            // of sending each message
            self.read { transaction in
                let messageBody = MessageBody(text: CommonGenerator.paragraph,
                                              ranges: MessageBodyRanges.empty)
                ThreadUtil.enqueueMessage(body: messageBody,
                                          thread: thread,
                                          transaction: transaction)
            }
        }

        waitForExpectations(timeout: 20.0) { _ in
            self.stopMeasuring()

            self.dbObserverBlock = nil
            // There's some async stuff that happens in message sender that will explode if
            // we delete these models too early - e.g. sending a sync message, which we can't
            // easily wait for in an explicit way.
            sleep(1)
            self.write { transaction in
                TSInteraction.anyRemoveAllWithInstantation(transaction: transaction)
                TSThread.anyRemoveAllWithInstantation(transaction: transaction)
                SSKMessageSenderJobRecord.anyRemoveAllWithInstantation(transaction: transaction)
                OWSRecipientIdentity.anyRemoveAllWithInstantation(transaction: transaction)
            }
        }
    }
}

private class BlockObserver: DatabaseChangeDelegate {
    let block: () -> Void
    init(block: @escaping () -> Void) {
        self.block = block
    }

    func databaseChangesDidUpdate(databaseChanges: DatabaseChanges) {
        block()
    }

    func databaseChangesDidUpdateExternally() {
        block()
    }

    func databaseChangesDidReset() {
        block()
    }
}

class StubbableNetworkManager: NetworkManager {
    typealias NetworkManagerSuccess = (HTTPResponse) -> Void
    typealias NetworkManagerFailure = (Error) -> Void

    var block: (TSRequest, NetworkManagerSuccess, NetworkManagerFailure) -> Void = { request, success, _ in
        Logger.info("faking success for request: \(request)")
        let response = HTTPResponseImpl(requestUrl: request.url!,
                                        status: 200,
                                        headers: OWSHttpHeaders(),
                                        bodyData: nil)
        success(response)
    }

    public override func makePromise(request: TSRequest, canTryWebSocket: Bool = false) -> Promise<HTTPResponse> {
        Logger.info("Ignoring request: \(request)")

        // This latency is optimistic because I didn't want to slow
        // the tests down too much. But I did want to introduce some
        // non-trivial latency to make any interactions with the various
        // async's a little more realistic.
        let fakeNetworkLatency = DispatchTimeInterval.milliseconds(25)
        let block = self.block
        let (promise, future) = Promise<HTTPResponse>.pending()
        DispatchQueue.global().asyncAfter(deadline: .now() + fakeNetworkLatency) {
            let success = { response in
                future.resolve(response)
            }
            let failure = { error in
                future.reject(error)
            }
            block(request, success, failure)
        }
        return promise
    }
}
