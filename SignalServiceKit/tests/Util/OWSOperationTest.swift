//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import SignalCoreKit

@testable import SignalServiceKit

class OWSOperationTest: XCTestCase {

    private class TestOperation: OWSOperation {
        let expectation: XCTestExpectation

        init(expectation: XCTestExpectation) {
            self.expectation = expectation
        }

        override func run() {
            // no-op
        }

        override func didReportError(_ error: Error) {
            XCTAssertTrue((error as NSError).isRetryable)
            expectation.fulfill()
        }
    }

    func test_castSwiftErrorToNSErrorThenSet() {
        let expectedError = expectation(description: "didReportError")
        let operation = TestOperation(expectation: expectedError)

        let error = OWSRetryableError()
        operation.reportError(error)

        waitForExpectations(timeout: 0.1, handler: nil)
    }

    func test_NSError() {
        let expectedError = expectation(description: "didReportError")
        let operation = TestOperation(expectation: expectedError)

        let error = OWSRetryableError()
        operation.reportError(error)

        waitForExpectations(timeout: 0.1, handler: nil)
    }

    func test_operationError() {
        enum BarError: Error, IsRetryableProvider {
            case bar
            var isRetryableProvider: Bool {
                return true
            }
        }

        let expectedError = expectation(description: "didReportError")
        let operation = TestOperation(expectation: expectedError)

        operation.reportError(BarError.bar)

        waitForExpectations(timeout: 0.1, handler: nil)
    }

    // MARK: -

    func test_retryInterval() {
        var totalInterval: TimeInterval = 0
        for failureCount: UInt in 0..<110 {
            let retryInterval: TimeInterval = OWSOperation.retryIntervalForExponentialBackoff(failureCount: failureCount)
            totalInterval += retryInterval
            let formattedTotal = OWSFormat.formatDurationSeconds(Int(totalInterval))
            Logger.info("failureCount: \(failureCount), retryInterval: \(retryInterval), totalInterval: \(totalInterval) (\(formattedTotal))")
        }
        Logger.flush()
    }
}
