//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest

class StringAdditionsTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

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

    func test_caesar() {
        XCTAssertEqual("abc", try! "abc".caesar(shift: 0))
        XCTAssertEqual("abc", try! "abc".caesar(shift: 127))

        XCTAssertEqual("bcd", try! "abc".caesar(shift: 1))
        XCTAssertEqual("bcd", try! "abc".caesar(shift: 128))

        XCTAssertEqual("z{b", try! "yza".caesar(shift: 1))
        XCTAssertEqual("|}d", try! "yza".caesar(shift: 3))
        XCTAssertEqual("ef=g", try! "bc:d".caesar(shift: 3))

        let shifted = try! "abc".caesar(shift: 32)
        let roundTrip = try! shifted.caesar(shift: 127 - 32)
        XCTAssertEqual("abc", roundTrip)
    }

    func test_encodedForSelector() {
        XCTAssertEqual("cnN0", "abc".encodedForSelector)
        XCTAssertEqual("abc", "abc".encodedForSelector!.decodedForSelector)

        XCTAssertNotEqual("abcWithFoo:bar:", "abcWithFoo:bar:".encodedForSelector)
        XCTAssertEqual("abcWithFoo:bar:", "abcWithFoo:bar:".encodedForSelector!.decodedForSelector)

        XCTAssertNotEqual("abcWithFoo:bar:zaz1:", "abcWithFoo:bar:zaz1:".encodedForSelector)
        XCTAssertEqual("abcWithFoo:bar:zaz1:", "abcWithFoo:bar:zaz1:".encodedForSelector!.decodedForSelector)
    }
}
