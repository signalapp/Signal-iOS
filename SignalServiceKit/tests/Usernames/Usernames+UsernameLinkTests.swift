//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class UsernamesUsernameLinkTests: XCTestCase {
    private typealias Username = String

    func testAestheticUrls() {
        let testCases: [(Username, String)] = [
            ("myusername", "signal.me/#u/bXl1c2VybmFtZQ"),
            ("?weird # but not disallowed/here", "signal.me/#u/P3dlaXJkICMgYnV0IG5vdCBkaXNhbGxvd2VkL2hlcmU")
        ]

        for testCase in testCases {
            let (username, expected) = testCase
            let actual = Usernames.UsernameLink(username: username).asAestheticUrlString

            XCTAssertEqual(actual, expected)
        }
    }

    func testSignalDotMeUrl() {
        let testCases: [(Username, URL?)] = [
            ("myusername", URL(string: "https://signal.me/#u/bXl1c2VybmFtZQ")!),
            ("?weird # but not disallowed/here", URL(string: "https://signal.me/#u/P3dlaXJkICMgYnV0IG5vdCBkaXNhbGxvd2VkL2hlcmU")!)
        ]

        for testCase in testCases {
            let (username, expected) = testCase
            let actual = Usernames.UsernameLink(username: username).asUrl

            XCTAssertEqual(actual, expected)
        }
    }

    func testParseFromUrl() {
        let testCases: [(URL, Usernames.UsernameLink?)] = [
            (url(scheme: "https", host: "signal.me", path: "/", fragment: "u/ZGFydGg"), Usernames.UsernameLink(username: "darth")),
            (url(scheme: "sgnl", host: "signal.me", path: "/", fragment: "u/ZGFydGg"), Usernames.UsernameLink(username: "darth")),
            (url(scheme: "sgnl", host: "signal.me", path: "/", fragment: "u/???"), nil),
            (url(scheme: "https", host: "signal.me", path: "/", fragment: "u/???"), nil),
            (url(scheme: "https", host: "signal.me", path: "/", fragment: "ZGFydGg"), nil),
            (url(scheme: "http", host: "signal.me", path: "/", fragment: "u/ZGFydGg"), nil),
            (url(scheme: "https", host: "signal.link", path: "/", fragment: "u/ZGFydGg"), nil),
            (url(scheme: "ssh", host: "signal.org", path: "/", fragment: "u/ZGFydGg"), nil),
            (url(host: "signal.me", path: "/", fragment: "u/ZGFydGg"), nil),
            (url(scheme: "https", path: "/", fragment: "u/ZGFydGg"), nil),
            (url(scheme: "https", host: "signal.me", fragment: "u/ZGFydGg"), nil),
            (url(scheme: "https", host: "signal.me", path: "/"), nil),
            (url(scheme: "https", host: "signal.me", path: "/", fragment: "u/ZGFydGg", query: "foo=bar"), nil),
            (url(scheme: "https", host: "signal.me", path: "/", fragment: "u/ZGFydGg", user: "admin", password: "1337"), nil),
            (url(scheme: "https", host: "signal.me", path: "/", fragment: "u/ZGFydGg", port: 80), nil)
        ]

        for testCase in testCases {
            let (url, expected) = testCase
            let actual = Usernames.UsernameLink(usernameLinkUrl: url)

            XCTAssertEqual(actual, expected)
        }
    }

    /// Confirm that we are using base64url, not just base64.
    ///
    /// Uses strings that are technically invalid usernames, but produce the
    /// 63rd and 64th base64 characters, which need to be translated for
    /// base64url.
    func testBase64Url() {
        let testCases: [(Username, String)] = [
            ("aa?", "signal.me/#u/YWE_"),
            ("aa>", "signal.me/#u/YWE-")
        ]

        for testCase in testCases {
            let (username, expected) = testCase
            let actual = Usernames.UsernameLink(username: username).asAestheticUrlString

            XCTAssertEqual(actual, expected)
        }
    }

    private func url(
        scheme: String? = nil,
        host: String? = nil,
        path: String = "",
        fragment: String? = nil,
        query: String? = nil,
        user: String? = nil,
        password: String? = nil,
        port: Int? = nil
    ) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        components.fragment = fragment
        components.query = query
        components.user = user
        components.password = password
        components.port = port

        return components.url!
    }
}
