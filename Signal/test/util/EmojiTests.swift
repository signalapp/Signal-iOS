//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal
@testable import SignalServiceKit

class EmojiTests: SignalBaseTest {

    override func setUp() {
        super.setUp()
    }

    func testSimpleEmojiCases() {
        XCTAssertFalse("".isSingleEmoji)
        XCTAssertTrue("😃".isSingleEmoji)
        XCTAssertFalse("😃😃".isSingleEmoji)
        XCTAssertFalse("a".isSingleEmoji)
        XCTAssertFalse(" 😃".isSingleEmoji)
        XCTAssertFalse("😃 ".isSingleEmoji)
        XCTAssertTrue("👨‍👩‍👧‍👦".isSingleEmoji)

        XCTAssertFalse("".isSingleEmojiUsingEmojiWithSkinTones)
        XCTAssertTrue("😃".isSingleEmojiUsingEmojiWithSkinTones)
        XCTAssertFalse("😃😃".isSingleEmojiUsingEmojiWithSkinTones)
        XCTAssertFalse("a".isSingleEmojiUsingEmojiWithSkinTones)
        XCTAssertFalse(" 😃".isSingleEmojiUsingEmojiWithSkinTones)
        XCTAssertFalse("😃 ".isSingleEmojiUsingEmojiWithSkinTones)
        XCTAssertTrue("👨‍👩‍👧‍👦".isSingleEmojiUsingEmojiWithSkinTones)

        XCTAssertFalse("".isSingleEmojiUsingCoreText)
        XCTAssertTrue("😃".isSingleEmojiUsingCoreText)
        XCTAssertFalse("😃😃".isSingleEmojiUsingCoreText)
        XCTAssertFalse("a".isSingleEmojiUsingCoreText)
        XCTAssertFalse(" 😃".isSingleEmojiUsingCoreText)
        XCTAssertFalse("😃 ".isSingleEmojiUsingCoreText)
        XCTAssertTrue("👨‍👩‍👧‍👦".isSingleEmojiUsingCoreText)

        XCTAssertFalse("".isSingleEmojiUsingCount)
        XCTAssertTrue("😃".isSingleEmojiUsingCount)
        XCTAssertFalse("😃😃".isSingleEmojiUsingCount)
        XCTAssertFalse("a".isSingleEmojiUsingCount)
        XCTAssertFalse(" 😃".isSingleEmojiUsingCount)
        XCTAssertFalse("😃 ".isSingleEmojiUsingCount)
        XCTAssertTrue("👨‍👩‍👧‍👦".isSingleEmojiUsingCount)
    }

    func testEmojiCounts() {
        XCTAssertEqual("".count, 0)
        XCTAssertEqual("😃".count, 1)
        XCTAssertEqual("😃😃".count, 2)
        XCTAssertEqual("a".count, 1)
        XCTAssertEqual(" 😃".count, 2)
        XCTAssertEqual("😃 ".count, 2)
        XCTAssertEqual("👨‍👩‍👧‍👦".count, 1)

        XCTAssertEqual("".count, 0)
        XCTAssertEqual("😃".count, 1)
        XCTAssertEqual("😃😃".count, 2)
        XCTAssertEqual("a".count, 1)
        XCTAssertEqual(" 😃".count, 2)
        XCTAssertEqual("😃 ".count, 2)
        XCTAssertEqual("👨‍👩‍👧‍👦".count, 1)
    }

    func testFancyEmojiCases() {
        do {
            // Valid emoji with skin tones.
            let fancyEmoji = EmojiWithSkinTones(baseEmoji: .manWithGuaPiMao, skinTones: [.mediumDark]).rawValue
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            // Invalid emoji with skin tones.
            let fancyEmoji = EmojiWithSkinTones(baseEmoji: .blueberries, skinTones: [.mediumDark]).rawValue
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            // Black Diamond Suit Emoji
            let fancyEmoji = "\u{2666}" // ♦
            // EmojiWithSkinTones doesn't recognize this as an emoji...
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            // But CoreText+EmojiRanges does...
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            // So does count+EmojiRanges does...
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            // Black Diamond Suit Emoji
            // Adding 'Variation Selector-16':
            let fancyEmoji = "\u{2666}\u{FE0F}" // ♦️
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            // Thumbs up sign:
            let fancyEmoji = "\u{1F44D}" // 👍
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            // Thumbs up sign:
            // Adding 'Emoji Modifier Fitzpatrick Type-4':
            let fancyEmoji = "\u{1F44D}\u{1F3FD}" // 👍🏽
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            // Man, Woman, Girl, Boy
            let fancyEmoji = "\u{1F468}\u{1F469}\u{1F467}\u{1F466}" // 👨👩👧👦
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingCoreText)
            XCTAssertEqual(fancyEmoji.count, 4)
        }

