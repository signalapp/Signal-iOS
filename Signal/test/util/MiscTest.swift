//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import XCTest

class MiscTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func test_uintRotation() {
        XCTAssertEqual(UInt(0b10), UInt(0b1).rotateLeft(1))
        XCTAssertEqual(UInt(0b101000), UInt(0b101).rotateLeft(3))

        // Max bit should wrap around.
        XCTAssertTrue(UInt.highestBit > 0)
        XCTAssertEqual(UInt(0b1), UInt.highestBit.rotateLeft(1))
        XCTAssertEqual(UInt(0b11), (UInt.highestBit | UInt(0b1)).rotateLeft(1))
    }
}
