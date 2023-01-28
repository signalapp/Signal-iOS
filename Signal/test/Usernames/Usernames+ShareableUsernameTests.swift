//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class UsernamesShareableUsernameTests: XCTestCase {
    private typealias Username = String

    func testUsernameStrings() {
        let testCases: [(Username, String)] = [
            ("myusername", "myusername"),
            ("", "")
        ]

        for testCase in testCases {
            let (username, expected) = testCase
            let actual = Usernames.ShareableUsername(username: username).asString

            XCTAssertEqual(
                actual,
                expected
            )
        }
    }

    func testShortUrls() {
        let testCases: [(Username, String)] = [
            ("myusername", "signal.me/myusername"),
            ("?weird # but not disallowed/here", "signal.me/%3Fweird%20%23%20but%20not%20disallowed/here")
        ]

        for testCase in testCases {
            let (username, expected) = testCase
            let actual = Usernames.ShareableUsername(username: username).asShortUrlString

            XCTAssertEqual(
                actual,
                expected
            )
        }
    }

    func testSignalDotMeUrl() {
        let testCases: [(Username, URL?)] = [
            ("myusername", URL(string: "https://signal.me/myusername")!),
            ("?weird # but not disallowed/here", URL(string: "https://signal.me/%3Fweird%20%23%20but%20not%20disallowed/here")!)
        ]

        for testCase in testCases {
            let (username, expected) = testCase
            let actual = Usernames.ShareableUsername(username: username).asUrl

            XCTAssertEqual(
                actual,
                expected
            )
        }
    }
}
