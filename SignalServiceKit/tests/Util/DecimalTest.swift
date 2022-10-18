//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

final class DecimalTest: XCTestCase {
    func testIsInteger() throws {
        let ints: [Decimal] = [-12, -1, -1.0, -0, 0, 0.0, 1, 1.0, 12]
        for value in ints {
            XCTAssertTrue(value.isInteger, "\(value) should be an integer")
        }

        let nan: Decimal = 1 / 0
        let notInts: [Decimal] = [1.2, 0.1, nan]
        for value in notInts {
            XCTAssertFalse(value.isInteger, "\(value) shouldn't be an integer")
        }
    }

    func testRounded() throws {
        let testCases: [(Decimal, Decimal)] = [
            (-123, -123),
            (-123.4, -123),
            (-123.5, -124),
            (-123.6, -124),
            (-0.4, 0),
            (-0.5, -1),
            (-0.6, -1),
            (0.4, 0),
            (0.5, 1),
            (0.6, 1),
            (123, 123),
            (123.4, 123),
            (123.5, 124),
            (123.6, 124)
        ]
        for (input, expected) in testCases {
            let actual = input.rounded()
            XCTAssertEqual(actual, expected, "\(input) should equal \(expected) when rounding")
        }
    }
}
