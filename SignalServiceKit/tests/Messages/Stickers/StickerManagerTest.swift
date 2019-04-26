//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
import Foundation
import SignalCoreKit
import SignalMetadataKit
@testable import SignalServiceKit

class StickerManagerTest: SSKBaseTestSwift {

    func testEmojiParsing() {
        XCTAssertNil(StickerManager.firstEmoji(inEmojiString: nil))
        XCTAssertEqual("🇨🇦", StickerManager.firstEmoji(inEmojiString: "🇨🇦"))
        XCTAssertEqual("🇨🇦", StickerManager.firstEmoji(inEmojiString: "🇨🇦🇨🇦"))
        XCTAssertEqual("🇹🇹", StickerManager.firstEmoji(inEmojiString: "🇹🇹🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual("🌼", StickerManager.firstEmoji(inEmojiString: "🌼🇹🇹🌼🇹🇹"))
        XCTAssertEqual("👌🏽", StickerManager.firstEmoji(inEmojiString: "👌🏽👌🏾"))
        XCTAssertEqual("👌🏾", StickerManager.firstEmoji(inEmojiString: "👌🏾👌🏽"))
        XCTAssertEqual("👾", StickerManager.firstEmoji(inEmojiString: "👾🙇💁🙅🙆🙋🙎🙍"))
    }
}
