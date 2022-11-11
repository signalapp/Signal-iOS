//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

class TSGroupThreadTest: XCTestCase {
    func testHasSafetyNumbers() throws {
        let groupThread = try TSGroupThread(dictionary: [:])
        XCTAssertFalse(groupThread.hasSafetyNumbers())
    }
}
