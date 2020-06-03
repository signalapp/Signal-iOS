//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class OWSOperationTest: SSKBaseTestSwift {

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
        enum FooError: Error {
            case foo
        }

        let expectedError = expectation(description: "didReportError")
        let operation = TestOperation(expectation: expectedError)

        let error = FooError.foo
        let nsError = error as NSError
        nsError.isRetryable = true

        operation.reportError(nsError)

        waitForExpectations(timeout: 0.1, handler: nil)
    }

    func test_NSError() {
        let expectedError = expectation(description: "didReportError")
        let operation = TestOperation(expectation: expectedError)

        let nsError = NSError(domain: "Foo", code: 3, userInfo: nil)
        nsError.isRetryable = true

        operation.reportError(nsError)
        waitForExpectations(timeout: 0.1, handler: nil)
    }

    func test_operationError() {
        enum BarError: OperationError {
            case bar
            var isRetryable: Bool {
                return true
            }
        }

        let expectedError = expectation(description: "didReportError")
        let operation = TestOperation(expectation: expectedError)

        operation.reportError(BarError.bar)

        waitForExpectations(timeout: 0.1, handler: nil)
    }
}
