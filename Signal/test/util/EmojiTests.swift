//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal

class EmojiTests: SignalBaseTest {

    override func setUp() {
        super.setUp()
    }

    func test_roundtrip() {
        XCTAssertFalse("".isSingleEmoji)
        XCTAssertTrue("😃".isSingleEmoji)
        XCTAssertFalse("😃😃".isSingleEmoji)
        XCTAssertFalse("a".isSingleEmoji)
        XCTAssertFalse(" 😃".isSingleEmoji)
        XCTAssertFalse("😃 ".isSingleEmoji)

        XCTAssertFalse("".isSingleEmojiWithoutCoreText)
        XCTAssertTrue("😃".isSingleEmojiWithoutCoreText)
        XCTAssertFalse("😃😃".isSingleEmojiWithoutCoreText)
        XCTAssertFalse("a".isSingleEmojiWithoutCoreText)
        XCTAssertFalse(" 😃".isSingleEmojiWithoutCoreText)
        XCTAssertFalse("😃 ".isSingleEmojiWithoutCoreText)
    }
}
