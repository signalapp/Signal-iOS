//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
import SignalServiceKit

public class PerformanceBaseTest: XCTestCase {

    // MARK: Hooks

    public override func setUp() {
        super.setUp()

        SetCurrentAppContext(TestAppContext(), true)
        SDSDatabaseStorage.shouldLogDBQueries = false

        MockSSKEnvironment.activate()
    }

    public override func tearDown() {
        SDSDatabaseStorage.shouldLogDBQueries = DebugFlags.logSQLQueries
        super.tearDown()
    }

    // MARK: Helpers

    public func read(_ block: @escaping (SDSAnyReadTransaction) -> Void) {
        return databaseStorage.read(block: block)
    }

    public func write(_ block: @escaping (SDSAnyWriteTransaction) -> Void) {
        return databaseStorage.write(block: block)
    }

    public func asyncWrite(_ block: @escaping (SDSAnyWriteTransaction) -> Void) {
        return databaseStorage.asyncWrite(block: block)
    }
}
