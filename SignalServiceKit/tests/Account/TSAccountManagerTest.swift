//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class TSAccountManagerTest: XCTestCase {
    func testGenerateRegistrationId() {
        var results = Set<UInt32>()
        for _ in 1...100 {
            let result = TSAccountManager.generateRegistrationId()
            XCTAssertGreaterThanOrEqual(result, 1)
            XCTAssertLessThanOrEqual(result, 0x3fff)
            results.insert(result)
        }
        XCTAssertGreaterThan(results.count, 25)
    }
}
