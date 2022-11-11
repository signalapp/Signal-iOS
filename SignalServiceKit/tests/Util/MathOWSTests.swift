//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

class MathOWSTests: XCTestCase {
    func testCGFloatRandom() throws {
        let expectedTwoChoicesValues = Set([CGFloat(0), CGFloat(50)])
        var actualTwoChoicesValues = Set<CGFloat>()
        for _ in 1...1000 {
            let value = CGFloat.random(in: 0..<100, choices: 2)
            actualTwoChoicesValues.insert(value)
        }
        XCTAssertEqual(actualTwoChoicesValues, expectedTwoChoicesValues)

        let expectedSixChoicesValues = Set([0, 0.25, 0.5, 0.75, 1, 1.25].map { CGFloat($0) })
        var actualSixChoicesValues = Set<CGFloat>()
        for _ in 1...10000 {
            let value = CGFloat.random(in: 0..<1.5, choices: 6)
            actualSixChoicesValues.insert(value)
        }
        XCTAssertEqual(actualSixChoicesValues, expectedSixChoicesValues)
    }
}
