//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit
import CocoaLumberjack

@objc
public class SSKBaseTestSwift: XCTestCase {

    // MARK: - Dependencies

    var primaryStorage: OWSPrimaryStorage? {
        return SSKEnvironment.shared.primaryStorage
    }

    // MARK: -

    @objc
    public override func setUp() {
        super.setUp()

        DDLog.add(DDTTYLogger.sharedInstance)

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

    @objc
    public func yapRead(_ block: @escaping (YapDatabaseReadTransaction) -> Void) {
        guard let primaryStorage = primaryStorage else {
            XCTFail("Missing primaryStorage.")
            return
        }
        return primaryStorage.dbReadConnection.read(block)
    }

    @objc
    public func yapWrite(_ block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        guard let primaryStorage = primaryStorage else {
            XCTFail("Missing primaryStorage.")
            return
        }
        return primaryStorage.dbReadWriteConnection.readWrite(block)
    }

    @objc
    public func yapAsyncWrite(_ block: @escaping (YapDatabaseReadWriteTransaction) -> Void) {
        guard let primaryStorage = primaryStorage else {
            XCTFail("Missing primaryStorage.")
            return
        }
        return primaryStorage.dbReadWriteConnection.asyncReadWrite(block)
    }
}
