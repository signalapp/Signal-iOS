//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

@objc
public class SSKBaseTestSwift: XCTestCase {

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

        SSKEnvironment.shared.primaryStorage.closeForTests()

        ClearCurrentAppContextForTests()
        SSKEnvironment.clearSharedForTests()
    }

    @objc
    public func read(_ block: @escaping (YapDatabaseReadTransaction) -> Swift.Void) {
        return OWSPrimaryStorage.shared().dbReadConnection.read(block)
    }

    @objc
    public func readWrite(_ block: @escaping (YapDatabaseReadWriteTransaction) -> Swift.Void) {
        return OWSPrimaryStorage.shared().dbReadWriteConnection.readWrite(block)
    }
}
