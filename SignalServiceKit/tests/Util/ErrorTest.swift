//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class ErrorTest: XCTestCase {

    func testShortDescription() {
        let error = CocoaError(.fileReadNoSuchFile, userInfo: [ NSUnderlyingErrorKey: POSIXError(.ENOENT) ])
        XCTAssertEqual(error.shortDescription, "NSCocoaErrorDomain/260, NSPOSIXErrorDomain/2")
    }

}
