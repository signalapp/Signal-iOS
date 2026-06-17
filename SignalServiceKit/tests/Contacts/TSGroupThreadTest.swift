//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class TSGroupThreadTest: XCTestCase {
    func testHasSafetyNumbers() throws {
        let groupThread = TSGroupThread.forUnitTest(groupId: Randomness.generateRandomBytes(32))
        XCTAssertFalse(groupThread.hasSafetyNumbers())
    }
}
