//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

public class StyleOnlyMessageBodyTests: XCTestCase {

    typealias MergedSingleStyle = MessageBodyRanges.MergedSingleStyle
    typealias CollapsedStyle = MessageBodyRanges.CollapsedStyle

    // MARK: - dropFirst

    public func testStripAndDropFirst_droppedStyle() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: "Hello World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 5)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            ).stripAndDropFirst(6),
            StyleOnlyMessageBody(
                text: "World",
                collapsedStyles: []
            )
        )
    }

    public func testStripAndDropFirst_cutOffStyle() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: "Hello World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 11)
                    )
                ]
            ).stripAndDropFirst(6),
            StyleOnlyMessageBody(
                text: "World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            )
        )
    }

    public func testStripAndDropFirst_includedStyle() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: "Hello World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 6, length: 5)
                                )
                            ]),
                        range: NSRange(location: 6, length: 5)
                    )
                ]
            ).stripAndDropFirst(6),
            StyleOnlyMessageBody(
                text: "World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 6, length: 5)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            )
        )
    }

    public func testStripAndDropFirst_stripMiddle() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: "Hello World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 11)
                    )
                ]
            ).stripAndDropFirst(5),
            StyleOnlyMessageBody(
                text: "World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            )
        )
    }

    public func testStripAndDropFirst_stripLeading() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: " Hello World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 1, length: 11)
                                )
                            ]),
                        range: NSRange(location: 1, length: 11)
                    )
                ]
            ).stripAndDropFirst(5),
            StyleOnlyMessageBody(
                text: "World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 1, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            )
        )
    }

    public func testStripAndDropFirst_stripLeadingAndTrailing() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: " Hello World ",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 1, length: 11)
                                )
                            ]),
                        range: NSRange(location: 1, length: 11)
                    )
                ]
            ).stripAndDropFirst(5),
            StyleOnlyMessageBody(
                text: "World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 1, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            )
        )
    }

    // MARK: - dropLast

    public func testStripAndDropLast_droppedStyle() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: "Hello World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 6, length: 5)
                                )
                            ]),
                        range: NSRange(location: 6, length: 5)
                    )
                ]
            ).stripAndDropLast(6),
            StyleOnlyMessageBody(
                text: "Hello",
                collapsedStyles: []
            )
        )
    }

    public func testStripAndDropLast_cutOffStyle() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: "Hello World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 11)
                    )
                ]
            ).stripAndDropLast(6),
            StyleOnlyMessageBody(
                text: "Hello",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            )
        )
    }

    public func testStripAndDropLast_includedStyle() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: "Hello World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 5)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            ).stripAndDropLast(6),
            StyleOnlyMessageBody(
                text: "Hello",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 5)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            )
        )
    }

    public func testStripAndDropLast_stripMiddle() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: "Hello World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 11)
                    )
                ]
            ).stripAndDropLast(5),
            StyleOnlyMessageBody(
                text: "Hello",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 0, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            )
        )
    }

    public func testStripAndDropLast_stripLeading() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: " Hello World",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 1, length: 11)
                                )
                            ]),
                        range: NSRange(location: 1, length: 11)
                    )
                ]
            ).stripAndDropLast(5),
            StyleOnlyMessageBody(
                text: "Hello",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 1, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            )
        )
    }

    public func testStripAndDropLast_stripLeadingAndTrailing() {
        XCTAssertEqual(
            StyleOnlyMessageBody(
                text: " Hello World ",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 1, length: 11)
                                )
                            ]),
                        range: NSRange(location: 1, length: 11)
                    )
                ]
            ).stripAndDropLast(5),
            StyleOnlyMessageBody(
                text: "Hello",
                collapsedStyles: [
                    .init(
                        CollapsedStyle(
                            style: .bold,
                            originals: [
                                .bold: MergedSingleStyle(
                                    style: .bold,
                                    mergedRange: NSRange(location: 1, length: 11)
                                )
                            ]),
                        range: NSRange(location: 0, length: 5)
                    )
                ]
            )
        )
    }
}
