//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

final class MessageBodyTests: XCTestCase {

    typealias Style = MessageBodyRanges.Style

    // MARK: - Style Collapsing

    func testStyleCollapsing_sequential() {
        // They don't overlap but they're out of order.
        let styles: [(NSRange, Style)] = [
            (NSRange(location: 11, length: 5), .strikethrough),
            (NSRange(location: 0, length: 1), .bold),
            (NSRange(location: 1, length: 2), .italic),
            (NSRange(location: 120, length: 10), .bold.union(.italic)),
            (NSRange(location: 3, length: 3), .monospace),
            (NSRange(location: 6, length: 4), .spoiler)
        ]
        let expectedOutput: [(NSRange, Style)] = [
            (NSRange(location: 0, length: 1), .bold),
            (NSRange(location: 1, length: 2), .italic),
            (NSRange(location: 3, length: 3), .monospace),
            (NSRange(location: 6, length: 4), .spoiler),
            (NSRange(location: 11, length: 5), .strikethrough),
            (NSRange(location: 120, length: 10), .bold.union(.italic))
        ]
        let output = MessageBodyRanges(mentions: [:], styles: styles).styles
        assertStylesEqual(expectedOutput, output)
    }

    func testStyleCollapsing_overlap() {
        var styles: [(NSRange, Style)] = [
            (NSRange(location: 0, length: 3), .bold),
            (NSRange(location: 1, length: 3), .italic)
        ]
        var expectedOutput: [(NSRange, Style)] = [
            (NSRange(location: 0, length: 1), .bold),
            (NSRange(location: 1, length: 2), .bold.union(.italic)),
            (NSRange(location: 3, length: 1), .italic)
        ]
        var output = MessageBodyRanges(mentions: [:], styles: styles).styles
        assertStylesEqual(expectedOutput, output)

        styles = [
            (NSRange(location: 0, length: 5), .bold),
            (NSRange(location: 1, length: 3), .italic)
        ]
        expectedOutput = [
            (NSRange(location: 0, length: 1), .bold),
            (NSRange(location: 1, length: 3), .bold.union(.italic)),
            (NSRange(location: 4, length: 1), .bold)
        ]
        output = MessageBodyRanges(mentions: [:], styles: styles).styles
        assertStylesEqual(expectedOutput, output)

        styles = [
            (NSRange(location: 0, length: 5), .bold),
            (NSRange(location: 4, length: 5), .italic),
            (NSRange(location: 8, length: 5), .spoiler)
        ]
        expectedOutput = [
            (NSRange(location: 0, length: 4), .bold),
            (NSRange(location: 4, length: 1), .bold.union(.italic)),
            (NSRange(location: 5, length: 3), .italic),
            (NSRange(location: 8, length: 1), .italic.union(.spoiler)),
            (NSRange(location: 9, length: 4), .spoiler)
        ]
        output = MessageBodyRanges(mentions: [:], styles: styles).styles
        assertStylesEqual(expectedOutput, output)

        styles = [
            (NSRange(location: 0, length: 6), .bold),
            (NSRange(location: 1, length: 6), .italic),
            (NSRange(location: 2, length: 6), .spoiler),
            (NSRange(location: 3, length: 6), .strikethrough),
            (NSRange(location: 4, length: 6), .monospace)
        ]
        expectedOutput = [
            (NSRange(location: 0, length: 1), .bold),
            (NSRange(location: 1, length: 1), .bold.union(.italic)),
            (NSRange(location: 2, length: 1), .bold.union(.italic).union(.spoiler)),
            (NSRange(location: 3, length: 1), .bold.union(.italic).union(.spoiler).union(.strikethrough)),
            (NSRange(location: 4, length: 2), .bold.union(.italic).union(.spoiler).union(.strikethrough).union(.monospace)),
            (NSRange(location: 6, length: 1), .italic.union(.spoiler).union(.strikethrough).union(.monospace)),
            (NSRange(location: 7, length: 1), .spoiler.union(.strikethrough).union(.monospace)),
            (NSRange(location: 8, length: 1), .strikethrough.union(.monospace)),
            (NSRange(location: 9, length: 1), .monospace)
        ]
        output = MessageBodyRanges(mentions: [:], styles: styles).styles
        assertStylesEqual(expectedOutput, output)
    }

