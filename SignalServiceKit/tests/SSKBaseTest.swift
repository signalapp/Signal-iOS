//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import XCTest
@testable public import SignalServiceKit
import CocoaLumberjack

public class SSKBaseTest: XCTestCase {
    private var oldContext: (any AppContext)!

    @MainActor
    override public func setUp() {
        DDLog.add(DDTTYLogger.sharedInstance!)
        let setupExpectation = expectation(description: "mock ssk environment setup completed")
        self.oldContext = CurrentAppContext()
        Task {
            await MockSSKEnvironment.activate()
            setupExpectation.fulfill()
        }
        waitForExpectations(timeout: 30)
    }

    @MainActor
    override public func tearDown() {
        MockSSKEnvironment.deactivate(oldContext: self.oldContext)
        super.tearDown()
    }

    public func read(_ block: (DBReadTransaction) -> Void) {
        return SSKEnvironment.shared.databaseStorageRef.read(block: block)
    }

    public func write<T>(_ block: (DBWriteTransaction) -> T) -> T {
        return SSKEnvironment.shared.databaseStorageRef.write(block: block)
    }

    public func write<T>(_ block: (DBWriteTransaction) throws -> T) rethrows -> T {
        try SSKEnvironment.shared.databaseStorageRef.write(block: block)
    }

    public func asyncWrite(_ block: @escaping (DBWriteTransaction) -> Void) {
        return SSKEnvironment.shared.databaseStorageRef.asyncWrite(block: block)
    }
}
