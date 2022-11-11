//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class OWSHttpHeadersTest: XCTestCase {
    func testFormatAcceptLanguageHeader() throws {
        func chars(_ str: String) -> [String] {
            str.map { String($0) }
        }

        let testCases: [[String]: String] = [
            []: "*",
            ["invalid!"]: "*",
            ["bad1", "bad2", "no_unders", "itstoolong", "en--", "en--us", "en-*stars*", "en-**"]: "*",

            ["en-US"]: "en-US",
            ["en-*"]: "en-*",
            ["*-US"]: "*-US",
            ["*-*"]: "*-*",
            ["a-b-c2-d"]: "a-b-c2-d",
            ["bad1", "ok", "bad2"]: "ok",

            // This was an actual string sent from someone's device, so we test that it's ignored.
            ["en-US@attribute=isk", "de"]: "de",

            ["a", "b", "c"]: "a, b;q=0.9, c;q=0.8",
            ["a", "b", "bad123", "c"]: "a, b;q=0.9, c;q=0.8",
            chars("abcdefghij"): "a, b;q=0.9, c;q=0.8, d;q=0.7, e;q=0.6, f;q=0.5, g;q=0.4, h;q=0.3, i;q=0.2, j;q=0.1",
            chars("abcdefghijklmnopqrst"): "a, b;q=0.9, c;q=0.8, d;q=0.7, e;q=0.6, f;q=0.5, g;q=0.4, h;q=0.3, i;q=0.2, j;q=0.1",
            chars("a!b@c#d$e%f^g&h(i)j_"): "a, b;q=0.9, c;q=0.8, d;q=0.7, e;q=0.6, f;q=0.5, g;q=0.4, h;q=0.3, i;q=0.2, j;q=0.1"
        ]

        for (languages, expected) in testCases {
            let actual = OWSHttpHeaders.formatAcceptLanguageHeader(languages)
            XCTAssertEqual(actual, expected, "Input: \(languages)")
        }
    }

    func testAcceptLanguageHeaderValue() throws {
        let expected = OWSHttpHeaders.formatAcceptLanguageHeader(Locale.preferredLanguages)
        let actual = OWSHttpHeaders.acceptLanguageHeaderValue
        XCTAssertEqual(actual, expected)
    }
}
