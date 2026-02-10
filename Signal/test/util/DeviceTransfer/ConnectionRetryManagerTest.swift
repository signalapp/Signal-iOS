//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

class ConnectionRetryManagerTest: XCTestCase {

    // MARK: - Configuration Tests

    func testDefaultConfiguration() {
        let manager = ConnectionRetryManager()

        XCTAssertEqual(manager.configuration.maxRetries, 3)
        XCTAssertEqual(manager.configuration.baseDelaySeconds, 2.0)
    }

    func testCustomConfiguration() {
        let config = ConnectionRetryManager.Configuration(
            maxRetries: 5,
            baseDelaySeconds: 1.0
        )
        let manager = ConnectionRetryManager(configuration: config)

        XCTAssertEqual(manager.configuration.maxRetries, 5)
        XCTAssertEqual(manager.configuration.baseDelaySeconds, 1.0)
    }

    // MARK: - Initial State Tests

    func testInitialRetryCountIsZero() {
        let manager = ConnectionRetryManager()
        XCTAssertEqual(manager.retryCount, 0)
    }

    func testInitiallyCanRetry() {
        let manager = ConnectionRetryManager()
        XCTAssertTrue(manager.canRetry)
    }

    func testInitialRemainingRetries() {
        let manager = ConnectionRetryManager()
        XCTAssertEqual(manager.remainingRetries, 3)
    }

    // MARK: - Exponential Backoff Tests

    func testDelayForFirstRetry() {
        let manager = ConnectionRetryManager()
        let delay = manager.delayForRetry(attempt: 1)
        XCTAssertEqual(delay, 2.0)  // base delay
    }

    func testDelayForSecondRetry() {
        let manager = ConnectionRetryManager()
        let delay = manager.delayForRetry(attempt: 2)
        XCTAssertEqual(delay, 4.0)  // 2 * 2^1
    }

    func testDelayForThirdRetry() {
        let manager = ConnectionRetryManager()
        let delay = manager.delayForRetry(attempt: 3)
        XCTAssertEqual(delay, 8.0)  // 2 * 2^2
    }

    func testExponentialBackoffWithCustomBase() {
        let config = ConnectionRetryManager.Configuration(
            maxRetries: 5,
            baseDelaySeconds: 1.0
        )
        let manager = ConnectionRetryManager(configuration: config)

        XCTAssertEqual(manager.delayForRetry(attempt: 1), 1.0)
        XCTAssertEqual(manager.delayForRetry(attempt: 2), 2.0)
        XCTAssertEqual(manager.delayForRetry(attempt: 3), 4.0)
        XCTAssertEqual(manager.delayForRetry(attempt: 4), 8.0)
        XCTAssertEqual(manager.delayForRetry(attempt: 5), 16.0)
    }

    // MARK: - Retry Attempt Tests

    func testAttemptRetryIncrementsCount() {
        let manager = ConnectionRetryManager()

        XCTAssertEqual(manager.retryCount, 0)

        manager.executeRetryImmediately()
        XCTAssertEqual(manager.retryCount, 1)

        manager.executeRetryImmediately()
        XCTAssertEqual(manager.retryCount, 2)
    }

    func testAttemptRetryReturnsTrueWhenRetriesAvailable() {
        let manager = ConnectionRetryManager()
        let result = manager.attemptRetry()
        XCTAssertTrue(result)
    }

    func testAttemptRetryReturnsFalseWhenRetriesExhausted() {
        let manager = ConnectionRetryManager()

        // Exhaust all retries
        manager.executeRetryImmediately()
        manager.executeRetryImmediately()
        manager.executeRetryImmediately()

        XCTAssertFalse(manager.canRetry)
        XCTAssertFalse(manager.attemptRetry())
    }

    func testCanRetryUpdatesProperly() {
        let manager = ConnectionRetryManager()

        XCTAssertTrue(manager.canRetry)
        manager.executeRetryImmediately()

        XCTAssertTrue(manager.canRetry)
        manager.executeRetryImmediately()

        XCTAssertTrue(manager.canRetry)
        manager.executeRetryImmediately()

        XCTAssertFalse(manager.canRetry)
    }

    func testRemainingRetriesDecrements() {
        let manager = ConnectionRetryManager()

        XCTAssertEqual(manager.remainingRetries, 3)
        manager.executeRetryImmediately()

        XCTAssertEqual(manager.remainingRetries, 2)
        manager.executeRetryImmediately()

        XCTAssertEqual(manager.remainingRetries, 1)
        manager.executeRetryImmediately()

        XCTAssertEqual(manager.remainingRetries, 0)
    }

