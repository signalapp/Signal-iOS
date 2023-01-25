//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class SpamReportingTokenTest: XCTestCase {
    func testInit() {
        XCTAssertNil(SpamReportingToken(data: .init()))
        XCTAssertNotNil(SpamReportingToken(data: .init([1, 2, 3])))
    }

    func testBase64EncodedString() {
        XCTAssertEqual(
            SpamReportingToken(data: .init([1, 2, 3, 4]))?.base64EncodedString(),
            "AQIDBA=="
        )
    }
}
