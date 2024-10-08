//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class OWSDisappearingMessagesConfigurationTest: XCTestCase {
    private var mockDB: InMemoryDB!
    private var store: MockDisappearingMessagesConfigurationStore!

    override func setUp() {
        super.setUp()

        mockDB = InMemoryDB()
        store = MockDisappearingMessagesConfigurationStore()
    }

    func testEquality() {
        mockDB.read { tx in
            let value1 = store.fetchOrBuildDefault(for: .universal, tx: tx)
            let value2 = value1.copyAsEnabled(withDurationSeconds: 10, timerVersion: 1)
            let value3 = value2.copy(withIsEnabled: false, timerVersion: 1)
            XCTAssertNotEqual(value1, value2)
            XCTAssertNotEqual(value2, value3)
            XCTAssertEqual(value1, value3)
        }
    }
}
