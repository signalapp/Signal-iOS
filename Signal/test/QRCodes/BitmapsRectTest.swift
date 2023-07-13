//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class BitmapsRectTest: XCTestCase {
    private typealias Rect = Bitmaps.Rect
    private typealias Point = Bitmaps.Point

    func testSquareRectCirclePointContains() {
        let size = 11
        let rect = Bitmaps.Rect(x: 0, y: 0, width: size, height: size)

        let testCases: [(Point, Bool)] = [
            (Point(x: 0, y: 0), false),
            (Point(x: 5, y: 0), true),
            (Point(x: 0, y: 5), true),
            (Point(x: 1, y: 1), false),
            (Point(x: 2, y: 1), true),
            (Point(x: 1, y: 2), true)
        ]

        for (point, outcome) in testCases {
            XCTAssertEqual(
                rect.inscribedCircleContains(point),
                outcome
            )
        }
    }

    func testNonSquareRectCirclePointContains() {
        let rect = Bitmaps.Rect(x: 0, y: 0, width: 99, height: 5)

        let testCases: [(Point, Bool)] = [
            (Point(x: 49, y: 2), true),
            (Point(x: 48, y: 2), true),
            (Point(x: 47, y: 2), true),
            (Point(x: 46, y: 2), false),
            (Point(x: 49, y: 1), true),
            (Point(x: 48, y: 1), true),
            (Point(x: 47, y: 1), false),
        ]

        for (point, outcome) in testCases {
            XCTAssertEqual(
                rect.inscribedCircleContains(point),
                outcome,
                "\(point)"
            )
        }
    }

    func testCGRectFromRect() {
        let testCases: [(Rect, CGFloat, CGFloat, CGRect)] = [
            (
                Rect(x: 0, y: 0, width: 1, height: 1),
                1,
                0,
                CGRect(x: 0.5, y: 0.5, maxX: 0.5, maxY: 0.5)
            ),
            (
                Rect(x: 0, y: 0, width: 2, height: 2),
                1,
                0,
                CGRect(x: 0.5, y: 0.5, maxX: 1.5, maxY: 1.5)
            ),
            (
                Rect(x: 0, y: 0, width: 2, height: 2),
                1,
                0.5,
                CGRect(x: 1, y: 1, maxX: 1, maxY: 1)
            ),
            (
                Rect(x: 0, y: 0, width: 2, height: 2),
                1,
                0.25,
                CGRect(x: 0.75, y: 0.75, maxX: 1.25, maxY: 1.25)
            ),
            (
                Rect(x: 0, y: 0, width: 5, height: 5),
                5,
                0,
                CGRect(x: 2.5, y: 2.5, maxX: 22.5, maxY: 22.5)
            ),
            (
                Rect(x: 0, y: 0, width: 5, height: 5),
                5,
                0.5,
                CGRect(x: 5, y: 5, maxX: 20, maxY: 20)
            )
        ]

        for (rect, scale, inset, outcome) in testCases {
            XCTAssertEqual(
                rect.cgRect(scaledBy: scale, insetBy: inset),
                outcome,
                "Test case { \(rect), \(scale), \(inset) } failed!"
            )
        }
    }
}

private extension CGRect {
    /// Create a rect from the origin and opposite corner.
    init(x: CGFloat, y: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        self.init(x: x, y: y, width: maxX - x, height: maxY - y)
    }
}
