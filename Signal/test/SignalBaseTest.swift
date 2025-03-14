//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import XCTest

@testable import SignalServiceKit

open class SignalBaseTest: XCTestCase {

    @MainActor
    public override func setUp() {
        super.setUp()
        let setupExpectation = expectation(description: "mock ssk environment setup completed")
        Task {
            await MockSSKEnvironment.activate()
            setupExpectation.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    open override func tearDown() {
        MockSSKEnvironment.flushAndWait()
        super.tearDown()
    }

    func read<T>(block: (DBReadTransaction) throws -> T) rethrows -> T {
        return try SSKEnvironment.shared.databaseStorageRef.read(block: block)
    }

    func write<T>(block: (DBWriteTransaction) throws -> T) rethrows -> T {
        return try SSKEnvironment.shared.databaseStorageRef.write(block: block)
    }
}
