//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing
import XCTest

@testable import SignalServiceKit

final class MessageBodyTests: XCTestCase {

    typealias Style = MessageBodyRanges.Style
    typealias SingleStyle = MessageBodyRanges.SingleStyle
    typealias CollapsedStyle = MessageBodyRanges.CollapsedStyle

    // MARK: - Hydration

    let acis = (0...5).map { _ in Aci.randomForTesting() }

    func testHydration_noMentions() {
        runHydrationTest(
            input: .init(
                text: "Hello",
                ranges: .init(
                    mentions: [],
                    styles: [],
                ),
            ),
            names: [:],
            output: .init(
                hydratedText: "Hello",
                mentionAttributes: [],
                styleAttributes: [],
            ),
        )
    }

    func testHydration_singleMention() {
        runHydrationTest(
            input: .init(
                text: "Hello @",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 6, length: 1)),
                    ],
                    styles: [],
                ),
            ),
            names: [acis[0]: "Luke"],
            output: .init(
                hydratedText: "Hello @Luke",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 6, length: 1),
                            mentionAci: acis[0],
                            displayName: "Luke",
                        ),
                        range: NSRange(location: 6, length: 5),
                    ),
                ],
                styleAttributes: [],
            ),
        )
    }

    func testHydration_multipleMentions() {
        runHydrationTest(
            input: .init(
                text: "Hello @ and @, how is @?",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 6, length: 1)),
                        NSRangedValue(acis[1], range: NSRange(location: 12, length: 1)),
                        NSRangedValue(acis[2], range: NSRange(location: 22, length: 1)),
                    ],
                    styles: [],
                ),
            ),
            names: [
                acis[0]: "Luke",
                acis[1]: "Leia",
                acis[2]: "Han",
            ],
            output: .init(
                hydratedText: "Hello @Luke and @Leia, how is @Han?",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 6, length: 1),
                            mentionAci: acis[0],
                            displayName: "Luke",
                        ),
                        range: NSRange(location: 6, length: 5),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 12, length: 1),
                            mentionAci: acis[1],
                            displayName: "Leia",
                        ),
                        range: NSRange(location: 16, length: 5),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 22, length: 1),
                            mentionAci: acis[2],
                            displayName: "Han",
                        ),
                        range: NSRange(location: 30, length: 4),
                    ),
                ],
                styleAttributes: [],
            ),
        )
    }

    /// Strictly speaking, mentions should always have length 1 when sent
    /// in messages. But best not to crash due to an antagonistic sender.
    func testHydration_nonSingularLengthMentions() {
        runHydrationTest(
            input: .init(
                text: "Hello @wasd and @1, how is ?",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 6, length: 5)),
                        NSRangedValue(acis[1], range: NSRange(location: 16, length: 2)),
                        NSRangedValue(acis[2], range: NSRange(location: 27, length: 0)),
                    ],
                    styles: [],
                ),
            ),
            names: [
                acis[0]: "Luke",
                acis[1]: "Leia",
            ],
            output: .init(
                hydratedText: "Hello @Luke and @Leia, how is ?",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 6, length: 5),
                            mentionAci: acis[0],
                            displayName: "Luke",
                        ),
                        range: NSRange(location: 6, length: 5),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 16, length: 2),
                            mentionAci: acis[1],
                            displayName: "Leia",
                        ),
                        range: NSRange(location: 16, length: 5),
                    ),
                ],
                styleAttributes: [],
            ),
        )
    }

    func testHydration_notAllHydrated() {
        runHydrationTest(
            input: .init(
                text: "Hello @ and @, how is @?",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 6, length: 1)),
                        NSRangedValue(acis[1], range: NSRange(location: 12, length: 1)),
                        NSRangedValue(acis[2], range: NSRange(location: 22, length: 1)),
                    ],
                    styles: [],
                ),
            ),
            names: [
                acis[0]: "Luke",
                acis[2]: "Han",
            ],
            output: .init(
                hydratedText: "Hello @Luke and @, how is @Han?",
                unhydratedMentions: [
                    .init(
                        .fromOriginalRange(NSRange(location: 12, length: 1), mentionAci: acis[1]),
                        range: NSRange(location: 16, length: 1),
                    ),
                ],
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 6, length: 1),
                            mentionAci: acis[0],
                            displayName: "Luke",
                        ),
                        range: NSRange(location: 6, length: 5),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 22, length: 1),
                            mentionAci: acis[2],
                            displayName: "Han",
                        ),
                        range: NSRange(location: 26, length: 4),
                    ),
                ],
                styleAttributes: [],
            ),
        )
    }

    func testHydration_justStyles() {
        runHydrationTest(
            input: .init(
                text: "This is bold, italic, and mono",
                ranges: .init(
                    mentions: [],
                    styles: [
                        .init(.bold, range: NSRange(location: 8, length: 4)),
                        .init(.italic, range: NSRange(location: 14, length: 6)),
                        .init(.monospace, range: NSRange(location: 26, length: 4)),
                    ],
                ),
            ),
            names: [:],
            output: .init(
                hydratedText: "This is bold, italic, and mono",
                mentionAttributes: [],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 8, length: 4)),
                        ),
                        range: NSRange(location: 8, length: 4),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.italic, mergedRange: NSRange(location: 14, length: 6)),
                        ),
                        range: NSRange(location: 14, length: 6),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.monospace, mergedRange: NSRange(location: 26, length: 4)),
                        ),
                        range: NSRange(location: 26, length: 4),
                    ),
                ],
            ),
        )
    }

    func testHydration_stylesAndTrailingMention() {
        runHydrationTest(
            input: .init(
                text: "This is bold, italic, and mono, @.",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 32, length: 1)),
                    ],
                    styles: [
                        .init(.bold, range: NSRange(location: 8, length: 4)),
                        .init(.italic, range: NSRange(location: 14, length: 6)),
                        .init(.monospace, range: NSRange(location: 26, length: 4)),
                    ],
                ),
            ),
            names: [acis[0]: "Luke"],
            output: .init(
                hydratedText: "This is bold, italic, and mono, @Luke.",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 32, length: 1),
                            mentionAci: acis[0],
                            displayName: "Luke",
                        ),
                        range: NSRange(location: 32, length: 5),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 8, length: 4)),
                        ),
                        range: NSRange(location: 8, length: 4),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.italic, mergedRange: NSRange(location: 14, length: 6)),
                        ),
                        range: NSRange(location: 14, length: 6),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.monospace, mergedRange: NSRange(location: 26, length: 4)),
                        ),
                        range: NSRange(location: 26, length: 4),
                    ),
                ],
            ),
        )
    }

    func testHydration_stylesAndLeadingMention() {
        runHydrationTest(
            input: .init(
                text: "@, this is bold, italic, and mono",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 0, length: 1)),
                    ],
                    styles: [
                        .init(.bold, range: NSRange(location: 11, length: 4)),
                        .init(.italic, range: NSRange(location: 17, length: 6)),
                        .init(.monospace, range: NSRange(location: 29, length: 4)),
                    ],
                ),
            ),
            names: [acis[0]: "Luke"],
            output: .init(
                hydratedText: "@Luke, this is bold, italic, and mono",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 0, length: 1),
                            mentionAci: acis[0],
                            displayName: "Luke",
                        ),
                        range: NSRange(location: 0, length: 5),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 11, length: 4)),
                        ),
                        range: NSRange(location: 15, length: 4),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.italic, mergedRange: NSRange(location: 17, length: 6)),
                        ),
                        range: NSRange(location: 21, length: 6),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.monospace, mergedRange: NSRange(location: 29, length: 4)),
                        ),
                        range: NSRange(location: 33, length: 4),
                    ),
                ],
            ),
        )
    }

    func testHydration_overlappingStyleAndMention() {
        runHydrationTest(
            input: .init(
                text: "Use the force, @",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 15, length: 1)),
                    ],
                    styles: [
                        .init(.italic, range: NSRange(location: 0, length: 16)),
                    ],
                ),
            ),
            names: [acis[0]: "Luke"],
            output: .init(
                hydratedText: "Use the force, @Luke",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 15, length: 1),
                            mentionAci: acis[0],
                            displayName: "Luke",
                        ),
                        range: NSRange(location: 15, length: 5),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.italic, mergedRange: NSRange(location: 0, length: 16)),
                        ),
                        range: NSRange(location: 0, length: 20),
                    ),
                ],
            ),
        )
    }

    func testHydration_styleOverlappingTwoMentions() {
        runHydrationTest(
            input: .init(
                text: "@@ and @@ are stylish people.",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 0, length: 2)),
                        NSRangedValue(acis[1], range: NSRange(location: 7, length: 2)),
                    ],
                    styles: [
                        .init(.bold, range: NSRange(location: 1, length: 7)),
                    ],
                ),
            ),
            names: [
                acis[0]: "BoldGuy1",
                acis[1]: "BoldGuy2",
            ],
            output: .init(
                hydratedText: "@BoldGuy1 and @BoldGuy2 are stylish people.",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 0, length: 2),
                            mentionAci: acis[0],
                            displayName: "BoldGuy1",
                        ),
                        range: NSRange(location: 0, length: 9),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 7, length: 2),
                            mentionAci: acis[1],
                            displayName: "BoldGuy2",
                        ),
                        range: NSRange(location: 14, length: 9),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 0, length: 9)),
                        ),
                        range: NSRange(location: 0, length: 23),
                    ),
                ],
            ),
        )
    }

    func testHydration_overlappingStylesAndMentions() {
        // The styles are flattened out into this before hydration applies:
        // .init(.bold, range: NSRange(location: 0, length: 3)),
        // .init(.bold.union(.italic), range: NSRange(location: 3, length: 3)),
        // .init(.bold, range: NSRange(location: 6, length: 2)),
        // .init(.bold.union(.monospace), range: NSRange(location: 8, length: 16)),
        // .init(.bold.union(.monospace).union(.spoiler), range: NSRange(location: 24, length: 3)),
        // .init(.bold.union(.spoiler), range: NSRange(location: 27, length: 4)),
        // .init(.bold, range: NSRange(location: 31, length: 20)),
        runHydrationTest(
            input: .init(
                text: "@, @@@, @@@@@@@@@@@@@@@ and @@@ are stylish people.",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 0, length: 1)),
                        NSRangedValue(acis[1], range: NSRange(location: 3, length: 3)),
                        NSRangedValue(acis[2], range: NSRange(location: 8, length: 15)),
                        NSRangedValue(acis[3], range: NSRange(location: 28, length: 3)),
                    ],
                    styles: [
                        .init(.bold, range: NSRange(location: 0, length: 51)),
                        .init(.italic, range: NSRange(location: 4, length: 1)),
                        .init(.monospace, range: NSRange(location: 12, length: 15)),
                        .init(.spoiler, range: NSRange(location: 24, length: 5)),
                    ],
                ),
            ),
            names: [
                acis[0]: "BoldGuy",
                acis[1]: "BoldItalicGuy",
                acis[2]: "BoldMonoGuy",
                acis[3]: "BoldSpoilerGuy",
            ],
            output: .init(
                hydratedText: "@BoldGuy, @BoldItalicGuy, @BoldMonoGuy and @BoldSpoilerGuy are stylish people.",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 0, length: 1),
                            mentionAci: acis[0],
                            displayName: "BoldGuy",
                        ),
                        range: NSRange(location: 0, length: 8),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 3, length: 3),
                            mentionAci: acis[1],
                            displayName: "BoldItalicGuy",
                        ),
                        range: NSRange(location: 10, length: 14),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 8, length: 15),
                            mentionAci: acis[2],
                            displayName: "BoldMonoGuy",
                        ),
                        range: NSRange(location: 26, length: 12),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 28, length: 3),
                            mentionAci: acis[3],
                            displayName: "BoldSpoilerGuy",
                        ),
                        range: NSRange(location: 43, length: 15),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 0, length: 51)),
                        ),
                        range: NSRange(location: 0, length: 10),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 51),
                                .italic: NSRange(location: 3, length: 3),
                            ]),
                        ),
                        range: NSRange(location: 10, length: 14),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 0, length: 51)),
                        ),
                        range: NSRange(location: 24, length: 2),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 51),
                                .monospace: NSRange(location: 8, length: 19),
                            ]),
                        ),
                        range: NSRange(location: 26, length: 13),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 51),
                                .monospace: NSRange(location: 8, length: 19),
                                .spoiler: NSRange(location: 24, length: 7),
                            ]),
                        ),
                        range: NSRange(location: 39, length: 3),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 51),
                                .spoiler: NSRange(location: 24, length: 7),
                            ]),
                        ),
                        range: NSRange(location: 42, length: 16),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 0, length: 51)),
                        ),
                        range: NSRange(location: 58, length: 20),
                    ),
                ],
            ),
        )
    }

    func testHydration_overlappingStylesAndSomeUnhydratedMentions() {
        // The styles are flattened out into this before hydration applies:
        // .init(, range: NSRange(location: 0, length: 3), .bold),
        // .init(, range: NSRange(location: 3, length: 3), .bold.union(.italic)),
        // .init(, range: NSRange(location: 6, length: 2), .bold),
        // .init(, range: NSRange(location: 8, length: 16), .bold.union(.monospace)),
        // .init(, range: NSRange(location: 24, length: 3), .bold.union(.monospace).union(.spoiler)),
        // .init(, range: NSRange(location: 27, length: 4), .bold.union(.spoiler)),
        // .init(, range: NSRange(location: 31, length: 20), .bold),
        runHydrationTest(
            input: .init(
                text: "@, @@@, @@@@@@@@@@@@@@@ and @@@ are stylish people.",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 0, length: 1)),
                        NSRangedValue(acis[1], range: NSRange(location: 3, length: 3)),
                        NSRangedValue(acis[2], range: NSRange(location: 8, length: 15)),
                        NSRangedValue(acis[3], range: NSRange(location: 28, length: 3)),
                    ],
                    styles: [
                        .init(.bold, range: NSRange(location: 0, length: 51)),
                        .init(.italic, range: NSRange(location: 4, length: 1)),
                        .init(.monospace, range: NSRange(location: 12, length: 15)),
                        .init(.spoiler, range: NSRange(location: 24, length: 5)),
                    ],
                ),
            ),
            names: [
                acis[0]: "BoldGuy",
                acis[3]: "BoldSpoilerGuy",
            ],
            output: .init(
                hydratedText: "@BoldGuy, @@@, @@@@@@@@@@@@@@@ and @BoldSpoilerGuy are stylish people.",
                unhydratedMentions: [
                    .init(.fromOriginalRange(NSRange(location: 3, length: 3), mentionAci: acis[1]), range: NSRange(location: 10, length: 3)),
                    .init(.fromOriginalRange(NSRange(location: 8, length: 15), mentionAci: acis[2]), range: NSRange(location: 15, length: 15)),
                ],
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 0, length: 1),
                            mentionAci: acis[0],
                            displayName: "BoldGuy",
                        ),
                        range: NSRange(location: 0, length: 8),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 28, length: 3),
                            mentionAci: acis[3],
                            displayName: "BoldSpoilerGuy",
                        ),
                        range: NSRange(location: 35, length: 15),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 0, length: 51)),
                        ),
                        range: NSRange(location: 0, length: 10),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 51),
                                .italic: NSRange(location: 3, length: 3),
                            ]),
                        ),
                        range: NSRange(location: 10, length: 3),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 0, length: 51)),
                        ),
                        range: NSRange(location: 13, length: 2),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 51),
                                .monospace: NSRange(location: 8, length: 19),
                            ]),
                        ),
                        range: NSRange(location: 15, length: 16),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 51),
                                .monospace: NSRange(location: 8, length: 19),
                                .spoiler: NSRange(location: 24, length: 7),
                            ]),
                        ),
                        range: NSRange(location: 31, length: 3),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 51),
                                .spoiler: NSRange(location: 24, length: 7),
                            ]),
                        ),
                        range: NSRange(location: 34, length: 16),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 0, length: 51)),
                        ),
                        range: NSRange(location: 50, length: 20),
                    ),
                ],
            ),
        )
    }

    func testHydration_multipleMentions_RTL() {
        runHydrationTest(
            input: .init(
                text: "שלום @. שלום @.",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 5, length: 1)),
                        NSRangedValue(acis[1], range: NSRange(location: 13, length: 1)),
                    ],
                    styles: [],
                ),
            ),
            names: [
                acis[0]: "לוק",
                acis[1]: "ליאה",
            ],
            output: .init(
                hydratedText: "שלום לוק@. שלום ליאה@.",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 5, length: 1),
                            mentionAci: acis[0],
                            displayName: "לוק",
                        ),
                        range: NSRange(location: 5, length: 4),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 13, length: 1),
                            mentionAci: acis[1],
                            displayName: "ליאה",
                        ),
                        range: NSRange(location: 16, length: 5),
                    ),
                ],
                styleAttributes: [],
            ),
            isRTL: true,
        )
    }

    func testHydration_styleAndMention_RTL() {
        runHydrationTest(
            input: .init(
                text: "השתמש בכוח, @",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 12, length: 1)),
                    ],
                    styles: [
                        .init(.italic, range: NSRange(location: 5, length: 3)),
                    ],
                ),
            ),
            names: [acis[0]: "לוק"],
            output: .init(
                hydratedText: "השתמש בכוח, לוק@",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 12, length: 1),
                            mentionAci: acis[0],
                            displayName: "לוק",
                        ),
                        range: NSRange(location: 12, length: 4),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.italic, mergedRange: NSRange(location: 5, length: 3)),
                        ),
                        range: NSRange(location: 5, length: 3),
                    ),
                ],
            ),
            isRTL: true,
        )

        runHydrationTest(
            input: .init(
                text: "@, השתמש בכוח",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 0, length: 1)),
                    ],
                    styles: [
                        .init(.italic, range: NSRange(location: 5, length: 3)),
                    ],
                ),
            ),
            names: [acis[0]: "לוק"],
            output: .init(
                hydratedText: "לוק@, השתמש בכוח",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 0, length: 1),
                            mentionAci: acis[0],
                            displayName: "לוק",
                        ),
                        range: NSRange(location: 0, length: 4),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.italic, mergedRange: NSRange(location: 5, length: 3)),
                        ),
                        range: NSRange(location: 8, length: 3),
                    ),
                ],
            ),
            isRTL: true,
        )
    }

    func testHydration_overlappingStyleAndMention_RTL() {
        runHydrationTest(
            input: .init(
                text: "השתמש בכוח, @",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 12, length: 1)),
                    ],
                    styles: [
                        .init(.italic, range: NSRange(location: 0, length: 13)),
                    ],
                ),
            ),
            names: [acis[0]: "לוק"],
            output: .init(
                hydratedText: "השתמש בכוח, לוק@",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 12, length: 1),
                            mentionAci: acis[0],
                            displayName: "לוק",
                        ),
                        range: NSRange(location: 12, length: 4),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.italic, mergedRange: NSRange(location: 0, length: 13)),
                        ),
                        range: NSRange(location: 0, length: 16),
                    ),
                ],
            ),
            isRTL: true,
        )

        runHydrationTest(
            input: .init(
                text: "@, השתמש בכוח",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 0, length: 1)),
                    ],
                    styles: [
                        .init(.italic, range: NSRange(location: 0, length: 13)),
                    ],
                ),
            ),
            names: [acis[0]: "לוק"],
            output: .init(
                hydratedText: "לוק@, השתמש בכוח",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 0, length: 1),
                            mentionAci: acis[0],
                            displayName: "לוק",
                        ),
                        range: NSRange(location: 0, length: 4),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.italic, mergedRange: NSRange(location: 0, length: 13)),
                        ),
                        range: NSRange(location: 0, length: 16),
                    ),
                ],
            ),
            isRTL: true,
        )
    }

    func testHydration_partlyOverlappingStyleAndMention_RTL() {
        runHydrationTest(
            input: .init(
                text: "השתמש בכוח, @@@",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 12, length: 3)),
                    ],
                    styles: [
                        .init(.italic, range: NSRange(location: 5, length: 8)),
                    ],
                ),
            ),
            names: [acis[0]: "לוק"],
            output: .init(
                hydratedText: "השתמש בכוח, לוק@",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 12, length: 3),
                            mentionAci: acis[0],
                            displayName: "לוק",
                        ),
                        range: NSRange(location: 12, length: 4),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.italic, mergedRange: NSRange(location: 5, length: 10)),
                        ),
                        range: NSRange(location: 5, length: 11),
                    ),
                ],
            ),
            isRTL: true,
        )
        runHydrationTest(
            input: .init(
                text: "@@@, השתמש בכוח",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 0, length: 3)),
                    ],
                    styles: [
                        .init(.italic, range: NSRange(location: 1, length: 8)),
                    ],
                ),
            ),
            names: [acis[0]: "לוק"],
            output: .init(
                hydratedText: "לוק@, השתמש בכוח",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 0, length: 3),
                            mentionAci: acis[0],
                            displayName: "לוק",
                        ),
                        range: NSRange(location: 0, length: 4),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.italic, mergedRange: NSRange(location: 0, length: 9)),
                        ),
                        range: NSRange(location: 0, length: 10),
                    ),
                ],
            ),
            isRTL: true,
        )
    }

    func testHydration_multipleMentions_accents() {
        runHydrationTest(
            input: .init(
                text: "@@@ engaña a @@@",
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 0, length: 3)),
                        NSRangedValue(acis[1], range: NSRange(location: 13, length: 3)),
                    ],
                    styles: [
                        .init(.bold, range: NSRange(location: 1, length: 9)),
                        .init(.italic, range: NSRange(location: 4, length: 6)),
                        .init(.monospace, range: NSRange(location: 11, length: 3)),
                    ],
                ),
            ),
            names: [
                acis[0]: "José",
                acis[1]: "María",
            ],
            output: .init(
                hydratedText: "@José engaña a @María",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 0, length: 3),
                            mentionAci: acis[0],
                            displayName: "José",
                        ),
                        range: NSRange(location: 0, length: 5),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 13, length: 3),
                            mentionAci: acis[1],
                            displayName: "María",
                        ),
                        range: NSRange(location: 15, length: 6),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 0, length: 10)),
                        ),
                        range: NSRange(location: 0, length: 6),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 10),
                                .italic: NSRange(location: 4, length: 6),
                            ]),
                        ),
                        range: NSRange(location: 6, length: 6),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.monospace, mergedRange: NSRange(location: 11, length: 5)),
                        ),
                        range: NSRange(location: 13, length: 8),
                    ),
                ],
            ),
        )
    }

    func testHydration_multipleMentions_emoji() {
        let firstMention = "@@@ "
        let firstMentionHydrated = "@Luke "

        let firstEmojiLocation = (firstMention as NSString).length
        let firstEmojiLocationHydrated = (firstMentionHydrated as NSString).length
        let firstEmojis = "🤗👨‍👨‍👧‍👦"
        let firstEmojiLength = (firstEmojis as NSString).length

        let middleWordLocation = firstEmojiLocation + firstEmojiLength
        let middleWordLocationHydrated = firstEmojiLocationHydrated + firstEmojiLength
        let middleWord = "hello"

        let secondEmojiLocation = middleWordLocation + (middleWord as NSString).length
        let secondEmojiLocationHydrated = middleWordLocationHydrated + (middleWord as NSString).length
        let secondEmojis = "👩‍❤️‍👨🌗"
        let secondEmojiLength = (secondEmojis as NSString).length

        let secondMentionLocation = secondEmojiLocation + secondEmojiLength
        let secondMentionLocationHydrated = secondEmojiLocationHydrated + secondEmojiLength
        let secondMention = " @@@"

        runHydrationTest(
            input: .init(
                text: firstMention + firstEmojis + middleWord + secondEmojis + secondMention,
                ranges: .init(
                    mentions: [
                        NSRangedValue(acis[0], range: NSRange(location: 0, length: 3)),
                        NSRangedValue(acis[1], range: NSRange(location: secondMentionLocation + 1, length: 3)),
                    ],
                    styles: [
                        .init(.bold, range: NSRange(location: 1, length: 3 + firstEmojiLength + 5)),
                        .init(.italic, range: NSRange(location: firstEmojiLocation, length: firstEmojiLength + 5 + secondEmojiLength)),
                        .init(.monospace, range: NSRange(location: middleWordLocation, length: 5 + secondEmojiLength + 2)),
                    ],
                ),
            ),
            names: [
                acis[0]: "Luke",
                acis[1]: "Leia",
            ],
            output: .init(
                hydratedText: "@Luke 🤗👨‍👨‍👧‍👦hello👩‍❤️‍👨🌗 @Leia",
                mentionAttributes: [
                    .init(
                        .fromOriginalRange(
                            NSRange(location: 0, length: 3),
                            mentionAci: acis[0],
                            displayName: "Luke",
                        ),
                        range: NSRange(location: 0, length: 5),
                    ),
                    .init(
                        .fromOriginalRange(
                            NSRange(location: secondMentionLocation + 1, length: 3),
                            mentionAci: acis[1],
                            displayName: "Leia",
                        ),
                        range: NSRange(location: secondMentionLocation + 3, length: 5),
                    ),
                ],
                styleAttributes: [
                    .init(
                        .fromCollapsedStyle(
                            .init(.bold, mergedRange: NSRange(location: 0, length: 4 + firstEmojiLength + 5)),
                        ),
                        range: NSRange(location: 0, length: 6),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 4 + firstEmojiLength + 5),
                                .italic: NSRange(location: firstEmojiLocation, length: firstEmojiLength + 5 + secondEmojiLength),
                            ]),
                        ),
                        range: NSRange(location: firstEmojiLocationHydrated, length: firstEmojiLength),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .bold: NSRange(location: 0, length: 4 + firstEmojiLength + 5),
                                .italic: NSRange(location: firstEmojiLocation, length: firstEmojiLength + 5 + secondEmojiLength),
                                .monospace: NSRange(location: middleWordLocation, length: 5 + secondEmojiLength + 4),
                            ]),
                        ),
                        range: NSRange(location: middleWordLocationHydrated, length: 5),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init([
                                .italic: NSRange(location: firstEmojiLocation, length: firstEmojiLength + 5 + secondEmojiLength),
                                .monospace: NSRange(location: middleWordLocation, length: 5 + secondEmojiLength + 4),
                            ]),
                        ),
                        range: NSRange(location: secondEmojiLocationHydrated, length: secondEmojiLength),
                    ),
                    .init(
                        .fromCollapsedStyle(
                            .init(.monospace, mergedRange: NSRange(location: middleWordLocation, length: 5 + secondEmojiLength + 4)),
                        ),
                        range: NSRange(location: secondMentionLocationHydrated, length: 6),
                    ),
                ],
            ),
        )
    }

    // MARK: - Helpers

    private func runHydrationTest(
        input: MessageBody,
        names: [Aci: String],
        output: HydratedMessageBody,
        isRTL: Bool = false,
        file: StaticString = #filePath,
        line: UInt = #line,
    ) {
        let hydrated = input.hydrating(
            mentionHydrator: { aci in
                if let displayName = names[aci] {
                    return .hydrate(displayName)
                } else {
                    return .preserveMention
                }
            },
            isRTL: isRTL,
        )
        XCTAssertEqual(
            output,
            hydrated,
            file: file,
            line: line,
        )
    }
}

