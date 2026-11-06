//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct UsernameLinkTests {
    private static let entropyData = Data((0..<UsernameLink.Entropy.length).map { UInt8($0) })
    private static let handle = UUID(uuidString: "4A3B9C1D-2E5F-4B6A-8C7D-9E0F1A2B3C4D")!
    private static let goodDataString = (entropyData + handle.data).asBase64Url
    private static let goodFragment = "eu/\(goodDataString)"

    @Test(arguments: [
        (url(scheme: "https", host: "signal.me", path: "/", fragment: goodFragment), true),
        (url(scheme: "sgnl", host: "signal.me", path: "/", fragment: goodFragment), true),
        (url(scheme: "https", host: "signal.me", path: "", fragment: goodFragment), true),
        (url(scheme: "sgnl", host: "signal.me", path: "", fragment: goodFragment), true),
        (url(scheme: "sgnl", host: "signal.me", path: "/", fragment: "eu/???"), false),
        (url(scheme: "https", host: "signal.me", path: "/", fragment: "eu/???"), false),
        (url(scheme: "https", host: "signal.me", path: "/", fragment: goodDataString), false),
        (url(scheme: "https", host: "signal.me", path: "/", fragment: "eu/\((entropyData + handle.data).dropLast().asBase64Url)"), false),
        (url(scheme: "https", host: "signal.me", path: "/", fragment: "eu/\((entropyData + handle.data + Data([0])).asBase64Url)"), false),
        (url(scheme: "http", host: "signal.me", path: "/", fragment: goodFragment), false),
        (url(scheme: "https", host: "signal.link", path: "/", fragment: goodFragment), false),
        (url(scheme: "ssh", host: "signal.org", path: "/", fragment: goodFragment), false),
        (url(host: "signal.me", path: "/", fragment: goodFragment), false),
        (url(scheme: "https", path: "/", fragment: goodFragment), false),
        (url(scheme: "https", host: "signal.me", path: "/"), false),
        (url(scheme: "https", host: "signal.me", path: "/", fragment: goodFragment, query: "foo=bar"), false),
        (url(scheme: "https", host: "signal.me", path: "/", fragment: goodFragment, user: "admin", password: "1337"), false),
        (url(scheme: "https", host: "signal.me", path: "/", fragment: goodFragment, port: 80), false),
    ])
    func testParseFromUrl(testCase: (url: URL, shouldParse: Bool)) throws {
        let expected = UsernameLink(
            handle: Self.handle,
            entropy: try UsernameLink.Entropy(rawValue: Self.entropyData),
        )

        let actual = try? UsernameLink(usernameLinkUrl: testCase.url)
        #expect(actual == (testCase.shouldParse ? expected : nil))
    }

    @Test
    func testRoundTrip() throws {
        let link = UsernameLink(
            handle: UUID(),
            entropy: try UsernameLink.Entropy(rawValue: Randomness.generateRandomBytes(UInt(UsernameLink.Entropy.length))),
        )
        #expect(try UsernameLink(usernameLinkUrl: link.url) == link)
    }

    /// Confirm that we are using base64url, not just base64.
    ///
    /// Uses strings that are technically invalid usernames, but produce the
    /// 63rd and 64th base64 characters, which need to be translated for
    /// base64url.
    @Test(arguments: [
        ("aa?", "https://signal.me/#eu/YWE_AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwPvAiiinqxGwqz0Z99bBr5X"),
        ("aa>", "https://signal.me/#eu/YWE-AwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwMDAwPvAiiinqxGwqz0Z99bBr5X"),
    ])
    func testBase64Url(testCase: (dangerString: String, expected: String)) throws {
        let knownHandle = UUID(uuidString: "EF0228A2-9EAC-46C2-ACF4-67DF5B06BE57")!

        let entropy = try UsernameLink.Entropy(rawValue: Data(testCase.dangerString.utf8) + Data(repeating: 3, count: 29))

        let actual = Usernames.UsernameLink(
            handle: knownHandle,
            entropy: entropy,
        ).url.absoluteString

        #expect(actual == testCase.expected)
    }

    private static func url(
        scheme: String? = nil,
        host: String? = nil,
        path: String,
        fragment: String? = nil,
        query: String? = nil,
        user: String? = nil,
        password: String? = nil,
        port: Int? = nil,
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
