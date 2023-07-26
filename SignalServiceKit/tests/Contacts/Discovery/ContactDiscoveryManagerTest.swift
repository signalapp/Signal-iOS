//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class ContactDiscoveryManagerTest: XCTestCase {
    private class MockContactDiscoveryTaskQueue: ContactDiscoveryTaskQueue {
        var onPerform: ((Set<String>, ContactDiscoveryMode) -> Promise<Set<SignalRecipient>>)?

        func perform(for phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Promise<Set<SignalRecipient>> {
            onPerform!(phoneNumbers, mode)
        }

        static func foundResponse(for phoneNumbers: Set<String>) -> Set<SignalRecipient> {
            Set(phoneNumbers.lazy.map { SignalRecipient(serviceId: FutureAci.randomForTesting(), phoneNumber: E164($0)!, deviceIds: [1])})
        }
    }

    private lazy var taskQueue = MockContactDiscoveryTaskQueue()
    private lazy var manager = ContactDiscoveryManagerImpl(contactDiscoveryTaskQueue: taskQueue)

    func testQueueing() throws {
        // Start the first stateful request, but don't resolve it yet.
        let (initialRequestPromise, initialRequestFuture) = Promise<Set<SignalRecipient>>.pending()
        let initialRequestStarted = expectation(description: "Waiting for initial request to start.")
        taskQueue.onPerform = { phoneNumbers, mode in
            initialRequestStarted.fulfill()
            return initialRequestPromise
        }
        _ = manager.lookUp(phoneNumbers: ["+16505550100"], mode: .contactIntersection)
        waitForExpectations(timeout: 10)

        // Schedule the next stateful request, which will be queued.
        var queuedRequestResult: Set<SignalRecipient>?
        let queuedRequestExpectation = expectation(description: "Waiting for queued request.")
        taskQueue.onPerform = { phoneNumbers, mode in
            return .value(MockContactDiscoveryTaskQueue.foundResponse(for: phoneNumbers))
        }
        manager.lookUp(phoneNumbers: ["+16505550101"], mode: .contactIntersection).done { signalRecipients in
            queuedRequestResult = signalRecipients
        }.ensure {
            queuedRequestExpectation.fulfill()
        }.cauterize()
        // Finish the initial request, which should unblock the queued request.
        initialRequestFuture.resolve([])
        waitForExpectations(timeout: 10)

        XCTAssertEqual(queuedRequestResult?.map { $0.phoneNumber! }, ["+16505550101"])
    }

    func testRateLimit() throws {
        let retryDate1 = Date(timeIntervalSinceNow: 30)
        let retryDate2 = Date(timeIntervalSinceNow: 60)

        // Step 1: Contact intersection fails with a rate limit error.
        taskQueue.onPerform = { phoneNumbers, mode in
            return Promise(error: ContactDiscoveryError(
                kind: .rateLimit, debugDescription: "", retryable: true, retryAfterDate: retryDate1
            ))
        }
        XCTAssertEqual(
            lookUpAndReturnRateLimitDate(phoneNumbers: ["+16505550100"], mode: .contactIntersection),
            retryDate1
        )

        // Step 2: One-off requests should still be possible, despite the earlier error.
        taskQueue.onPerform = { phoneNumbers, mode in
            return Promise(error: ContactDiscoveryError(
                kind: .rateLimit, debugDescription: "", retryable: true, retryAfterDate: retryDate2
            ))
        }
        XCTAssertEqual(
            lookUpAndReturnRateLimitDate(phoneNumbers: ["+16505550100"], mode: .oneOffUserRequest),
            retryDate2
        )

        // Step 3: Contact intersection should now be stuck behind the one-off retry date.
        taskQueue.onPerform = nil
        XCTAssertEqual(
            lookUpAndReturnRateLimitDate(phoneNumbers: ["+16505550100"], mode: .contactIntersection),
            retryDate2
        )
    }

    func testUndiscoverableCache() throws {
        let phoneNumber1 = "+16505550101"
        let phoneNumber2 = "+16505550102"
        let phoneNumber3 = "+16505550103"
        let phoneNumber4 = "+16505550104"

        // Populate the cache with empty phone numbers.
        taskQueue.onPerform = { phoneNumbers, mode in
            XCTAssertEqual(phoneNumbers, [phoneNumber1, phoneNumber2, phoneNumber3])
            return .value([])
        }
        XCTAssertEqual(
            lookUpAndReturnResult(phoneNumbers: [phoneNumber1, phoneNumber2, phoneNumber3], mode: .outgoingMessage),
            []
        )

        // Send a request for some of the same numbers -- these should be de-duped.
        taskQueue.onPerform = { phoneNumbers, mode in
            XCTAssertEqual(phoneNumbers, [])
            return .value([])
        }
        XCTAssertEqual(
            lookUpAndReturnResult(phoneNumbers: [phoneNumber1, phoneNumber2], mode: .outgoingMessage),
            []
        )

        // Send another request, but include an unknown number to force a request.
        taskQueue.onPerform = { phoneNumbers, mode in
            XCTAssertEqual(phoneNumbers, [phoneNumber1, phoneNumber4])
            return .value(MockContactDiscoveryTaskQueue.foundResponse(for: [phoneNumber4]))
        }
        XCTAssertEqual(
            lookUpAndReturnResult(phoneNumbers: [phoneNumber1, phoneNumber4], mode: .outgoingMessage),
            [phoneNumber4]
        )
    }

    private func lookUpAndReturnResult(phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Set<String>? {
        var result: Set<SignalRecipient>?
        let requestExpectation = expectation(description: "Waiting for request.")
        manager.lookUp(phoneNumbers: phoneNumbers, mode: mode).done { signalRecipients in
            result = signalRecipients
        }.ensure {
            requestExpectation.fulfill()
        }.cauterize()
        wait(for: [requestExpectation], timeout: 10)
        if let result {
            return Set(result.map { $0.phoneNumber! })
        }
        return nil
    }

    private func lookUpAndReturnRateLimitDate(phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Date? {
        var resultError: Error?
        let requestExpectation = expectation(description: "Waiting for request.")
        manager.lookUp(phoneNumbers: phoneNumbers, mode: mode).catch { error in
            resultError = error
        }.ensure {
            requestExpectation.fulfill()
        }.cauterize()
        wait(for: [requestExpectation], timeout: 10)
        if let error = resultError as? ContactDiscoveryError, error.kind == .rateLimit {
            return error.retryAfterDate
        }
        return nil
    }

    /// Ensures that all modes are included in `allCasesOrderedByRateLimitPriority.`
    ///
    /// This test is written weirdly so that the compiler will complain if you
    /// add a new mode without also updating this test. If you add a new mode &
    /// update this test but don't add it to the list sorted by priority, you'll
    /// get a test failure.
    func testModeRateLimitPriority() {
        let allCases = ContactDiscoveryMode.allCasesOrderedByRateLimitPriority
        let uniqueCases = Set(allCases)
        XCTAssertEqual(allCases.count, uniqueCases.count)  // no duplicates
        var caseCount = 0
        for mode in Set(ContactDiscoveryMode.allCasesOrderedByRateLimitPriority) {
            switch mode {
            case .oneOffUserRequest, .outgoingMessage, .contactIntersection:
                caseCount += 1
            }
        }
        XCTAssertEqual(caseCount, 3)  // every case appears
    }
}
