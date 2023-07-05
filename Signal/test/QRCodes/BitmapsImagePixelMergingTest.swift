//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

/// Do bitmap images correctly merge adjacent pixels?
class BitmapsImagePixelMergingTest: XCTestCase {
    func testMergeAdjacentPixels() {
        for testCase in TestCase.all {
            XCTAssertEqual(
                testCase.image.gridDrawingByMergingAdjacentPixels(
                    deadzone: testCase.deadzone
                ),
                testCase.gridDrawing
            )
        }
    }
}

private struct TestCase {
    let image: Bitmaps.Image
    let deadzone: Bitmaps.Rect
    let gridDrawing: Bitmaps.GridDrawing

    static let all: [TestCase] = [.one, .two, .three]

    /// 3x4, all filled in, no dead zone.
    static let one: TestCase = TestCase(
        image: Bitmaps.Image(width: 3, height: 4, bytes: [Byte](repeating: .xxx, count: 12)),
        deadzone: Bitmaps.Rect(x: 0, y: 0, width: 0, height: 0),
        gridDrawing: Bitmaps.GridDrawing( width: 3, height: 4, segments: [
            .horizontal(x: 0, y: 0, length: 3),
            .horizontal(x: 0, y: 1, length: 3),
            .horizontal(x: 0, y: 2, length: 3),
            .horizontal(x: 0, y: 3, length: 3),
            .vertical(x: 0, y: 0, length: 4),
            .vertical(x: 1, y: 0, length: 4),
            .vertical(x: 2, y: 0, length: 4)
        ])
    )

    /// 6x6, mostly filled in, with a central deadzone.
    static let two: TestCase = TestCase(
        image: Bitmaps.Image(width: 6, height: 6, bytes: [
            .xxx, .xxx, .xxx, .xxx, .xxx, .xxx,
            .xxx, .xxx, .xxx, .xxx, .ooo, .xxx,
            .xxx, .xxx, .xxx, .xxx, .xxx, .xxx,
            .xxx, .xxx, .ooo, .xxx, .xxx, .xxx,
            .xxx, .xxx, .xxx, .xxx, .xxx, .xxx,
            .xxx, .xxx, .xxx, .xxx, .xxx, .ooo
        ]),
        deadzone: Bitmaps.Rect(x: 2, y: 2, width: 2, height: 2),
        gridDrawing: Bitmaps.GridDrawing(width: 6, height: 6, segments: [
            .horizontal(x: 0, y: 0, length: 6),
            .horizontal(x: 0, y: 1, length: 4),
            .horizontal(x: 5, y: 1, length: 1),
            .horizontal(x: 0, y: 2, length: 2),
            .horizontal(x: 4, y: 2, length: 2),
            .horizontal(x: 0, y: 3, length: 2),
            .horizontal(x: 4, y: 3, length: 2),
            .horizontal(x: 0, y: 4, length: 6),
            .horizontal(x: 0, y: 5, length: 5),
            .vertical(x: 0, y: 0, length: 6),
            .vertical(x: 1, y: 0, length: 6),
            .vertical(x: 2, y: 0, length: 2),
            .vertical(x: 2, y: 4, length: 2),
            .vertical(x: 3, y: 0, length: 2),
            .vertical(x: 3, y: 4, length: 2),
            .vertical(x: 4, y: 0, length: 1),
            .vertical(x: 4, y: 2, length: 4),
            .vertical(x: 5, y: 0, length: 5)
        ])
    )

    /// 7x7, fully filled in, with a central deadzone.
    static let three: TestCase = TestCase(
        image: Bitmaps.Image(width: 7, height: 7, bytes: [
            .xxx, .xxx, .xxx, .xxx, .xxx, .xxx, .xxx,
            .xxx, .xxx, .xxx, .xxx, .xxx, .xxx, .xxx,
            .xxx, .xxx, .xxx, .xxx, .xxx, .xxx, .xxx,
            .xxx, .xxx, .xxx, .xxx, .xxx, .xxx, .xxx,
            .xxx, .xxx, .xxx, .xxx, .xxx, .xxx, .xxx,
            .xxx, .xxx, .xxx, .xxx, .xxx, .xxx, .xxx,
            .xxx, .xxx, .xxx, .xxx, .xxx, .xxx, .xxx
        ]),
        deadzone: Bitmaps.Rect(x: 2, y: 2, width: 3, height: 3),
        gridDrawing: Bitmaps.GridDrawing(width: 7, height: 7, segments: [
            .horizontal(x: 0, y: 0, length: 7),
            .horizontal(x: 0, y: 1, length: 7),
            .horizontal(x: 0, y: 2, length: 2),
            .horizontal(x: 5, y: 2, length: 2),
            .horizontal(x: 0, y: 3, length: 2),
            .horizontal(x: 5, y: 3, length: 2),
            .horizontal(x: 0, y: 4, length: 2),
            .horizontal(x: 5, y: 4, length: 2),
            .horizontal(x: 0, y: 5, length: 7),
            .horizontal(x: 0, y: 6, length: 7),
            .vertical(x: 0, y: 0, length: 7),
            .vertical(x: 1, y: 0, length: 7),
            .vertical(x: 2, y: 0, length: 2),
            .vertical(x: 2, y: 5, length: 2),
            .vertical(x: 3, y: 0, length: 2),
            .vertical(x: 3, y: 5, length: 2),
            .vertical(x: 4, y: 0, length: 2),
            .vertical(x: 4, y: 5, length: 2),
            .vertical(x: 5, y: 0, length: 7),
            .vertical(x: 6, y: 0, length: 7)
        ])
    )
}

private extension Bitmaps.GridDrawing.Segment {
    static func horizontal(x: Int, y: Int, length: Int) -> Bitmaps.GridDrawing.Segment {
        return Bitmaps.GridDrawing.Segment(
            dimension: .horizontal,
            start: Bitmaps.Point(x: x, y: y),
            length: length
        )
    }

    static func vertical(x: Int, y: Int, length: Int) -> Bitmaps.GridDrawing.Segment {
        return Bitmaps.GridDrawing.Segment(
            dimension: .vertical,
            start: Bitmaps.Point(x: x, y: y),
            length: length
        )
    }
}

/// Binary, but with the same number of characters in "one" and "zero".
private enum Byte {
    case xxx
    case ooo
}

private extension Bitmaps.Image {
    init(width: Int, height: Int, bytes: [Byte]) {
        self.init(width: width, height: height, rawBytes: bytes.asRawBytes)
    }
}

private extension Array where Element == Byte {
    var asRawBytes: [UInt8] {
        return flatMap { byte in
            switch byte {
            case .xxx:
                return [UInt8(integerLiteral: 1), 1, 1, 1]
            case .ooo:
                return [UInt8(integerLiteral: 0), 0, 0, 0]
            }
        }
    }
}
