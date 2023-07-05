//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class BitmapsRectTest: XCTestCase {
    private typealias Rect = Bitmaps.Rect
    private typealias Point = Bitmaps.Point

    func testRectContains() {
        let testCases: [(Rect, Point, Bool)] = [
            (Rect(x: 0, y: 0, width: 10, height: 10), Point(x: 0, y: 0), true),
            (Rect(x: 0, y: 0, width: 10, height: 10), Point(x: 1, y: 1), true),
            (Rect(x: 0, y: 0, width: 10, height: 10), Point(x: 0, y: 10), false),
            (Rect(x: 0, y: 0, width: 10, height: 10), Point(x: 10, y: 0), false),
            (Rect(x: 0, y: 0, width: 0, height: 0), Point(x: 0, y: 0), false),
            (Rect(x: 0, y: 0, width: 10, height: 0), Point(x: 0, y: 0), false),
            (Rect(x: 0, y: 0, width: 0, height: 10), Point(x: 0, y: 0), false),
            (Rect(x: 0, y: 0, width: 10, height: 10), Point(x: 40, y: 40), false)
        ]

        for (rect, point, outcome) in testCases {
            XCTAssertEqual(
                rect.contains(point),
                outcome
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
