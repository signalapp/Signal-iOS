//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class LinkValidatorTest: XCTestCase {
    func testCanParseURLs() {
        XCTAssertTrue(LinkValidator.canParseURLs(in: "https://signal.org/"))
        XCTAssertFalse(LinkValidator.canParseURLs(in: "\u{202e}https://signal.org/"))
    }
}
