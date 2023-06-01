//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
import CocoaLumberjack

extension Thenable {
    func expect(timeout: TimeInterval, file: StaticString = #file, line: UInt = #line) -> Value {
        let expectation = XCTestExpectation(description: "\(file):\(line)")
        var result: Value?
        self.done {
            result = $0
            expectation.fulfill()
        }.catch {
            XCTFail("\($0)", file: file, line: line)
        }
        _ = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return try! XCTUnwrap(result, file: file, line: line)
    }
}

@objc
public class SSKBaseTestSwift: XCTestCase {
    @objc
    public override func setUp() {
        super.setUp()

        DDLog.add(DDTTYLogger.sharedInstance!)

        SetCurrentAppContext(TestAppContext(), true)

        MockSSKEnvironment.activate()
    }

    @objc
    public override func tearDown() {
        MockSSKEnvironment.flushAndWait()
        super.tearDown()
    }

    @objc
    public func read(_ block: (SDSAnyReadTransaction) -> Void) {
        return databaseStorage.read(block: block)
    }

    public func write<T>(_ block: (SDSAnyWriteTransaction) -> T) -> T {
        return databaseStorage.write(block: block)
    }

    public func write<T>(_ block: (SDSAnyWriteTransaction) throws -> T) throws -> T {
        try databaseStorage.write(block: block)
    }

    @objc
    public func asyncWrite(_ block: @escaping (SDSAnyWriteTransaction) -> Void) {
        return databaseStorage.asyncWrite(block: block)
    }
}

extension XCTestCase {
    @discardableResult
    public func expect<T>(
        _ promise: Promise<T>,
        description: String,
        timeout: TimeInterval
    ) -> Result<T, Error> {
        let expectation = self.expectation(description: description)
        var result: Result<T, Error>!
        promise.observe {
            result = $0
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        return result
    }

    @discardableResult
    public func expectSuccess<T>(
        _ promise: Promise<T>,
        description: String,
        timeout: TimeInterval
    ) -> T {
        let expectation = self.expectation(description: description)
        var result: T!
        promise.observe {
            switch $0 {
            case .success(let v):
                result = v
            case .failure(let e):
                XCTFail("Expected success, got error: \(e)")
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        return result
    }

    @discardableResult
    public func expectFailure<T>(
        _ promise: Promise<T>,
        description: String,
        timeout: TimeInterval
    ) -> Error {
        let expectation = self.expectation(description: description)
        var result: Error!
        promise.observe {
            switch $0 {
            case .success(let v):
                XCTFail("Expected failure, got success: \(v)")
            case .failure(let e):
                result = e
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        return result
    }
}
