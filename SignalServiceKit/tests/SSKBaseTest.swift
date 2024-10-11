//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import XCTest
@testable public import SignalServiceKit
import CocoaLumberjack

public class SSKBaseTest: XCTestCase {
    public override func setUp() {
        DDLog.add(DDTTYLogger.sharedInstance!)
        MockSSKEnvironment.activate()
    }

    public override func tearDown() {
        MockSSKEnvironment.flushAndWait()
        super.tearDown()
    }

    public func read(_ block: (SDSAnyReadTransaction) -> Void) {
        return SSKEnvironment.shared.databaseStorageRef.read(block: block)
    }

    public func write<T>(_ block: (SDSAnyWriteTransaction) -> T) -> T {
        return SSKEnvironment.shared.databaseStorageRef.write(block: block)
    }

    public func write<T>(_ block: (SDSAnyWriteTransaction) throws -> T) rethrows -> T {
        try SSKEnvironment.shared.databaseStorageRef.write(block: block)
    }

    public func asyncWrite(_ block: @escaping (SDSAnyWriteTransaction) -> Void) {
        return SSKEnvironment.shared.databaseStorageRef.asyncWrite(block: block)
    }
}
