//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest
import SignalServiceKit

@objc
public class PerformanceBaseTest: XCTestCase {

    // MARK: -

    @objc
    public override func setUp() {
        super.setUp()

        ClearCurrentAppContextForTests()
        SetCurrentAppContext(TestAppContext())

        MockSSKEnvironment.activate()
    }

    @objc
    public override func tearDown() {
        super.tearDown()
    }

    @objc
    public var databaseStorage: SDSDatabaseStorage {
        return SDSDatabaseStorage.shared
    }

    @objc
    public func read(_ block: @escaping (SDSAnyReadTransaction) -> Void) {
        return databaseStorage.read(block: block)
    }

    @objc
    public func write(_ block: @escaping (SDSAnyWriteTransaction) -> Void) {
        return databaseStorage.write(block: block)
    }

    @objc
    public func asyncWrite(_ block: @escaping (SDSAnyWriteTransaction) -> Void) {
        return databaseStorage.asyncWrite(block: block)
    }
}