struct MessageBodyTest2 {
    static let someZalgo = "x\u{338}\u{306}\u{344}\u{31b}\u{306}\u{33f}\u{344}\u{31a}\u{305}\u{33d}\u{346}\u{35d}\u{344}\u{33f}\u{314}\u{34c}\u{319}\u{31d}\u{322}\u{348}\u{348}\u{316}\u{327}\u{333}\u{317}\u{330}"

    struct TestMessageBody {
        var text: String
        var mentions: [Range<Int>]
        var styles: [Range<Int>]

        func asMessageBody(aci: Aci) -> MessageBody {
            return MessageBody(
                text: self.text,
                ranges: MessageBodyRanges(
                    mentions: self.mentions.map {
                        return NSRangedValue(aci, range: NSRange(location: $0.lowerBound, length: $0.count))
                    },
                    styles: self.styles.map {
                        return NSRangedValue(.bold, range: NSRange(location: $0.lowerBound, length: $0.count))
                    },
                ),
            )
        }
    }

    @Test(arguments: [
        (
            TestMessageBody(
                text: "  Hello @@ and @@.  ",
                mentions: [],
                styles: [],
            ),
            TestMessageBody(
                text: "Hello @@ and @@.",
                mentions: [],
                styles: [],
            ),
        ),
        (
            TestMessageBody(
                text: "  Hey @@ and @@.  ",
                mentions: [6..<8, 13..<15],
                styles: [2..<5],
            ),
            TestMessageBody(
                text: "Hey @@ and @@.",
                mentions: [4..<6, 11..<13],
                styles: [0..<3],
            ),
        ),
        (
            TestMessageBody(
                text: "  @ and @  ",
                mentions: [1..<3, 8..<10],
                styles: [1..<3, 8..<10],
            ),
            TestMessageBody(
                text: "@ and @",
                mentions: [0..<1, 6..<7],
                styles: [0..<1, 6..<7],
            ),
        ),
        (
            TestMessageBody(
                text: "  @ and \(someZalgo) and @  ",
                mentions: [1..<3, (13 + someZalgo.utf16.count)..<(15 + someZalgo.utf16.count)],
                styles: [1..<3, (13 + someZalgo.utf16.count)..<(15 + someZalgo.utf16.count)],
            ),
            TestMessageBody(
                text: "@ and \u{fffd} and @",
                // TODO: Enable these expectations once we're able to properly filter them.
                // mentions: [0..<1, (11 + someZalgo.utf16.count)..<(12 + someZalgo.utf16.count)],
                // styles: [0..<1, (11 + someZalgo.utf16.count)..<(12 + someZalgo.utf16.count)],
                mentions: [],
                styles: [],
            ),
        ),
    ])
    func testFilterForDisplay(testCase: (inputValue: TestMessageBody, expectedValue: TestMessageBody)) {
        let aci = Aci.randomForTesting()
        let inputValue = testCase.inputValue.asMessageBody(aci: aci)
        let outputValue = inputValue.filterStringForDisplay()
        let expectedValue = testCase.expectedValue.asMessageBody(aci: aci)
        #expect(outputValue.text == expectedValue.text)
        #expect(outputValue.ranges.orderedMentions == expectedValue.ranges.orderedMentions)
        // TODO: Filter original styles so that we can also compare the values.
        #expect(outputValue.ranges.collapsedStyles.map(\.range) == expectedValue.ranges.collapsedStyles.map(\.range))
    }

