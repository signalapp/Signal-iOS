//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class NSRangeUtilTests: XCTestCase {

    class TestObject: NSRangeProviding, Equatable {
        let range: NSRange
        let id: UUID

        required init(id: UUID = UUID(), _ location: Int, _ length: Int) {
            self.id = id
            self.range = NSRange(location: location, length: length)
        }

        func copyWithNewRange(_ range: NSRange) -> Self {
            return Self.init(id: id, range.location, range.length)
        }

        static func == (lhs: NSRangeUtilTests.TestObject, rhs: NSRangeUtilTests.TestObject) -> Bool {
            return lhs.id == rhs.id && lhs.range == rhs.range
        }
    }

    func testPartialOverlap() {
        var originals: [TestObject] = [
            .init(0, 2)
        ]
        var replacements: [TestObject] = [
            .init(1, 2)
        ]
        var output = NSRangeUtil.replacingRanges(in: originals, withOverlapsIn: replacements)
        XCTAssertEqual(output, [
            .init(id: originals[0].id, 0, 1),
            .init(id: replacements[0].id, 1, 2)
        ])

        originals = [
            .init(2, 2)
        ]
        replacements = [
            .init(1, 2)
        ]
        output = NSRangeUtil.replacingRanges(in: originals, withOverlapsIn: replacements)
        XCTAssertEqual(output, [
            .init(id: replacements[0].id, 1, 2),
            .init(id: originals[0].id, 3, 1)
        ])

        // Both overlapping at once
        originals = [
            .init(0, 2),
            .init(2, 2)
        ]
        replacements = [
            .init(1, 2)
        ]
        output = NSRangeUtil.replacingRanges(in: originals, withOverlapsIn: replacements)
        XCTAssertEqual(output, [
            .init(id: originals[0].id, 0, 1),
            .init(id: replacements[0].id, 1, 2),
            .init(id: originals[1].id, 3, 1)
        ])
    }

    func testTotalOverlap() {
        var originals: [TestObject] = [
            .init(0, 2)
        ]
        var replacements: [TestObject] = [
            .init(0, 2)
        ]
        var output = NSRangeUtil.replacingRanges(in: originals, withOverlapsIn: replacements)
        XCTAssertEqual(output, [
            .init(id: replacements[0].id, 0, 2)
        ])

        originals = [
            .init(1, 2)
        ]
        replacements = [
            .init(0, 4)
        ]
        output = NSRangeUtil.replacingRanges(in: originals, withOverlapsIn: replacements)
        XCTAssertEqual(output, [
            .init(id: replacements[0].id, 0, 4)
        ])
    }

    func testOverlapInside() {
        var originals: [TestObject] = [
            .init(0, 4)
        ]
        var replacements: [TestObject] = [
            .init(1, 2)
        ]
        var output = NSRangeUtil.replacingRanges(in: originals, withOverlapsIn: replacements)
        XCTAssertEqual(output, [
            .init(id: originals[0].id, 0, 1),
            .init(id: replacements[0].id, 1, 2),
            .init(id: originals[0].id, 3, 1)
        ])

        originals = [
            .init(0, 10)
        ]
        replacements = [
            .init(0, 2),
            .init(4, 2),
            .init(8, 2)
        ]
        output = NSRangeUtil.replacingRanges(in: originals, withOverlapsIn: replacements)
        XCTAssertEqual(output, [
            .init(id: replacements[0].id, 0, 2),
            .init(id: originals[0].id, 2, 2),
            .init(id: replacements[1].id, 4, 2),
            .init(id: originals[0].id, 6, 2),
            .init(id: replacements[2].id, 8, 2)
        ])
    }
}
