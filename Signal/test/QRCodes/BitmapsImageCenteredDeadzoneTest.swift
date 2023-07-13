//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

/// Do we correctly compute "centered deadzones" of images?
class BitmapsImageCenteredDeadzoneTest: XCTestCase {
    func testCenteredDeadzones() {
        for testCase in TestCase.all {
            XCTAssertEqual(
                testCase.image.centeredDeadzone(
                    dimensionPercentage: testCase.percentage,
                    paddingPoints: testCase.paddingPoints
                ),
                testCase.expectedRect
            )
        }
    }
}

private struct TestCase {
    let image: Bitmaps.Image
    let percentage: CGFloat
    let paddingPoints: Int
    let expectedRect: Bitmaps.Rect

    static let all: [TestCase] = [
        .usernameLinkQRCodeSize,
        .evenRemainder,
        .oddRemainder
    ]

    static let usernameLinkQRCodeSize = TestCase(
        image: Bitmaps.Image(width: 39, height: 39, rawBytes: []),
        percentage: 1/3,
        paddingPoints: 0,
        expectedRect: Bitmaps.Rect(x: 13, y: 13, width: 13, height: 13)
    )

    static let evenRemainder = TestCase(
        image: Bitmaps.Image(width: 30, height: 30, rawBytes: []),
        percentage: 1/3,
        paddingPoints: 0,
        expectedRect: Bitmaps.Rect(x: 10, y: 10, width: 10, height: 10)
    )

    static let evenRemainderWithPadding = TestCase(
        image: Bitmaps.Image(width: 30, height: 30, rawBytes: []),
        percentage: 1/3,
        paddingPoints: 1,
        expectedRect: Bitmaps.Rect(x: 9, y: 9, width: 11, height: 11)
    )

    static let oddRemainder = TestCase(
        image: Bitmaps.Image(width: 30, height: 41, rawBytes: []),
        percentage: 0.25,
        paddingPoints: 0,
        expectedRect: Bitmaps.Rect(x: 11, y: 15, width: 8, height: 11)
    )
}

extension Bitmaps.Rect: Equatable {
    public static func == (lhs: Bitmaps.Rect, rhs: Bitmaps.Rect) -> Bool {
        return lhs.origin == rhs.origin
        && lhs.height == rhs.height
        && lhs.width == rhs.width
    }
}
