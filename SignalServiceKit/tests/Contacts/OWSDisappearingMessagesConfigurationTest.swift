//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class OWSDisappearingMessagesConfigurationTest: XCTestCase {
    private var mockDB: MockDB!
    private var store: MockDisappearingMessagesConfigurationStore!

    override func setUp() {
        super.setUp()

        mockDB = MockDB()
        store = MockDisappearingMessagesConfigurationStore()
    }

    func testEquality() {
        mockDB.read { tx in
            let value1 = store.fetchOrBuildDefault(for: .universal, tx: tx)
            let value2 = value1.copyAsEnabled(withDurationSeconds: 10)
            let value3 = value2.copy(withIsEnabled: false)
            XCTAssertNotEqual(value1, value2)
            XCTAssertNotEqual(value2, value3)
            XCTAssertEqual(value1, value3)
        }
    }
}