    @Test(arguments: [
        (
            TestMessageBody(
                text: "Welcome! How are you? I'm good.",
                mentions: [17..<20],
                styles: [17..<20],
            ),
            "How are you?",
            [4..<7],
            TestMessageBody(
                text: "How are you?",
                mentions: [8..<11],
                styles: [4..<7, 8..<11],
            ),
        ),
    ])
    func testMergeStylesIntoFirstMatchOfSubstring(testCase: (inputValue: TestMessageBody, searchValue: String, newStyles: [Range<Int>], expectedValue: TestMessageBody)) {
        let aci = Aci.randomForTesting()
        let inputValue = testCase.inputValue.asMessageBody(aci: aci)
        let outputValue = inputValue.mergeIntoFirstMatchOfStyledSubstring(
            testCase.searchValue,
            styles: testCase.newStyles.map {
                return NSRangedValue(.bold, range: NSRange(location: $0.lowerBound, length: $0.count))
            },
        )
        let expectedValue = testCase.expectedValue.asMessageBody(aci: aci)
        #expect(outputValue.text == expectedValue.text)
        #expect(outputValue.ranges.orderedMentions == expectedValue.ranges.orderedMentions)
        #expect(outputValue.ranges.collapsedStyles == expectedValue.ranges.collapsedStyles)
        #expect(outputValue == expectedValue)
    }
}
