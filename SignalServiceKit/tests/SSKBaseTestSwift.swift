//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit
import CocoaLumberjack

@objc
public class SSKBaseTestSwift: XCTestCase {

    @objc
    public override func setUp() {
        super.setUp()

        DDLog.add(DDTTYLogger.sharedInstance)

        ClearCurrentAppContextForTests()
        SetCurrentAppContext(TestAppContext())

        MockSSKEnvironment.activate()
        SDSDatabaseStorage.shared.clearGRDBStorage()
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
    public func yapRead(_ block: @escaping (YapDatabaseReadTransaction) -> Void) {
        return OWSPrimaryStorage.shared().dbReadConnection.read(block)
    }

    @objc
    public func yapWrite(_ block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        return OWSPrimaryStorage.shared().dbReadWriteConnection.readWrite(block)
    }
}
