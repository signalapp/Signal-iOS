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

    func testDebugDescription() {
        let httpHeaders = OWSHttpHeaders()
        httpHeaders.addHeader("Retry-After", value: "Wed, 21 Oct 2015 07:28:01 GMT", overwriteOnConflict: true)
        httpHeaders.addHeader("x-signal-timestamp", value: "1669077270", overwriteOnConflict: true)
        httpHeaders.addHeader("Content-Type", value: "text/plain", overwriteOnConflict: true)

        XCTAssertEqual(
            "\(httpHeaders)",
            "<OWSHttpHeaders: [Content-Type; Retry-After: Wed, 21 Oct 2015 07:28:01 GMT; x-signal-timestamp: 1669077270]>"
        )
    }

    /// Test weird behavior with Apple's allHTTPHeaderFields property.
    func testURLRequestAllHTTPHeaderFields() {
        var urlRequest = URLRequest(url: URL(string: "https://signal.org")!)
        urlRequest.allHTTPHeaderFields = ["Retry-After": "1234", "X-Custom": "Value 1"]
        // this does *not* clear any headers
        urlRequest.allHTTPHeaderFields = nil
        // this does *not* clear all headers
        urlRequest.allHTTPHeaderFields = [:]
        // this does *not* clear missing headers
        urlRequest.allHTTPHeaderFields = ["x-custom": "Value 2"]
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "X-Custom"), "Value 2")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Retry-After"), "1234")
    }

    func testRetryAfter() {
        let now = Date().timeIntervalSince1970
        let testCases: [(String?, TimeInterval?)] = [
            // Reference: date -jf '%a, %d %b %Y %T %Z' <Value> +%s
            ("Thu, 01 Jan 1970 00:00:00 GMT", 0),
            ("Wed, 21 Oct 2015 07:28:01 GMT", 1445412481),

            // Reference: date -jf '%Y-%m-%dT%T%z' <Value> +%s
            ("1970-01-01T00:00:00+0000", 0),
            ("1969-12-31T16:00:00-0800", 0),
            ("2015-10-21T07:28:01+0000", 1445412481),
            ("2015-10-20T23:28:01-0800", 1445412481),

            // Relative delays
            ("1", now + 1),
            ("2", now + 2),
            ("1200.0", now + 1200),
            ("1200.5", now + 1200.5),
            ("86400.000", now + 86400),
            ("   86400.000    ", now + 86400),
            (" \t  \t86400.000\t  \t  ", now + 86400),

            // Invalid values (these used a default of 60)
            ("8/11/1994 01:02:03", now + 60),
            ("blahhh", now + 60),
            ("one", now + 60),
            ("soon", now + 60),
            ("later", now + 60),

            // Absent values (these use nil)
            (nil, nil),
            ("", nil),
            ("      ", nil),
            ("\n", nil)
        ]

        for (headerValue, expectedTimeInterval) in testCases {
            let actualTimeInterval = OWSHttpHeaders.parseRetryAfterHeaderValue(headerValue)?.timeIntervalSince1970
            if let expectedTimeInterval, let actualTimeInterval {
                XCTAssertEqual(actualTimeInterval, expectedTimeInterval, accuracy: 0.3, "\(headerValue ?? "nil")")
            } else {
                XCTAssertEqual(actualTimeInterval, expectedTimeInterval, "\(headerValue ?? "nil")")
            }
        }
    }
}
