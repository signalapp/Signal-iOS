//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class PhoneNumberRegionsTest: XCTestCase {
    func testInitFromRemoteConfig() {
        let empties = ["", "   ", "a"]
        for value in empties {
            XCTAssertTrue(PhoneNumberRegions(fromRemoteConfig: value).isEmpty)
        }

        let justOne = ["1", " 1a ", "+1,", "1١", "6️⃣1"]
        for value in justOne {
            XCTAssertEqual(PhoneNumberRegions(fromRemoteConfig: value), ["1"], value)
        }

        XCTAssertEqual(
            PhoneNumberRegions(fromRemoteConfig: "1,2 345, +6 7,, ,89,٦,6️⃣"),
            ["1", "2345", "67", "89"]
        )
    }

    func testIsEmpty() {
        let empty: PhoneNumberRegions = []
        XCTAssertTrue(empty.isEmpty)

        let notEmpty: PhoneNumberRegions = ["1", "44"]
        XCTAssertFalse(notEmpty.isEmpty)
    }

    func testContains() {
        let regions: PhoneNumberRegions = ["1", "44"]
        XCTAssertTrue(regions.contains(e164: "+17345550123"))
        XCTAssertTrue(regions.contains(e164: "+447700900123"))
        XCTAssertFalse(regions.contains(e164: "+33639981234"))

        // This tests the caching behavior, which should not affect results.
        XCTAssertFalse(regions.contains(e164: "+33639981234"))
    }
}
