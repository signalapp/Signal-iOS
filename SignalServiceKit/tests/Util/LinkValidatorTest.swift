//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class LinkValidatorTest: XCTestCase {
    func testCanParseURLs() {
        XCTAssertTrue(LinkValidator.canParseURLs(in: "https://signal.org/"))
        XCTAssertFalse(LinkValidator.canParseURLs(in: "\u{202e}https://signal.org/"))
    }

    func testFirstLinkPreviewURL() {
        let testCases: [(String, String?)] = [
            // Invalid: Explicit scheme is required
            ("signal.org", nil),
            ("www.signal.org", nil),
            ("https.signal.org", nil),

            // Invalid: Scheme must be https
            ("http://www.signal.org", nil),
            ("ftp://www.signal.org", nil),

            // Valid
            ("https://signal.org", "https://signal.org"),
            ("HTTPS://signal.org", "HTTPS://signal.org"),
            ("https://www.signal.org", "https://www.signal.org"),
            ("https://www.signal.org:443/blahh.html?query=value", "https://www.signal.org:443/blahh.html?query=value"),
            ("https://test.signal.org/", "https://test.signal.org/"),

            // Invalid: Username/Password disallowed
            ("https://mlin@www.signal.org", nil),
            ("https://:pass@www.signal.org", nil),
            ("https://mlin:mypass@www.signal.org", nil),

            // Invalid: .onion TLD explicitly disallowed
            ("https://3g2upl4pq6kufc4m.onion", nil),
            ("https://3g2upl4pq6kufc4m.ONION", nil),
            ("https://3g2upl4pq6kufc4m....onion", nil),

            // Valid
            ("https://3g2upl4pq6kufc4m.onion.com", "https://3g2upl4pq6kufc4m.onion.com"),
            ("https://3g2upl4pq6kufc4m.oniony", "https://3g2upl4pq6kufc4m.oniony"),
            ("https://3g2upl4pq6kufc4m.oonion", "https://3g2upl4pq6kufc4m.oonion"),
            ("https://3g2upl4pq6kufc4m.oniony/onion", "https://3g2upl4pq6kufc4m.oniony/onion"),
            ("https://3g2upl4pq6kufc4m.oniony#onion", "https://3g2upl4pq6kufc4m.oniony#onion"),

            // Invalid: invalid tld with trailing '.'
            ("https://3g2upl4pq6kufc4m.example.", nil),
            ("https://3g2upl4pq6kufc4m.test.", nil),

            // Invalid: other invalid tld.
            ("https://3g2upl4pq6kufc4m.example", nil),
            ("https://3g2upl4pq6kufc4m.i2p", nil),
            ("https://3g2upl4pq6kufc4m.invalid", nil),
            ("https://3g2upl4pq6kufc4m.localhost", nil),

            // Invalid: example.[com,org,net]
            ("https://example.org", nil),
            ("https://example.edu", "https://example.edu"),
            ("https://example.test.org", "https://example.test.org"),
            ("https://3g2upl4pq6kufc4m.example.com.", nil),

            // Invalid, mixed-ASCII
            ("https://www.wikipediа.org", nil), // (а is cyrillic)
            ("https://www.wikipediä.org", nil),

            // This is a valid URL. Our heuristic is a little sensitive
            // If we relax our heuristic and this returns non-nil, that's okay
            ("https://中国互联网络信息中心.cn", nil),

            // NSDataDetector parsing failures
            ("https://中国互联网络信息中心。中国", nil),   // NSDataDetector does not parse a TLD of "。中国"

            // Valid, all ASCII or non-ASCII + period
            ("https://中国互联网络信息中心.中国", "https://xn--fiqa61au8b7zsevnm8ak20mc4a87e.xn--fiqs8s"),
            ("https://中国互联网络信息中心.中国/nonASCIIPath", "https://xn--fiqa61au8b7zsevnm8ak20mc4a87e.xn--fiqs8s/nonASCIIPath"),
            ("https://中国互联网络信息中心.中国?nonASCIIQuery", "https://xn--fiqa61au8b7zsevnm8ak20mc4a87e.xn--fiqs8s?nonASCIIQuery"),
            ("https://中国互联网络信息中心.中国#fragment", "https://xn--fiqa61au8b7zsevnm8ak20mc4a87e.xn--fiqs8s#fragment"),
            ("https://signal.org#你好", "https://signal.org#%E4%BD%A0%E5%A5%BD"),

            // Invalid characters in path/params
            ("https://signal.org/你好", nil),
            ("https://signal.org?你好", nil),
            ("https://signal.org/hello?你好", nil),
            ("https://signal.org/наушники", nil),
            ("https://signal.org/hello?param=наушники", nil),

            ("", nil),
            ("alice bob jim", nil),
            ("alice bob jim http://", nil),
            ("alice bob jim http://a.com", nil),

            ("https://www.youtube.com/watch?v=tP-Ipsat90c", "https://www.youtube.com/watch?v=tP-Ipsat90c"),

            ("alice bob https://www.youtube.com/watch?v=tP-Ipsat90c jim", "https://www.youtube.com/watch?v=tP-Ipsat90c"),

            // If there is more than one, take the first.
            ("alice bob https://signal.org/url_1 jim https://signal.org/url_2 carol", "https://signal.org/url_1"),

            // If there's too much text, we can't parse any URLs.
            ("https://signal.org " + String(repeating: "A", count: 4096), nil),

            // Code points that are valid outside the link, but not inside
            ("▶ https://signal.org", "https://signal.org"),
            ("https://si▶gnal.org", nil)
        ]
        for (entireMessage, expectedValue) in testCases {
            let actualValue = LinkValidator.firstLinkPreviewURL(in: .init(text: entireMessage, ranges: .empty))
            XCTAssertEqual(actualValue?.absoluteString, expectedValue, entireMessage)
        }
    }

    func testFirstLinkPreviewURLPerformance() throws {
        let entireMessage = String(repeating: "https://signal.org ", count: 1_000_000)
        measure {
            let actualValue = LinkValidator.firstLinkPreviewURL(in: .init(text: entireMessage, ranges: .empty))
            XCTAssertNil(actualValue)
        }
    }
}
