//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class NSObjectTest: XCTestCase {
    func testObjectComparison() {
        let yes: NSNumber = true
        let no: NSNumber = false
        XCTAssertTrue(NSObject.isNullableObject(nil, equalTo: nil))
        XCTAssertFalse(NSObject.isNullableObject(yes, equalTo: nil))
        XCTAssertFalse(NSObject.isNullableObject(nil, equalTo: yes))
        XCTAssertFalse(NSObject.isNullableObject(yes, equalTo: no))
        XCTAssertTrue(NSObject.isNullableObject(yes, equalTo: yes))
    }
}
