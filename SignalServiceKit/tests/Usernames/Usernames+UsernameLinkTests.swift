//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class UsernameLinkTests: XCTestCase {
    func testParseFromUrl() {
        let entropyData = Data(repeating: 12, count: 32)
        let uuidData = UUID().data
        let goodDataString = (entropyData + uuidData).asBase64Url
        let goodFragment = "eu/\(goodDataString)"

        let testCases: [(URL, Bool)] = [
            (url(scheme: "https", host: "signal.me", path: "/", fragment: goodFragment), true),
            (url(scheme: "sgnl", host: "signal.me", path: "/", fragment: goodFragment), true),
            (url(scheme: "https", host: "signal.me", path: "", fragment: goodFragment), true),
            (url(scheme: "sgnl", host: "signal.me", path: "", fragment: goodFragment), true),
            (url(scheme: "sgnl", host: "signal.me", path: "/", fragment: "eu/???"), false),
            (url(scheme: "https", host: "signal.me", path: "/", fragment: "eu/???"), false),
            (url(scheme: "https", host: "signal.me", path: "/", fragment: goodDataString), false),
            (url(scheme: "http", host: "signal.me", path: "/", fragment: goodFragment), false),
            (url(scheme: "https", host: "signal.link", path: "/", fragment: goodFragment), false),
            (url(scheme: "ssh", host: "signal.org", path: "/", fragment: goodFragment), false),
            (url(host: "signal.me", path: "/", fragment: goodFragment), false),
            (url(scheme: "https", path: "/", fragment: goodFragment), false),
            (url(scheme: "https", host: "signal.me", path: "/"), false),
            (url(scheme: "https", host: "signal.me", path: "/", fragment: goodFragment, query: "foo=bar"), false),
            (url(scheme: "https", host: "signal.me", path: "/", fragment: goodFragment, user: "admin", password: "1337"), false),
            (url(scheme: "https", host: "signal.me", path: "/", fragment: goodFragment, port: 80), false)
        ]

        for (i, testCase) in testCases.enumerated() {
            let (url, shouldParse) = testCase
            let actual = Usernames.UsernameLink(usernameLinkUrl: url)

            XCTAssertEqual(
                actual != nil,
                shouldParse,
                "\(i): \(url.absoluteString)"
            )
        }
    }

    /// Confirm that we are using base64url, not just base64.
    ///
    /// Uses strings that are technically invalid usernames, but produce the
    /// 63rd and 64th base64 characters, which need to be translated for
    /// base64url.
    func testBase64Url() {
        let knownHandle = UUID(uuidString: "EF0228A2-9EAC-46C2-ACF4-67DF5B06BE57")!

        let testCases: [(String, String)] = [
            ("aa?", "https://signal.me/#eu/YWE_AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwPvAiiinqxGwqz0Z99bBr5X"),
            ("aa>", "https://signal.me/#eu/YWE-AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwPvAiiinqxGwqz0Z99bBr5X")
        ]

        for testCase in testCases {
            let (dangerString, expected) = testCase

            let entropy = dangerString.data(using: .utf8)! + Data(repeating: 3, count: 29)

            let actual = Usernames.UsernameLink(
                handle: knownHandle,
                entropy: entropy
            )!.url.absoluteString

            XCTAssertEqual(actual, expected)
        }
    }

    private func url(
        scheme: String? = nil,
        host: String? = nil,
        path: String,
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
