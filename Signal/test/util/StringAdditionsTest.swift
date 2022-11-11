//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

class StringAdditionsTest: SignalBaseTest {
    func test_truncated_ASCII() {
        let originalString = "Hello World"

        var truncatedString = originalString.truncated(toByteCount: 8)
        XCTAssertEqual("Hello Wo", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 0)
        XCTAssertEqual("", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 11)
        XCTAssertEqual("Hello World", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 12)
        XCTAssertEqual("Hello World", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 100)
        XCTAssertEqual("Hello World", truncatedString)
    }

    func test_truncated_MultiByte() {
        let originalString = "🇨🇦🇨🇦🇨🇦🇨🇦"

        var truncatedString = originalString.truncated(toByteCount: 0)
        XCTAssertEqual("", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 1)
        XCTAssertEqual("", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 7)
        XCTAssertEqual("", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 8)
        XCTAssertEqual("🇨🇦", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 9)
        XCTAssertEqual("🇨🇦", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 15)
        XCTAssertEqual("🇨🇦", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 16)
        XCTAssertEqual("🇨🇦🇨🇦", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 17)
        XCTAssertEqual("🇨🇦🇨🇦", truncatedString)
    }

    func test_truncated_Mixed() {
        let originalString = "Oh🇨🇦Canada🇨🇦"

        var truncatedString = originalString.truncated(toByteCount: 0)
        XCTAssertEqual("", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 1)
        XCTAssertEqual("O", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 7)
        XCTAssertEqual("Oh", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 9)
        XCTAssertEqual("Oh", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 10)
        XCTAssertEqual("Oh🇨🇦", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 11)
        XCTAssertEqual("Oh🇨🇦C", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 23)
        XCTAssertEqual("Oh🇨🇦Canada", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 24)
        XCTAssertEqual("Oh🇨🇦Canada🇨🇦", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 25)
        XCTAssertEqual("Oh🇨🇦Canada🇨🇦", truncatedString)

        truncatedString = originalString.truncated(toByteCount: 100)
        XCTAssertEqual("Oh🇨🇦Canada🇨🇦", truncatedString)
    }
}