        do {
            // Man, Woman, Girl, Boy
            // Adding 'Zero Width Joiner' between each
            let fancyEmoji = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}" // 👨‍👩‍👧‍👦
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            let fancyEmoji = "🏳"
            // EmojiWithSkinTones doesn't recognize this as an emoji...
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            // But CoreText+EmojiRanges does...
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            // So does count+EmojiRanges does...
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            let fancyEmoji = "🌈️"
            // EmojiWithSkinTones doesn't recognize this as an emoji...
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            // But CoreText+EmojiRanges does...
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            // So does count+EmojiRanges does...
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            // Not an emoji.
            let fancyEmoji = "a"
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingCoreText)
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            // Empty string.
            let fancyEmoji = ""
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingCoreText)
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 0)
        }

        do {
            // Not an emoji; just a isolated modifier.
            // 'Emoji Modifier Fitzpatrick Type-4':
            let fancyEmoji = "\u{1F3FD}"
            // But this is considered an emoji by all measures.
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }

        do {
            // Not an emoji; just a isolated modifier.
            // 'Variation Selector-16':
            let fancyEmoji = "\u{FE0F}"
            // EmojiWithSkinTones doesn't recognize this as an emoji...
            XCTAssertFalse(fancyEmoji.isSingleEmojiUsingEmojiWithSkinTones)
            // But CoreText+EmojiRanges does...
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCoreText)
            // So does count+EmojiRanges does...
            XCTAssertTrue(fancyEmoji.isSingleEmojiUsingCount)
            XCTAssertEqual(fancyEmoji.count, 1)
        }
    }

    func testMoreEmojiCases() {
        let moreEmojis = [
            "😍",
            "👩🏽",
            "👨‍🦰",
            "👨🏿‍🦰",
            "👨‍🦱",
            "👨🏿‍🦱",
            "🦹🏿‍♂️",
            "👾",
            "🙇",
            "💁",
            "🙅",
            "🙆",
            "🙋",
            "🙎",
            "🙍",
            "🐵",
            "🙈",
            "🙉",
            "🙊",
            "❤️",
            "💔",
            "💌",
            "💕",
            "💞",
            "💓",
            "💗",
            "💖",
            "💘",
            "💝",
            "💟",
            "💜",
            "💛",
            "💚",
            "💙",
            "✋🏿",
            "💪🏿",
            "👐🏿",
            "🙌🏿",
            "👏🏿",
            "🙏🏿",
            "👨‍👩‍👦",
            "👨‍👩‍👧‍👦",
            "👨‍👨‍👦",
            "👩‍👩‍👧",
            "👨‍👦",
            "👨‍👧‍👦",
            "👩‍👦",
            "👩‍👧‍👦",
            "🚾",
            "🆒",
            "🆓",
            "🆕",
            "🆖",
            "🆗",
            "🆙",
            "🏧",
            "0️⃣",
            "1️⃣",
            "2️⃣",
            "3️⃣",
            "4️⃣",
            "5️⃣",
            "6️⃣",
            "7️⃣",
            "8️⃣",
            "9️⃣",
            "🔟",
            "🇦🇫",
            "🇦🇲",
            "🇺🇸",
            "🇷🇺",
            "🇸🇦",
            "🇸🇦",
            "🇨🇦"
        ]
        for emoji in moreEmojis {
            if !emoji.isSingleEmojiUsingEmojiWithSkinTones {
                Logger.warn("!isSingleEmojiUsingEmojiWithSkinTones: '\(emoji)'")
            }
            XCTAssertTrue(emoji.isSingleEmojiUsingEmojiWithSkinTones)

            if !emoji.isSingleEmojiUsingCoreText {
                Logger.warn("!isSingleEmojiUsingCoreText: '\(emoji)'")
            }
            XCTAssertTrue(emoji.isSingleEmojiUsingCoreText)

            if !emoji.isSingleEmojiUsingCount {
                Logger.warn("!isSingleEmojiUsingCount: '\(emoji)'")
            }
            XCTAssertTrue(emoji.isSingleEmojiUsingCount)

            if emoji.count != 1 {
                Logger.warn("'\(emoji)': \(emoji.count) != 1")
            }
            XCTAssertEqual(emoji.count, 1)
        }
    }
}
