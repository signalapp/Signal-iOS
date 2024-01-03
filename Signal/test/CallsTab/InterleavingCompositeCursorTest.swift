//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class InterleavingCompositeCursorTest: XCTestCase {
    func testInterleaving() {
        let cursors: [[Int?]] = [
            [1, 4, 7],
            [2, 5, 8],
            [3, 6, 9],
        ]

        let interleavingCursor = InterleavingCompositeCursor(cursors.map { ArrayCursor($0) })

        XCTAssertEqual(
            interleavingCursor.drain(),
            [1, 2, 3, 4, 5, 6, 7, 8, 9]
        )
    }

    func testInterleavingWithUnsortedCursors() {
        let cursors: [[Int?]] = [
            [9, 6, 3],
            [2, 8, 5],
            [7, 1, 4],
        ]

        let interleavingCursor = InterleavingCompositeCursor(cursors.map { ArrayCursor($0) })

        XCTAssertEqual(
            interleavingCursor.drain(),
            [2, 7, 1, 4, 8, 5, 9, 6, 3]
        )
    }

    func testInterleavingWithInterruptedCursor() {
        // A `nil` return will indicate that the cursor is done, and all values
        // thereafter will not be asked for.
        let cursors: [[Int?]] = [
            [nil, 5, 8],
            [3, 6, 9],
            [1, nil, 7],
        ]

        let interleavingCursor = InterleavingCompositeCursor(cursors.map { ArrayCursor($0) })

        XCTAssertEqual(
            interleavingCursor.drain(),
            [1, 3, 6, 9]
        )
    }
}

private extension InterleavingCompositeCursor<ArrayCursor<Int>> {
    convenience init(_ elements: [ArrayCursor<Int>]) {
        try! self.init(
            interleaving: elements,
            nextElementComparator: { $0 < $1 }
        )
    }
}

private struct ArrayCursor<Element: Comparable>: InterleavableCursor {
    private var elements: [Element?]

    init(_ elements: [Element?]) {
        self.elements = elements
    }

    mutating func nextElement() throws -> Element? {
        guard let first = elements.first else {
            return nil
        }

        elements = Array(elements.dropFirst())
        return first
    }
}

private extension InterleavingCompositeCursor {
    func drain() -> [CursorType.Element] {
        var elements: [CursorType.Element] = []

        while let nextElement = try! next() {
            elements.append(nextElement)
        }

        return elements
    }
}