    // MARK: - Reset Tests

    func testResetClearsRetryCount() {
        let manager = ConnectionRetryManager()

        manager.executeRetryImmediately()
        manager.executeRetryImmediately()

        XCTAssertEqual(manager.retryCount, 2)

        manager.reset()

        XCTAssertEqual(manager.retryCount, 0)
        XCTAssertTrue(manager.canRetry)
        XCTAssertEqual(manager.remainingRetries, 3)
    }

    func testRecordSuccessfulConnectionResetsCount() {
        let manager = ConnectionRetryManager()

        manager.executeRetryImmediately()
        manager.executeRetryImmediately()

        XCTAssertEqual(manager.retryCount, 2)

        manager.recordSuccessfulConnection()

        XCTAssertEqual(manager.retryCount, 0)
        XCTAssertTrue(manager.canRetry)
    }

    // MARK: - Callback Tests

    func testOnRetryCallbackIsInvoked() {
        let manager = ConnectionRetryManager()

        var callbackInvoked = false
        var receivedRetryNumber: Int?

        manager.onRetry = { retryNumber in
            callbackInvoked = true
            receivedRetryNumber = retryNumber
        }

        manager.executeRetryImmediately()

        XCTAssertTrue(callbackInvoked)
        XCTAssertEqual(receivedRetryNumber, 1)
    }

    func testOnRetryCallbackReceivesCorrectRetryNumber() {
        let manager = ConnectionRetryManager()

        var retryNumbers: [Int] = []

        manager.onRetry = { retryNumber in
            retryNumbers.append(retryNumber)
        }

        manager.executeRetryImmediately()
        manager.executeRetryImmediately()
        manager.executeRetryImmediately()

        XCTAssertEqual(retryNumbers, [1, 2, 3])
    }

    func testOnRetriesExhaustedCallbackIsInvoked() {
        let manager = ConnectionRetryManager()

        var exhaustedCallbackInvoked = false

        manager.onRetriesExhausted = {
            exhaustedCallbackInvoked = true
        }

        // Exhaust all retries
        manager.executeRetryImmediately()
        manager.executeRetryImmediately()
        manager.executeRetryImmediately()

        XCTAssertFalse(exhaustedCallbackInvoked)

        // Try one more time when exhausted
        manager.executeRetryImmediately()

        XCTAssertTrue(exhaustedCallbackInvoked)
    }

    // MARK: - Next Retry Delay Tests

    func testNextRetryDelayReturnsCorrectValue() {
        let manager = ConnectionRetryManager()

        XCTAssertEqual(manager.nextRetryDelay, 2.0)

        manager.executeRetryImmediately()
        XCTAssertEqual(manager.nextRetryDelay, 4.0)

        manager.executeRetryImmediately()
        XCTAssertEqual(manager.nextRetryDelay, 8.0)

        manager.executeRetryImmediately()
        XCTAssertNil(manager.nextRetryDelay)  // No more retries available
    }

    // MARK: - Edge Cases

    func testZeroMaxRetries() {
        let config = ConnectionRetryManager.Configuration(
            maxRetries: 0,
            baseDelaySeconds: 2.0
        )
        let manager = ConnectionRetryManager(configuration: config)

        XCTAssertFalse(manager.canRetry)
        XCTAssertEqual(manager.remainingRetries, 0)
        XCTAssertFalse(manager.attemptRetry())
    }

    func testSingleRetry() {
        let config = ConnectionRetryManager.Configuration(
            maxRetries: 1,
            baseDelaySeconds: 2.0
        )
        let manager = ConnectionRetryManager(configuration: config)

        XCTAssertTrue(manager.canRetry)
        XCTAssertEqual(manager.remainingRetries, 1)

        manager.executeRetryImmediately()

        XCTAssertFalse(manager.canRetry)
        XCTAssertEqual(manager.remainingRetries, 0)
    }

    func testResetAfterExhaustion() {
        let manager = ConnectionRetryManager()

        // Exhaust all retries
        manager.executeRetryImmediately()
        manager.executeRetryImmediately()
        manager.executeRetryImmediately()

        XCTAssertFalse(manager.canRetry)

        // Reset
        manager.reset()

        XCTAssertTrue(manager.canRetry)
        XCTAssertEqual(manager.retryCount, 0)
        XCTAssertEqual(manager.remainingRetries, 3)
    }
}
