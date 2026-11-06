//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import WebRTC
import XCTest

@testable import Signal

final class TurnServerInfoTest: XCTestCase {
    func testParseTurnServers() throws {
        let testCases: [TestCase] = [
            .multipleTurnServer,
            .nullableHostnameTurnServer,
        ]

        for (idx, testCase) in testCases.enumerated() {
            let (parsedIceServers, ttl) = try RTCIceServerFetcher.parse(
                turnServerInfoJsonData: testCase.jsonData,
            )

            let parsedIceServerUrls: [String] = try parsedIceServers.map { iceServer throws in
                guard iceServer.urlStrings.count == 1 else {
                    throw FailTestError("Unexpected number of URLs in ICE server in test case \(idx)!")
                }

                return iceServer.urlStrings.first!
            }

            XCTAssertEqual(
                parsedIceServerUrls,
                testCase.expectedUrls,
                "URL comparison failed for test case \(idx)",
            )

            XCTAssertEqual(
                ttl,
                testCase.expectedTtl,
                "Unexpected ttl value \(ttl) for test case \(idx)",
            )
        }
    }
}

// MARK: -

private struct FailTestError: Error {
    init(_ message: String) {
        XCTFail(message)
    }
}

private struct TestCase {
    /// An ordered list of URLs, which should match those of the `RTCIceServer`s
    /// parsed from this test case.
    let expectedUrls: [String]
    let jsonData: Data
    let expectedTtl: Int

    init(expectedUrls: [String], jsonString: String, expectedTtl: Int) {
        self.expectedUrls = expectedUrls
        self.jsonData = Data(jsonString.utf8)
        self.expectedTtl = expectedTtl
    }

    static let multipleTurnServer = TestCase(
        expectedUrls: [
            "turn:[4444:bbbb:cccc:0:0:0:0:1]",
            "turn:4.turn.signal.org",
            "turn:[5555:bbbb:cccc:0:0:0:0:1]",
            "turn:5.turn.signal.org",
        ],
        jsonString: """
        {
            "relays": [{
                "username": "user",
                "password": "pass",
                "urls": [
                    "turn:4.turn.signal.org"
                ],
                "urlsWithIps": [
                    "turn:[4444:bbbb:cccc:0:0:0:0:1]",
                ],
                "hostname": "4.voip.signal.org",
            }, {
                "username": "user",
                "password": "pass",
                "urls": [
                    "turn:5.turn.signal.org"
                ],
                "urlsWithIps": [
                    "turn:[5555:bbbb:cccc:0:0:0:0:1]",
                ],
                "hostname": "5.voip.signal.org"
            }]
        }
        """,
        expectedTtl: 0,
    )

    static let multipleTurnServerWithTtl = TestCase(
        expectedUrls: [
            "turn:[4444:bbbb:cccc:0:0:0:0:1]",
            "turn:4.turn.signal.org",
            "turn:[5555:bbbb:cccc:0:0:0:0:1]",
            "turn:5.turn.signal.org",
        ],
        jsonString: """
        {
            "relays": [{
                "username": "user",
                "password": "pass",
                "urls": [
                    "turn:4.turn.signal.org"
                ],
                "urlsWithIps": [
                    "turn:[4444:bbbb:cccc:0:0:0:0:1]",
                ],
                "hostname": "4.voip.signal.org",
                "ttl": "86400"
            }, {
                "username": "user",
                "password": "pass",
                "urls": [
                    "turn:5.turn.signal.org"
                ],
                "urlsWithIps": [
                    "turn:[5555:bbbb:cccc:0:0:0:0:1]",
                ],
                "hostname": "5.voip.signal.org",
                "ttl": "43200"
            }]
        }
        """,
        expectedTtl: 43200,
    )

    static let nullableHostnameTurnServer = TestCase(
        expectedUrls: [
            "turn:[4444:bbbb:cccc:0:0:0:0:1]",
            "turn:4.turn.signal.org",
        ],
        jsonString: """
        {
            "relays": [{
                "username": "user",
                "password": "pass",
                "urls": [
                    "turn:4.turn.signal.org"
                ],
                "urlsWithIps": [
                    "turn:[4444:bbbb:cccc:0:0:0:0:1]",
                ]
            }]
        }
        """,
        expectedTtl: 0,
    )
}
