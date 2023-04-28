//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

class MiscTest: XCTestCase {
    func test_uintRotation() {
        XCTAssertEqual(UInt(0b10), UInt(0b1).rotateLeft(1))
        XCTAssertEqual(UInt(0b101000), UInt(0b101).rotateLeft(3))

        // Max bit should wrap around.
        XCTAssertTrue(UInt.highestBit > 0)
        XCTAssertEqual(UInt(0b1), UInt.highestBit.rotateLeft(1))
        XCTAssertEqual(UInt(0b11), (UInt.highestBit | UInt(0b1)).rotateLeft(1))
    }
}
