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

    func test_messageIsSent() async throws {
        let jobQueue = MessageSenderJobQueue()
        let (message, promise) = await databaseStorage.awaitableWrite { tx in
            let message = OutgoingMessageFactory().create(transaction: tx)
            let promise = jobQueue.add(.promise, message: message.asPreparer, transaction: tx)
            return (message, promise)
        }
        fakeMessageSender.stubbedFailingErrors = [nil]
        jobQueue.setup()
        try await promise.awaitable()
        XCTAssertEqual(fakeMessageSender.sentMessages.map { $0.uniqueId }, [message.uniqueId])
    }

    func test_respectsQueueOrder() async throws {
        let messageCount = 3
        let jobQueue = MessageSenderJobQueue()
        let (messages, promises) = await databaseStorage.awaitableWrite { tx in
            let messages = (1...messageCount).map { _ in OutgoingMessageFactory().create(transaction: tx) }
            let promises = messages.map { jobQueue.add(.promise, message: $0.asPreparer, transaction: tx) }
            return (messages, promises)
        }
        fakeMessageSender.stubbedFailingErrors = Array(repeating: nil, count: messageCount)
        jobQueue.setup()
        for promise in promises {
            try await promise.awaitable()
        }
        XCTAssertEqual(fakeMessageSender.sentMessages.map { $0.uniqueId }, messages.map { $0.uniqueId })
    }

    func test_sendingInvisibleMessage() async throws {
        let jobQueue = MessageSenderJobQueue()
        fakeMessageSender.stubbedFailingErrors = [nil]
        jobQueue.setup()
        let (message, promise) = await databaseStorage.awaitableWrite { tx in
            let message = OutgoingMessageFactory().buildDeliveryReceipt(transaction: tx)
            let promise = jobQueue.add(.promise, message: message.asPreparer, transaction: tx)
            return (message, promise)
        }
        try await promise.awaitable()
        XCTAssertEqual(fakeMessageSender.sentMessages.map { $0.uniqueId }, [message.uniqueId])
    }

    func test_retryableFailure() async throws {
        let jobQueue = MessageSenderJobQueue()

        let (message, promise) = await databaseStorage.awaitableWrite { tx in
            let message = OutgoingMessageFactory().create(transaction: tx)
            let promise = jobQueue.add(.promise, message: message.asPreparer, transaction: tx)
            return (message, promise)
        }

        let finder = JobRecordFinderImpl<MessageSenderJobRecord>()
        var readyRecords: [MessageSenderJobRecord] = []
        self.read { tx in
            readyRecords = try! finder.allRecords(
                status: .ready,
                transaction: tx.asV2Read
            )
        }
        XCTAssertEqual(1, readyRecords.count)

        var jobRecord = readyRecords.first!
        XCTAssertEqual(0, jobRecord.failureCount)

        // simulate permanent failure (via `maxRetries` retryable failures)
        let retryCount: Int = 110 // Matches MessageSenderOperation
        fakeMessageSender.stubbedFailingErrors = Array(repeating: OWSRetryableError(), count: retryCount + 1)
        jobQueue.setup()

        do {
            let retryTriggerTask = Task.detached {
                while true {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 500*NSEC_PER_USEC)
                    _ = jobQueue.runAnyQueuedRetry()
                }
            }
            defer {
                retryTriggerTask.cancel()
            }
            try await promise.awaitable()
            XCTFail("Must throw an error.")
        } catch {}

        self.read { transaction in
            jobRecord = jobRecord.fetchLatest(transaction: transaction)
        }

        XCTAssertEqual(retryCount + 1, Int(jobRecord.failureCount))
        XCTAssertEqual(.permanentlyFailed, jobRecord.status)
        XCTAssertEqual(
            fakeMessageSender.sentMessages.map { $0.uniqueId },
            Array(repeating: message.uniqueId, count: retryCount + 1)
        )

        // No remaining retries
        XCTAssertNil(jobQueue.runAnyQueuedRetry())
    }

    func test_permanentFailure() async {
        let jobQueue = MessageSenderJobQueue()

        let (message, promise) = await databaseStorage.awaitableWrite { tx in
            let message = OutgoingMessageFactory().create(transaction: tx)
            let promise = jobQueue.add(.promise, message: message.asPreparer, transaction: tx)
            return (message, promise)
        }

        let finder = JobRecordFinderImpl<MessageSenderJobRecord>()
        var readyRecords: [MessageSenderJobRecord] = []
        self.read { tx in
            readyRecords = try! finder.allRecords(
                status: .ready,
                transaction: tx.asV2Read
            )
        }
        XCTAssertEqual(1, readyRecords.count)

        var jobRecord = readyRecords.first!
        XCTAssertEqual(0, jobRecord.failureCount)

        // simulate permanent failure
        let error = OWSUnretryableError()
        fakeMessageSender.stubbedFailingErrors = [error]
        jobQueue.setup()

        do {
            try await promise.awaitable()
            XCTFail("Must throw an error.")
        } catch {}

        self.read { tx in
            jobRecord = jobRecord.fetchLatest(transaction: tx)
        }

        XCTAssertEqual(1, jobRecord.failureCount)
        XCTAssertEqual(.permanentlyFailed, jobRecord.status)
        XCTAssertEqual(fakeMessageSender.sentMessages.map { $0.uniqueId }, [message.uniqueId])
    }
}

private extension MessageSenderJobRecord {
    func fetchLatest(transaction: SDSAnyReadTransaction) -> Self {
        guard let latest = Self.anyFetch(uniqueId: uniqueId, transaction: transaction) else {
            owsFail("Failed to fetch latest model! Was the model removed?")
        }

        return latest
    }
}