    // MARK: - Hydration

    let uuids = (0...5).map { _ in UUID() }

    func testHydration_noMentions() {
        runHydrationTest(
            input: .init(
                text: "Hello",
                ranges: .init(
                    mentions: [:],
                    styles: []
                )
            ),
            names: [:],
            output: .init(
                text: "Hello",
                ranges: .init(
                    mentions: [:],
                    styles: []
                )
            )
        )
    }

    func testHydration_singleMention() {
        runHydrationTest(
            input: .init(
                text: "Hello @",
                ranges: .init(
                    mentions: [
                        NSRange(location: 6, length: 1): uuids[0]
                    ],
                    styles: []
                )
            ),
            names: [uuids[0]: "Luke"],
            output: .init(
                text: "Hello @Luke",
                ranges: .init(
                    mentions: [:],
                    styles: []
                )
            )
        )
    }

    func testHydration_multipleMentions() {
        runHydrationTest(
            input: .init(
                text: "Hello @ and @, how is @?",
                ranges: .init(
                    mentions: [
                        NSRange(location: 6, length: 1): uuids[0],
                        NSRange(location: 12, length: 1): uuids[1],
                        NSRange(location: 22, length: 1): uuids[2]
                    ],
                    styles: []
                )
            ),
            names: [
                uuids[0]: "Luke",
                uuids[1]: "Leia",
                uuids[2]: "Han"
            ],
            output: .init(
                text: "Hello @Luke and @Leia, how is @Han?",
                ranges: .init(
                    mentions: [:],
                    styles: []
                )
            )
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
                        NSRange(location: 6, length: 5): uuids[0],
                        NSRange(location: 16, length: 2): uuids[1],
                        NSRange(location: 27, length: 0): uuids[2]
                    ],
                    styles: []
                )
            ),
            names: [
                uuids[0]: "Luke",
                uuids[1]: "Leia",
                uuids[2]: "Han"
            ],
            output: .init(
                text: "Hello @Luke and @Leia, how is @Han?",
                ranges: .init(
                    mentions: [:],
                    styles: []
                )
            )
        )
    }

    func testHydration_notAllHydrated() {
        runHydrationTest(
            input: .init(
                text: "Hello @ and @, how is @?",
                ranges: .init(
                    mentions: [
                        NSRange(location: 6, length: 1): uuids[0],
                        NSRange(location: 12, length: 1): uuids[1],
                        NSRange(location: 22, length: 1): uuids[2]
                    ],
                    styles: []
                )
            ),
            names: [
                uuids[0]: "Luke",
                uuids[2]: "Han"
            ],
            output: .init(
                text: "Hello @Luke and @, how is @Han?",
                ranges: .init(
                    mentions: [
                        NSRange(location: 16, length: 1): uuids[1]
                    ],
                    styles: []
                )
            )
        )
    }

    func testHydration_justStyles() {
        runHydrationTest(
            input: .init(
                text: "This is bold, italic, and mono",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 8, length: 4), .bold),
                        (NSRange(location: 14, length: 6), .italic),
                        (NSRange(location: 26, length: 4), .monospace)
                    ]
                )
            ),
            names: [:],
            output: .init(
                text: "This is bold, italic, and mono",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 8, length: 4), .bold),
                        (NSRange(location: 14, length: 6), .italic),
                        (NSRange(location: 26, length: 4), .monospace)
                    ]
                )
            )
        )
    }

    func testHydration_stylesAndTrailingMention() {
        runHydrationTest(
            input: .init(
                text: "This is bold, italic, and mono, @.",
                ranges: .init(
                    mentions: [
                        NSRange(location: 32, length: 1): uuids[0]
                    ],
                    styles: [
                        (NSRange(location: 8, length: 4), .bold),
                        (NSRange(location: 14, length: 6), .italic),
                        (NSRange(location: 26, length: 4), .monospace)
                    ]
                )
            ),
            names: [uuids[0]: "Luke"],
            output: .init(
                text: "This is bold, italic, and mono, @Luke.",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 8, length: 4), .bold),
                        (NSRange(location: 14, length: 6), .italic),
                        (NSRange(location: 26, length: 4), .monospace)
                    ]
                )
            )
        )
    }

    func testHydration_stylesAndLeadingMention() {
        runHydrationTest(
            input: .init(
                text: "@, this is bold, italic, and mono",
                ranges: .init(
                    mentions: [
                        NSRange(location: 0, length: 1): uuids[0]
                    ],
                    styles: [
                        (NSRange(location: 11, length: 4), .bold),
                        (NSRange(location: 17, length: 6), .italic),
                        (NSRange(location: 29, length: 4), .monospace)
                    ]
                )
            ),
            names: [uuids[0]: "Luke"],
            output: .init(
                text: "@Luke, this is bold, italic, and mono",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 15, length: 4), .bold),
                        (NSRange(location: 21, length: 6), .italic),
                        (NSRange(location: 33, length: 4), .monospace)
                    ]
                )
            )
        )
    }

    func testHydration_overlappingStyleAndMention() {
        runHydrationTest(
            input: .init(
                text: "Use the force, @",
                ranges: .init(
                    mentions: [
                        NSRange(location: 15, length: 1): uuids[0]
                    ],
                    styles: [
                        (NSRange(location: 0, length: 16), .italic)
                    ]
                )
            ),
            names: [uuids[0]: "Luke"],
            output: .init(
                text: "Use the force, @Luke",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 0, length: 20), .italic)
                    ]
                )
            )
        )
    }

    func testHydration_overlappingStylesAndMentions() {
        runHydrationTest(
            input: .init(
                text: "@, @@@, @@@@@@@@@@@@@@@ and @@@ are stylish people.",
                ranges: .init(
                    mentions: [
                        NSRange(location: 0, length: 1): uuids[0],
                        NSRange(location: 3, length: 3): uuids[1],
                        NSRange(location: 8, length: 15): uuids[2],
                        NSRange(location: 28, length: 3): uuids[3]
                    ],
                    styles: [
                        (NSRange(location: 0, length: 51), .bold),
                        (NSRange(location: 4, length: 1), .italic),
                        (NSRange(location: 12, length: 15), .monospace),
                        (NSRange(location: 24, length: 5), .spoiler)
                    ]
                )
            ),
            names: [
                uuids[0]: "BoldGuy",
                uuids[1]: "BoldItalicGuy",
                uuids[2]: "BoldMonoGuy",
                uuids[3]: "BoldSpoilerGuy"
            ],
            output: .init(
                text: "@BoldGuy, @BoldItalicGuy, @BoldMonoGuy and @BoldSpoilerGuy are stylish people.",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 0, length: 78), .bold),
                        (NSRange(location: 10, length: 14), .italic),
                        (NSRange(location: 26, length: 16), .monospace),
                        (NSRange(location: 39, length: 19), .spoiler)
                    ]
                )
            )
        )
    }

    func testHydration_overlappingStylesAndSomeUnhydratedMentions() {
        let foo: MessageBodyRanges = .init(
            mentions: [
                NSRange(location: 10, length: 3): uuids[1],
                NSRange(location: 15, length: 15): uuids[2]
            ],
            styles: [
                (NSRange(location: 0, length: 10), .bold),
                (NSRange(location: 10, length: 3), .bold.union(.italic)),
                (NSRange(location: 13, length: 2), .bold),
                (NSRange(location: 15, length: 16), .bold.union(.monospace)),
                (NSRange(location: 31, length: 3), .bold.union(.monospace).union(.spoiler)),
                (NSRange(location: 34, length: 16), .bold.union(.spoiler)),
                (NSRange(location: 50, length: 20), .bold)
            ]
        )
        runHydrationTest(
            input: .init(
                text: "@, @@@, @@@@@@@@@@@@@@@ and @@@ are stylish people.",
                ranges: .init(
                    mentions: [
                        NSRange(location: 0, length: 1): uuids[0],
                        NSRange(location: 3, length: 3): uuids[1],
                        NSRange(location: 8, length: 15): uuids[2],
                        NSRange(location: 28, length: 3): uuids[3]
                    ],
                    styles: [
                        (NSRange(location: 0, length: 51), .bold),
                        (NSRange(location: 4, length: 1), .italic),
                        (NSRange(location: 12, length: 15), .monospace),
                        (NSRange(location: 24, length: 5), .spoiler)
                    ]
                )
            ),
            names: [
                uuids[0]: "BoldGuy",
                uuids[3]: "BoldSpoilerGuy"
            ],
            output: .init(
                text: "@BoldGuy, @@@, @@@@@@@@@@@@@@@ and @BoldSpoilerGuy are stylish people.",
                ranges: foo
            )
        )
    }

    func testHydration_multipleMentions_RTL() {
        runHydrationTest(
            input: .init(
                text: "שלום @. שלום @.",
                ranges: .init(
                    mentions: [
                        NSRange(location: 5, length: 1): uuids[0],
                        NSRange(location: 13, length: 1): uuids[1]
                    ],
                    styles: []
                )
            ),
            names: [
                uuids[0]: "לוק",
                uuids[1]: "ליאה"
            ],
            output: .init(
                text: "שלום לוק@. שלום ליאה@.",
                ranges: .init(
                    mentions: [:],
                    styles: []
                )
            ),
            isRTL: true
        )
    }

    func testHydration_styleAndMention_RTL() {
        runHydrationTest(
            input: .init(
                text: "השתמש בכוח, @",
                ranges: .init(
                    mentions: [
                        NSRange(location: 12, length: 1): uuids[0]
                    ],
                    styles: [
                        (NSRange(location: 5, length: 3), .italic)
                    ]
                )
            ),
            names: [uuids[0]: "לוק"],
            output: .init(
                text: "השתמש בכוח, לוק@",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 5, length: 3), .italic)
                    ]
                )
            ),
            isRTL: true
        )

        runHydrationTest(
            input: .init(
                text: "@, השתמש בכוח",
                ranges: .init(
                    mentions: [
                        NSRange(location: 0, length: 1): uuids[0]
                    ],
                    styles: [
                        (NSRange(location: 5, length: 3), .italic)
                    ]
                )
            ),
            names: [uuids[0]: "לוק"],
            output: .init(
                text: "לוק@, השתמש בכוח",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 8, length: 3), .italic)
                    ]
                )
            ),
            isRTL: true
        )
    }

    func testHydration_overlappingStyleAndMention_RTL() {
        runHydrationTest(
            input: .init(
                text: "השתמש בכוח, @",
                ranges: .init(
                    mentions: [
                        NSRange(location: 12, length: 1): uuids[0]
                    ],
                    styles: [
                        (NSRange(location: 0, length: 13), .italic)
                    ]
                )
            ),
            names: [uuids[0]: "לוק"],
            output: .init(
                text: "השתמש בכוח, לוק@",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 0, length: 16), .italic)
                    ]
                )
            ),
            isRTL: true
        )

        runHydrationTest(
            input: .init(
                text: "@, השתמש בכוח",
                ranges: .init(
                    mentions: [
                        NSRange(location: 0, length: 1): uuids[0]
                    ],
                    styles: [
                        (NSRange(location: 0, length: 13), .italic)
                    ]
                )
            ),
            names: [uuids[0]: "לוק"],
            output: .init(
                text: "לוק@, השתמש בכוח",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 0, length: 16), .italic)
                    ]
                )
            ),
            isRTL: true
        )
    }

    func testHydration_partlyOverlappingStyleAndMention_RTL() {
        runHydrationTest(
            input: .init(
                text: "השתמש בכוח, @@@",
                ranges: .init(
                    mentions: [
                        NSRange(location: 12, length: 3): uuids[0]
                    ],
                    styles: [
                        (NSRange(location: 5, length: 8), .italic)
                    ]
                )
            ),
            names: [uuids[0]: "לוק"],
            output: .init(
                text: "השתמש בכוח, לוק@",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 5, length: 11), .italic)
                    ]
                )
            ),
            isRTL: true
        )
        runHydrationTest(
            input: .init(
                text: "@@@, השתמש בכוח",
                ranges: .init(
                    mentions: [
                        NSRange(location: 0, length: 3): uuids[0]
                    ],
                    styles: [
                        (NSRange(location: 1, length: 8), .italic)
                    ]
                )
            ),
            names: [uuids[0]: "לוק"],
            output: .init(
                text: "לוק@, השתמש בכוח",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 0, length: 10), .italic)
                    ]
                )
            ),
            isRTL: true
        )
    }

    func testHydration_multipleMentions_accents() {
        runHydrationTest(
            input: .init(
                text: "@@@ engaña a @@@",
                ranges: .init(
                    mentions: [
                        NSRange(location: 0, length: 3): uuids[0],
                        NSRange(location: 13, length: 3): uuids[1]
                    ],
                    styles: [
                        (NSRange(location: 1, length: 9), .bold),
                        (NSRange(location: 4, length: 6), .italic),
                        (NSRange(location: 11, length: 3), .monospace)
                    ]
                )
            ),
            names: [
                uuids[0]: "José",
                uuids[1]: "María"
            ],
            output: .init(
                text: "@José engaña a @María",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 0, length: 12), .bold),
                        (NSRange(location: 6, length: 6), .italic),
                        (NSRange(location: 13, length: 8), .monospace)
                    ]
                )
            )
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
        let secondMention = " @@@"

        runHydrationTest(
            input: .init(
                text: firstMention + firstEmojis + middleWord + secondEmojis + secondMention,
                ranges: .init(
                    mentions: [
                        NSRange(location: 0, length: 3): uuids[0],
                        NSRange(location: secondMentionLocation + 1, length: 3): uuids[1]
                    ],
                    styles: [
                        (NSRange(location: 1, length: 3 + firstEmojiLength + 5), .bold),
                        (NSRange(location: firstEmojiLocation, length: firstEmojiLength + 5 + secondEmojiLength), .italic),
                        (NSRange(location: middleWordLocation, length: 5 + secondEmojiLength + 2), .monospace)
                    ]
                )
            ),
            names: [
                uuids[0]: "Luke",
                uuids[1]: "Leia"
            ],
            output: .init(
                text: "@Luke 🤗👨‍👨‍👧‍👦hello👩‍❤️‍👨🌗 @Leia",
                ranges: .init(
                    mentions: [:],
                    styles: [
                        (NSRange(location: 0, length: 6 + firstEmojiLength + 5), .bold),
                        (NSRange(location: firstEmojiLocationHydrated, length: firstEmojiLength + 5 + secondEmojiLength), .italic),
                        (NSRange(location: middleWordLocationHydrated, length: 5 + secondEmojiLength + 6), .monospace)
                    ]
                )
            )
        )
    }

    func testDeserializeV1() throws {
        let encodedDataBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEBALDB0lJictMTQWODs/QEFEVSRudWxs2A0ODxAREhMUFRYXGBkaGxxfEBBtZW50aW9ucy5yYW5nZS4wXW1lbnRpb25zQ291bnRWJGNsYXNzXxAPbWVudGlvbnMudXVpZC4yXxAQbWVudGlvbnMucmFuZ2UuMV8QEG1lbnRpb25zLnJhbmdlLjJfEA9tZW50aW9ucy51dWlkLjFfEA9tZW50aW9ucy51dWlkLjCAAhADgA+ADoAIgAuACoAG1B4fIA8hIiMkXxASTlMucmFuZ2V2YWwubGVuZ3RoXxAUTlMucmFuZ2V2YWwubG9jYXRpb25aTlMuc3BlY2lhbIADgAQQBIAFEAEQANIoKSorWiRjbGFzc25hbWVYJGNsYXNzZXNXTlNWYWx1ZaIqLFhOU09iamVjdNIuDy8wXE5TLnV1aWRieXRlc08QEDRv6bLICE9hkgPhkjjFju2AB9IoKTIzVk5TVVVJRKIyLNQeHyAPITYjJIADgAmABdIuDzkwTxAQ4Vl38Lg2TAKkc40D+J1IxoAH1B4fIA88PSMkgAyADYAFEAcQBdIuD0IwTxAQhC0Fz6D1SSiY4rfoa5AXlIAH0igpRUZfECJTaWduYWxTZXJ2aWNlS2l0Lk1lc3NhZ2VCb2R5UmFuZ2VzokcsXxAiU2lnbmFsU2VydmljZUtpdC5NZXNzYWdlQm9keVJhbmdlcwAIABEAGgAkACkAMgA3AEkATABRAFMAZgBsAH0AkACeAKUAtwDKAN0A7wEBAQMBBQEHAQkBCwENAQ8BEQEaAS8BRgFRAVMBVQFXAVkBWwFdAWIBbQF2AX4BgQGKAY8BnAGvAbEBtgG9AcAByQHLAc0BzwHUAecB6QHyAfQB9gH4AfoB/AIBAhQCFgIbAkACQwAAAAAAAAIBAAAAAAAAAEgAAAAAAAAAAAAAAAAAAAJo"
        let expectedResult = MessageBodyRanges(
            mentions: [
                NSRange(location: 0, length: 1): UUID(uuidString: "346FE9B2-C808-4F61-9203-E19238C58EED")!,
                NSRange(location: 3, length: 1): UUID(uuidString: "E15977F0-B836-4C02-A473-8D03F89D48C6")!,
                NSRange(location: 5, length: 7): UUID(uuidString: "842D05CF-A0F5-4928-98E2-B7E86B901794")!
            ],
            styles: []
        )

        let data = Data(base64Encoded: encodedDataBase64)!
        let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: MessageBodyRanges.self,
            from: data
        )
        XCTAssertEqual(expectedResult, decoded)
    }

    func testDeserializeV2() throws {
        let encodedDataBase64 = "YnBsaXN0MDDUAQIDBAUGBwpYJHZlcnNpb25ZJGFyY2hpdmVyVCR0b3BYJG9iamVjdHMSAAGGoF8QD05TS2V5ZWRBcmNoaXZlctEICVRyb290gAGvEBoLDDc+P0BGSk0iUVJVJVlcYDBkaCZscCd0dVUkbnVsbN8QFQ0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Nl5zdHlsZXMuc3R5bGUuMF5zdHlsZXMucmFuZ2UuNV5zdHlsZXMucmFuZ2UuMl1tZW50aW9uc0NvdW50XnN0eWxlcy5zdHlsZS41W3N0eWxlc0NvdW50ViRjbGFzc18QEG1lbnRpb25zLnJhbmdlLjFec3R5bGVzLnN0eWxlLjJfEA9tZW50aW9ucy51dWlkLjBec3R5bGVzLnJhbmdlLjRec3R5bGVzLnJhbmdlLjFec3R5bGVzLnN0eWxlLjRfEA9tZW50aW9ucy51dWlkLjFec3R5bGVzLnN0eWxlLjFfEBBtZW50aW9ucy5yYW5nZS4yXnN0eWxlcy5yYW5nZS4zXxAQbWVudGlvbnMucmFuZ2UuMF8QD21lbnRpb25zLnV1aWQuMl5zdHlsZXMucmFuZ2UuMF5zdHlsZXMuc3R5bGUuMxABgBaAEhADEAQQBoAZgAgQGoAGgBWAEBAUgAsQAoAMgBOAAoAOgA8QEtQ4OToTOzwmPV8QEk5TLnJhbmdldmFsLmxlbmd0aF8QFE5TLnJhbmdldmFsLmxvY2F0aW9uWk5TLnNwZWNpYWyAA4AEgAUQBxAF0kFCQ0RaJGNsYXNzbmFtZVgkY2xhc3Nlc1dOU1ZhbHVlokNFWE5TT2JqZWN00kcTSElcTlMudXVpZGJ5dGVzTxAQrp7/WnBvRr6+oaToYla4x4AH0kFCS0xWTlNVVUlEoktF1Dg5OhNOTyY9gAmACoAFEADSRxNTSU8QEK9AYjOzRE5Ame2tCAuLGs+AB9Q4OToTTlcmPYAJgA2ABdJHE1pJTxAQAXRH4MWkRWykwR7H+RrAcIAH1Dg5OhNOTyY9gAmACoAF1Dg5OhNOYiY9gAmAEYAF1Dg5OhNOVyY9gAmADYAF1Dg5OhNOaiY9gAmAFIAF1Dg5OhM7PCY9gAOABIAF1Dg5OhNxciY9gBeAGIAFEAzSQUJ2d18QIlNpZ25hbFNlcnZpY2VLaXQuTWVzc2FnZUJvZHlSYW5nZXOieEVfECJTaWduYWxTZXJ2aWNlS2l0Lk1lc3NhZ2VCb2R5UmFuZ2VzAAgAEQAaACQAKQAyADcASQBMAFEAUwBwAHYAowCyAMEA0ADeAO0A+QEAARMBIgE0AUMBUgFhAXMBggGVAaQBtwHJAdgB5wHpAesB7QHvAfEB8wH1AfcB+QH7Af0B/wIBAgMCBQIHAgkCCwINAg8CEQIaAi8CRgJRAlMCVQJXAlkCWwJgAmsCdAJ8An8CiAKNApoCrQKvArQCuwK+AscCyQLLAs0CzwLUAucC6QLyAvQC9gL4Av0DEAMSAxsDHQMfAyEDKgMsAy4DMAM5AzsDPQM/A0gDSgNMA04DVwNZA1sDXQNmA2gDagNsA24DcwOYA5sAAAAAAAACAQAAAAAAAAB5AAAAAAAAAAAAAAAAAAADwA=="

        let expectedResult = MessageBodyRanges(
            mentions: [
                NSRange(location: 0, length: 1): UUID(uuidString: "AF406233-B344-4E40-99ED-AD080B8B1ACF")!,
                NSRange(location: 3, length: 1): UUID(uuidString: "017447E0-C5A4-456C-A4C1-1EC7F91AC070")!,
                NSRange(location: 5, length: 7): UUID(uuidString: "AE9EFF5A-706F-46BE-BEA1-A4E86256B8C7")!
            ],
            styles: [
                (NSRange(location: 0, length: 1), .bold),
                (NSRange(location: 2, length: 1), .italic),
                (NSRange(location: 3, length: 1), .italic.union(.monospace).union(.strikethrough)),
                (NSRange(location: 4, length: 1), .italic.union(.monospace)),
                (NSRange(location: 5, length: 2), .monospace),
                (NSRange(location: 8, length: 10), .spoiler)
            ]
        )

        let data = Data(base64Encoded: encodedDataBase64)!
        let decoded = try NSKeyedUnarchiver.unarchivedObject(
            ofClass: MessageBodyRanges.self,
            from: data
        )
        XCTAssertEqual(expectedResult, decoded)
    }

    // MARK: - Helpers

    private func assertStylesEqual(
        _ lhs: [(NSRange, Style)],
        _ rhs: [(NSRange, Style)],
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(lhs.count, rhs.count, file: file, line: line)
        for i in 0..<lhs.count {
            XCTAssertEqual(lhs[i].0, rhs[i].0)
            XCTAssertEqual(lhs[i].1, rhs[i].1)
        }
    }

    private func runHydrationTest(
        input: MessageBody,
        names: [UUID: String],
        output: MessageBody,
        isRTL: Bool = false,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let hydrated = input.hydratingMentions(
            hydrator: { uuid in
                if let displayName = names[uuid] {
                    return .hydrate(displayName: displayName)
                } else {
                    return .preserveMention
                }
            },
            isRTL: isRTL
        )
        XCTAssertEqual(
            output,
            hydrated,
            file: file,
            line: line
        )
    }
}
