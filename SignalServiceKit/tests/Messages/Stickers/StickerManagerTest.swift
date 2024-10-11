//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Foundation
@testable import SignalServiceKit

class StickerManagerTest: XCTestCase {

    func testFirstEmoji() {
        XCTAssertEqual(nil, StickerManager.firstEmoji(in: ""))
        XCTAssertEqual(nil, StickerManager.firstEmoji(in: "ABC"))
        XCTAssertEqual("🇨🇦", StickerManager.firstEmoji(in: "🇨🇦"))
        XCTAssertEqual("🇨🇦", StickerManager.firstEmoji(in: "🇨🇦🇨🇦"))
        XCTAssertEqual("🇹🇹", StickerManager.firstEmoji(in: "🇹🇹🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual("🌼", StickerManager.firstEmoji(in: "🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual("👌🏽", StickerManager.firstEmoji(in: "👌🏽👌🏾"))
        XCTAssertEqual("👌🏾", StickerManager.firstEmoji(in: "👌🏾👌🏽"))
        XCTAssertEqual("👾", StickerManager.firstEmoji(in: "👾🙇💁🙅🙆🙋🙎🙍"))
        XCTAssertEqual("👾", StickerManager.firstEmoji(in: "👾🙇💁🙅🙆🙋🙎🙍"))
    }

    func testAllEmoji() {
        XCTAssertEqual(["🇨🇦"], Array(StickerManager.allEmoji(in: "🇨🇦")))
        XCTAssertEqual(["🇨🇦", "🇨🇦"], Array(StickerManager.allEmoji(in: "🇨🇦🇨🇦")))
        XCTAssertEqual(["🇹🇹", "🌼", "🇹🇹", "🌼", "🇹🇹"], Array(StickerManager.allEmoji(in: "🇹🇹🌼🇹🇹🌼🇹🇹")))
        XCTAssertEqual(["🌼", "🇹🇹", "🌼", "🇹🇹"], Array(StickerManager.allEmoji(in: "🌼🇹🇹🌼🇹🇹")))
        XCTAssertEqual(["👌🏽", "👌🏾"], Array(StickerManager.allEmoji(in: "👌🏽👌🏾")))
        XCTAssertEqual(["👌🏾", "👌🏽"], Array(StickerManager.allEmoji(in: "👌🏾👌🏽")))
        XCTAssertEqual(["👾", "🙇", "💁", "🙅", "🙆", "🙋", "🙎", "🙍"], Array(StickerManager.allEmoji(in: "👾🙇💁🙅🙆🙋🙎🙍")))

        XCTAssertEqual(["🇨🇦"], Array(StickerManager.allEmoji(in: "a🇨🇦a")))
        XCTAssertEqual(["🇨🇦", "🇹🇹"], Array(StickerManager.allEmoji(in: "a🇨🇦b🇹🇹c")))
    }

    func testSuggestedStickerEmoji() {
        let testCases: [(String, Character?)] = [
            ("", nil),
            ("Hey Bob, what's up?", nil),
            ("a🇨🇦", nil),
            ("🇨🇦a", nil),
            ("🇨🇦🇹🇹", nil),
            ("🌼🇨🇦", nil),
            ("This is a flag: 🇨🇦", nil),
            ("🇨🇦", "🇨🇦"),
            ("🌼", "🌼"),
            ("🇹🇹", "🇹🇹"),
        ]
        for (inputValue, suggestedEmoji) in testCases {
            XCTAssertEqual(StickerManager.suggestedStickerEmoji(chatBoxText: inputValue), suggestedEmoji, "\(inputValue)")
        }
    }

    func testInfos() {
        let packId = Randomness.generateRandomBytes(16)
        let packKey = Randomness.generateRandomBytes(StickerManager.packKeyLength)
        let stickerId: UInt32 = 0

        XCTAssertEqual(StickerPackInfo(packId: packId, packKey: packKey), StickerPackInfo(packId: packId, packKey: packKey))
        XCTAssertTrue(StickerPackInfo(packId: packId, packKey: packKey) == StickerPackInfo(packId: packId, packKey: packKey))

        XCTAssertEqual(StickerInfo(packId: packId, packKey: packKey, stickerId: stickerId), StickerInfo(packId: packId, packKey: packKey, stickerId: stickerId))
        XCTAssertTrue(StickerInfo(packId: packId, packKey: packKey, stickerId: stickerId) == StickerInfo(packId: packId, packKey: packKey, stickerId: stickerId))
    }

    func testDecryption() {
        // From the Zozo the French Bulldog sticker pack
        let packKey = Data([
            0x17, 0xe9, 0x71, 0xc1, 0x34, 0x03, 0x56, 0x22,
            0x78, 0x1d, 0x2e, 0xe2, 0x49, 0xe6, 0x47, 0x3b,
            0x77, 0x45, 0x83, 0x75, 0x0b, 0x68, 0xc1, 0x1b,
            0xb8, 0x2b, 0x75, 0x09, 0xc6, 0x8b, 0x6d, 0xfd
        ])

        let bundle = Bundle(for: StickerManagerTest.self)
        let encryptedStickerURL = bundle.url(forResource: "sample-sticker", withExtension: "encrypted")!

        let decryptedStickerURL = bundle.url(forResource: "sample-sticker", withExtension: "webp")!
        let decryptedStickerData = try! Data(contentsOf: decryptedStickerURL)

        let outputUrl = try! StickerManager.decrypt(at: encryptedStickerURL, packKey: packKey)
        let outputData = try! Data(contentsOf: outputUrl)
        XCTAssertEqual(outputData, decryptedStickerData)
    }
}

class StickerManagerTest2: SSKBaseTest {

    func testSuggestedStickers() {
        // The "StickerManager.suggestedStickers" instance method does caching;
        // the class method does not.

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertEqual(0, StickerManager.suggestedStickers(for: "🇨🇦", tx: tx).count)
        }

        let stickerInfo = StickerInfo.defaultValue
        let stickerData = Randomness.generateRandomBytes(1)
        let temporaryFile = OWSFileSystem.temporaryFileUrl()
        try! stickerData.write(to: temporaryFile)

        let success = StickerManager.installSticker(
            stickerInfo: stickerInfo,
            stickerUrl: temporaryFile,
            contentType: MimeType.imageWebp.rawValue,
            emojiString: "🌼🇨🇦"
        )
        XCTAssertTrue(success)

        // The sticker should only be suggested if user enters a single emoji
        // (and nothing else) that is associated with the sticker.
        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertEqual(1, StickerManager.suggestedStickers(for: "🇨🇦", tx: tx).count)
            XCTAssertEqual(1, StickerManager.suggestedStickers(for: "🌼", tx: tx).count)
            XCTAssertEqual(0, StickerManager.suggestedStickers(for: "🇹🇹", tx: tx).count)
        }

        SSKEnvironment.shared.databaseStorageRef.write { (transaction) in
            // Don't bother calling completion.
            StickerManager.uninstallSticker(stickerInfo: stickerInfo, transaction: transaction)
        }

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            XCTAssertEqual(0, StickerManager.suggestedStickers(for: "🇨🇦", tx: tx).count)
        }
    }
}
