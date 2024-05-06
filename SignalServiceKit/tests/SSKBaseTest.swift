//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit
import CocoaLumberjack

public class SSKBaseTest: XCTestCase {
    public override func setUp() {
        DDLog.add(DDTTYLogger.sharedInstance!)
        SetCurrentAppContext(TestAppContext())
        MockSSKEnvironment.activate()
    }

    public override func tearDown() {
        MockSSKEnvironment.flushAndWait()
        super.tearDown()
    }

    public func read(_ block: (SDSAnyReadTransaction) -> Void) {
        return databaseStorage.read(block: block)
    }

    public func write<T>(_ block: (SDSAnyWriteTransaction) -> T) -> T {
        return databaseStorage.write(block: block)
    }

    public func write<T>(_ block: (SDSAnyWriteTransaction) throws -> T) rethrows -> T {
        try databaseStorage.write(block: block)
    }

    public func asyncWrite(_ block: @escaping (SDSAnyWriteTransaction) -> Void) {
        return databaseStorage.asyncWrite(block: block)
    }
}
