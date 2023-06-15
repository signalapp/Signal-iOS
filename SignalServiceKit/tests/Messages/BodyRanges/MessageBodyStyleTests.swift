//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

final class MessageBodyStyleTests: XCTestCase {

    typealias Style = MessageBodyRanges.Style
    typealias SingleStyle = MessageBodyRanges.SingleStyle
    typealias MergedSingleStyle = MessageBodyRanges.MergedSingleStyle

    // Enforce that the SingleStyle and OptionSet don't break invariants.
    func testOptionSet() throws {
        var testedCases = [SingleStyle]()
        XCTAssertEqual(Style.bold, Style(rawValue: SingleStyle.bold.rawValue))
        testedCases.append(.bold)
        XCTAssertEqual(Style.italic, Style(rawValue: SingleStyle.italic.rawValue))
        testedCases.append(.italic)
        XCTAssertEqual(Style.spoiler, Style(rawValue: SingleStyle.spoiler.rawValue))
        testedCases.append(.spoiler)
        XCTAssertEqual(Style.strikethrough, Style(rawValue: SingleStyle.strikethrough.rawValue))
        testedCases.append(.strikethrough)
        XCTAssertEqual(Style.monospace, Style(rawValue: SingleStyle.monospace.rawValue))
        testedCases.append(.monospace)

        XCTAssertEqual(testedCases, SingleStyle.allCases)
        var allStyle = Style()
        allStyle.insert(.bold)
        allStyle.insert(.italic)
        allStyle.insert(.spoiler)
        allStyle.insert(.strikethrough)
        allStyle.insert(.monospace)
        XCTAssertEqual(
            allStyle,
            Style(testedCases.map { Style(rawValue: $0.rawValue) })
        )
        testedCases.forEach {
            XCTAssert(allStyle.contains(Style(rawValue: $0.rawValue)))
        }
        testedCases.forEach {
            XCTAssertFalse(Style().contains(Style(rawValue: $0.rawValue)))
        }
    }

    func testMergeSingleStyle() {
        // Overlap
        XCTAssertEqual(
            MergedSingleStyle.merge(sortedOriginals: [
                NSRangedValue(.bold, range: NSRange(location: 0, length: 2)),
                NSRangedValue(.bold, range: NSRange(location: 1, length: 2))
            ]),
            [
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 0, length: 3))
            ]
        )
        // Adjacent (doesn't merge)
        XCTAssertEqual(
            MergedSingleStyle.merge(sortedOriginals: [
                NSRangedValue(.bold, range: NSRange(location: 0, length: 2)),
                NSRangedValue(.bold, range: NSRange(location: 2, length: 2))
            ]),
            [
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 0, length: 2)),
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 2, length: 2))
            ]
        )
        // Adjacent (merging)
        XCTAssertEqual(
            MergedSingleStyle.merge(
                sortedOriginals: [
                    NSRangedValue(.bold, range: NSRange(location: 0, length: 2)),
                    NSRangedValue(.bold, range: NSRange(location: 2, length: 2))
                ],
                mergeAdjacentRangesOfSameStyle: true
            ),
            [
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 0, length: 4))
            ]
        )
        // One inside the other
        XCTAssertEqual(
            MergedSingleStyle.merge(sortedOriginals: [
                NSRangedValue(.bold, range: NSRange(location: 0, length: 5)),
                NSRangedValue(.bold, range: NSRange(location: 2, length: 2))
            ]),
            [
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 0, length: 5))
            ]
        )
        // Not touching at all
        XCTAssertEqual(
            MergedSingleStyle.merge(sortedOriginals: [
                NSRangedValue(.bold, range: NSRange(location: 0, length: 2)),
                NSRangedValue(.bold, range: NSRange(location: 3, length: 2))
            ]),
            [
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 0, length: 2)),
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 3, length: 2))
            ]
        )
        // Mutliple overlapping
        XCTAssertEqual(
            MergedSingleStyle.merge(sortedOriginals: [
                NSRangedValue(.bold, range: NSRange(location: 0, length: 5)),
                NSRangedValue(.bold, range: NSRange(location: 3, length: 5)),
                NSRangedValue(.bold, range: NSRange(location: 7, length: 5))
            ]),
            [
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 0, length: 12))
            ]
        )
        // Mutliple overlapping segments
        XCTAssertEqual(
            MergedSingleStyle.merge(sortedOriginals: [
                NSRangedValue(.bold, range: NSRange(location: 0, length: 2)),
                NSRangedValue(.bold, range: NSRange(location: 1, length: 2)),
                NSRangedValue(.bold, range: NSRange(location: 10, length: 2)),
                NSRangedValue(.bold, range: NSRange(location: 12, length: 2))
            ]),
            [
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 0, length: 3)),
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 10, length: 2)),
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 12, length: 2))
            ]
        )
    }

    func testMergeMultiStyle() {
        // Overlap two of different styles
        XCTAssertEqual(
            MergedSingleStyle.merge(sortedOriginals: [
                NSRangedValue(.bold, range: NSRange(location: 0, length: 2)),
                NSRangedValue(.italic, range: NSRange(location: 1, length: 2))
            ]),
            [
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 0, length: 2)),
                MergedSingleStyle(style: .italic, mergedRange: NSRange(location: 1, length: 2))
            ]
        )
        // Merge two bolds and don't let an italic interrupt.
        XCTAssertEqual(
            MergedSingleStyle.merge(sortedOriginals: [
                NSRangedValue(.bold, range: NSRange(location: 0, length: 3)),
                NSRangedValue(.bold, range: NSRange(location: 2, length: 2)),
                NSRangedValue(.italic, range: NSRange(location: 1, length: 3))
            ]),
            [
                MergedSingleStyle(style: .bold, mergedRange: NSRange(location: 0, length: 4)),
                MergedSingleStyle(style: .italic, mergedRange: NSRange(location: 1, length: 3))
            ]
        )
    }
}
