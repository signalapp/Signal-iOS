//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class MessageSenderJobQueueTest: SSKBaseTestSwift {
    private var fakeMessageSender: FakeMessageSender {
        MockSSKEnvironment.shared.messageSender as! FakeMessageSender
    }

    // MARK: 

    func test_messageIsSent() {
        let message: TSOutgoingMessage = OutgoingMessageFactory().create()

        let expectation = sentExpectation(message: message)

        let jobQueue = MessageSenderJobQueue()
        self.write { transaction in
            jobQueue.add(message: message.asPreparer, transaction: transaction)
        }
        jobQueue.setup()

        self.wait(for: [expectation], timeout: 1)
    }

    func test_waitsForSetup() {
        let message: TSOutgoingMessage = OutgoingMessageFactory().create()

        let sentBeforeReadyExpectation = sentExpectation(message: message)
        sentBeforeReadyExpectation.isInverted = true

        let jobQueue = MessageSenderJobQueue()

        self.write { transaction in
            jobQueue.add(message: message.asPreparer, transaction: transaction)
        }

        self.wait(for: [sentBeforeReadyExpectation], timeout: 1)

        let sentAfterReadyExpectation = sentExpectation(message: message)

        jobQueue.setup()

        self.wait(for: [sentAfterReadyExpectation], timeout: 1)
    }

    func test_respectsQueueOrder() {
        let messageCount = 3

        let messages = (1...messageCount).map { _ in OutgoingMessageFactory().create() }
        let expectations = (1...messageCount).map { self.expectation(description: "message\($0)") }

        let jobQueue = MessageSenderJobQueue()
        self.write { transaction in
            for message in messages {
                jobQueue.add(message: message.asPreparer, transaction: transaction)
            }
        }

        let sentMessages = AtomicArray<TSOutgoingMessage>()
        let remainingExpectations = AtomicArray(expectations)
        fakeMessageSender.sendMessageWasCalledBlock = { sentMessage in
            sentMessages.append(sentMessage)
            remainingExpectations.popHead()!.fulfill()
        }

        jobQueue.setup()

        self.wait(for: expectations, timeout: 1.0)

        XCTAssertEqual(sentMessages.get().map { $0.uniqueId }, messages.map { $0.uniqueId })
    }

    func test_sendingInvisibleMessage() {
        let jobQueue = MessageSenderJobQueue()
        jobQueue.setup()

        let message = OutgoingMessageFactory().buildDeliveryReceipt()
        let expectation = sentExpectation(message: message)
        self.write { transaction in
            jobQueue.add(message: message.asPreparer, transaction: transaction)
        }

        self.wait(for: [expectation], timeout: 1)
    }

    func test_retryableFailure() {
        let message: TSOutgoingMessage = OutgoingMessageFactory().create()

        let jobQueue = MessageSenderJobQueue()
        self.write { transaction in
            jobQueue.add(message: message.asPreparer, transaction: transaction)
        }

        let finder = AnyJobRecordFinder()
        var readyRecords: [SSKJobRecord] = []
        self.read { transaction in
            readyRecords = try! finder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction)
        }
        XCTAssertEqual(1, readyRecords.count)

        let jobRecord = readyRecords.first!
        XCTAssertEqual(0, jobRecord.failureCount)

        // simulate permanent failure (via `maxRetries` retryable failures)
        let error = OWSRetryableError()
        fakeMessageSender.stubbedFailingError = error
        let expectation = sentExpectation(message: message) {
            jobQueue.isSetup.set(false)
        }

        jobQueue.setup()
        self.wait(for: [expectation], timeout: 1)

        self.read { transaction in
            jobRecord.anyReload(transaction: transaction)
        }

        XCTAssertEqual(1, jobRecord.failureCount)
        XCTAssertEqual(.running, jobRecord.status)

        let retryCount: UInt = MessageSenderJobQueue.maxRetries
        (1..<retryCount).forEach { _ in
            let expectedResend = sentExpectation(message: message)
            // Manually kick queue restart.
            //
            // OWSOperation uses an NSTimer backed retry mechanism, but NSTimer's are not fired
            // during `self.wait(for:,timeout:` unless the timer was scheduled on the
            // `RunLoop.main`.
            //
            // We could move the timer to fire on the main RunLoop (and have the selector dispatch
            // back to a background queue), but the production code is simpler if we just manually
            // kick every retry in the test case.            
            XCTAssertNotNil(jobQueue.runAnyQueuedRetry())
            self.wait(for: [expectedResend], timeout: 1)
        }

        // Verify one retry left
        self.read { transaction in
            jobRecord.anyReload(transaction: transaction)
        }
        XCTAssertEqual(retryCount, jobRecord.failureCount)
        XCTAssertEqual(.running, jobRecord.status)

        // Verify final send fails permanently
        let expectedFinalResend = sentExpectation(message: message)
        XCTAssertNotNil(jobQueue.runAnyQueuedRetry())
        self.wait(for: [expectedFinalResend], timeout: 1)

        self.read { transaction in
            jobRecord.anyReload(transaction: transaction)
        }

        XCTAssertEqual(retryCount + 1, jobRecord.failureCount)
        XCTAssertEqual(.permanentlyFailed, jobRecord.status)

        // No remaining retries
        XCTAssertNil(jobQueue.runAnyQueuedRetry())
    }

    func test_permanentFailure() {
        let message: TSOutgoingMessage = OutgoingMessageFactory().create()

        let jobQueue = MessageSenderJobQueue()
        self.write { transaction in
            jobQueue.add(message: message.asPreparer, transaction: transaction)
        }

        let finder = AnyJobRecordFinder()
        var readyRecords: [SSKJobRecord] = []
        self.read { transaction in
            readyRecords = try! finder.allRecords(label: MessageSenderJobQueue.jobRecordLabel, status: .ready, transaction: transaction)
        }
        XCTAssertEqual(1, readyRecords.count)

        let jobRecord = readyRecords.first!
        XCTAssertEqual(0, jobRecord.failureCount)

        // simulate permanent failure
        let error = OWSUnretryableError()
        fakeMessageSender.stubbedFailingError = error
        let expectation = sentExpectation(message: message) {
            jobQueue.isSetup.set(false)
        }
        jobQueue.setup()
        self.wait(for: [expectation], timeout: 1)

        self.read { transaction in
            jobRecord.anyReload(transaction: transaction)
        }

        XCTAssertEqual(1, jobRecord.failureCount)
        XCTAssertEqual(.permanentlyFailed, jobRecord.status)
    }

    // MARK: Private

    private func sentExpectation(message: TSOutgoingMessage, block: @escaping () -> Void = { }) -> XCTestExpectation {
        let expectation = self.expectation(description: "sent message")

        fakeMessageSender.sendMessageWasCalledBlock = { [weak fakeMessageSender] sentMessage in
            guard let fakeMessageSender = fakeMessageSender else {
                owsFailDebug("Lost track of the message sender!")
                return
            }

            guard sentMessage.uniqueId == message.uniqueId else {
                XCTFail("unexpected sentMessage: \(sentMessage)")
                return
            }

            fakeMessageSender.sendMessageWasCalledBlock = nil

            expectation.fulfill()
            block()
        }

        return expectation
    }
}
