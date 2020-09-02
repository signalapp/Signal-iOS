//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
import Foundation
import SignalCoreKit
import SignalMetadataKit
@testable import SignalServiceKit

class StickerManagerTest: SSKBaseTestSwift {

    func testFirstEmoji() {
        XCTAssertNil(StickerManager.firstEmoji(inEmojiString: nil))
        XCTAssertEqual("🇨🇦", StickerManager.firstEmoji(inEmojiString: "🇨🇦"))
        XCTAssertEqual("🇨🇦", StickerManager.firstEmoji(inEmojiString: "🇨🇦🇨🇦"))
        XCTAssertEqual("🇹🇹", StickerManager.firstEmoji(inEmojiString: "🇹🇹🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual("🌼", StickerManager.firstEmoji(inEmojiString: "🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual("👌🏽", StickerManager.firstEmoji(inEmojiString: "👌🏽👌🏾"))
        XCTAssertEqual("👌🏾", StickerManager.firstEmoji(inEmojiString: "👌🏾👌🏽"))
        XCTAssertEqual("👾", StickerManager.firstEmoji(inEmojiString: "👾🙇💁🙅🙆🙋🙎🙍"))
        XCTAssertEqual("👾", StickerManager.firstEmoji(inEmojiString: "👾🙇💁🙅🙆🙋🙎🙍"))
    }

    func testAllEmoji() {
        XCTAssertEqual([], StickerManager.allEmoji(inEmojiString: nil))
        XCTAssertEqual(["🇨🇦"], StickerManager.allEmoji(inEmojiString: "🇨🇦"))
        XCTAssertEqual(["🇨🇦", "🇨🇦"], StickerManager.allEmoji(inEmojiString: "🇨🇦🇨🇦"))
        XCTAssertEqual(["🇹🇹", "🌼", "🇹🇹", "🌼", "🇹🇹"], StickerManager.allEmoji(inEmojiString: "🇹🇹🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual(["🌼", "🇹🇹", "🌼", "🇹🇹"], StickerManager.allEmoji(inEmojiString: "🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual(["👌🏽", "👌🏾"], StickerManager.allEmoji(inEmojiString: "👌🏽👌🏾"))
        XCTAssertEqual(["👌🏾", "👌🏽"], StickerManager.allEmoji(inEmojiString: "👌🏾👌🏽"))
        XCTAssertEqual(["👾", "🙇", "💁", "🙅", "🙆", "🙋", "🙎", "🙍"], StickerManager.allEmoji(inEmojiString: "👾🙇💁🙅🙆🙋🙎🙍"))

        XCTAssertEqual(["🇨🇦"], StickerManager.allEmoji(inEmojiString: "a🇨🇦a"))
        XCTAssertEqual(["🇨🇦", "🇹🇹"], StickerManager.allEmoji(inEmojiString: "a🇨🇦b🇹🇹c"))
    }

    func testSuggestedStickers_uncached() {
        // The "StickerManager.suggestedStickers" instance method does caching;
        // the class method does not.

        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "Hey Bob, what's up?").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦🇹🇹").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "This is a flag: 🇨🇦").count)

        let stickerInfo = StickerInfo.defaultValue
        let stickerData = Randomness.generateRandomBytes(1)

        let expectation = self.expectation(description: "Wait for sticker to be installed.")
        StickerManager.installSticker(stickerInfo: stickerInfo,
                                      stickerData: stickerData,
                                      contentType: OWSMimeTypeImageWebp,
                                      emojiString: "🌼🇨🇦") {
                                        expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "Hey Bob, what's up?").count)
        // The sticker should only be suggested if user enters a single emoji
        // (and nothing else) that is associated with the sticker.
        XCTAssertEqual(1, StickerManager.suggestedStickers(forTextInput: "🇨🇦").count)
        XCTAssertEqual(1, StickerManager.suggestedStickers(forTextInput: "🌼").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇹🇹").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "a🇨🇦").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦a").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦🇹🇹").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🌼🇨🇦").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "This is a flag: 🇨🇦").count)

        databaseStorage.write { (transaction) in
            // Don't bother calling completion.
            _ = StickerManager.uninstallSticker(stickerInfo: stickerInfo,
                                                transaction: transaction)
        }

        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "Hey Bob, what's up?").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "🇨🇦🇹🇹").count)
        XCTAssertEqual(0, StickerManager.suggestedStickers(forTextInput: "This is a flag: 🇨🇦").count)
    }

    func testSuggestedStickers_cached() {
        // The "StickerManager.suggestedStickers" instance method does caching;
        // the class method does not.
        let stickerManager = StickerManager.shared

        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "Hey Bob, what's up?").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "🇨🇦").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "🇨🇦🇹🇹").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "This is a flag: 🇨🇦").count)

        let stickerInfo = StickerInfo.defaultValue
        let stickerData = Randomness.generateRandomBytes(1)

        let expectation = self.expectation(description: "Wait for sticker to be installed.")
        StickerManager.installSticker(stickerInfo: stickerInfo,
                                      stickerData: stickerData,
                                      contentType: OWSMimeTypeImageWebp,
                                      emojiString: "🌼🇨🇦") {
                                        expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0, handler: nil)

        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "Hey Bob, what's up?").count)
        // The sticker should only be suggested if user enters a single emoji
        // (and nothing else) that is associated with the sticker.
        XCTAssertEqual(1, stickerManager.suggestedStickers(forTextInput: "🇨🇦").count)
        XCTAssertEqual(1, stickerManager.suggestedStickers(forTextInput: "🌼").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "🇹🇹").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "a🇨🇦").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "🇨🇦a").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "🇨🇦🇹🇹").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "🌼🇨🇦").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "This is a flag: 🇨🇦").count)

        databaseStorage.write { (transaction) in
            // Don't bother calling completion.
            _ = StickerManager.uninstallSticker(stickerInfo: stickerInfo,
                                                transaction: transaction)
        }

        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "Hey Bob, what's up?").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "🇨🇦").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "🇨🇦🇹🇹").count)
        XCTAssertEqual(0, stickerManager.suggestedStickers(forTextInput: "This is a flag: 🇨🇦").count)
    }

    func testInfos() {
        let packId = Randomness.generateRandomBytes(16)
        let packKey = Randomness.generateRandomBytes(Int32(StickerManager.packKeyLength))
        let stickerId: UInt32 = 0

        XCTAssertEqual(StickerPackInfo(packId: packId, packKey: packKey),
                       StickerPackInfo(packId: packId, packKey: packKey))
        XCTAssertTrue(StickerPackInfo(packId: packId, packKey: packKey) == StickerPackInfo(packId: packId, packKey: packKey))

        XCTAssertEqual(StickerInfo(packId: packId, packKey: packKey, stickerId: stickerId),
                       StickerInfo(packId: packId, packKey: packKey, stickerId: stickerId))
        XCTAssertTrue(StickerInfo(packId: packId, packKey: packKey, stickerId: stickerId) == StickerInfo(packId: packId, packKey: packKey, stickerId: stickerId))
    }
}
