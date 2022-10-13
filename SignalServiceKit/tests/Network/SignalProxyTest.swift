//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

class SignalProxyTest: XCTestCase {
    func testIsValidProxyLink() throws {
        let validHrefs: [String] = [
            "https://signal.tube/#example.com",
            "sgnl://signal.tube/#example.com",
            "sgnl://signal.tube/extrapath?extra=query#example.com",
            "HTTPS://SIGNAL.TUBE/#EXAMPLE.COM"
        ]
        for href in validHrefs {
            let url = URL(string: href)!
            XCTAssertTrue(SignalProxy.isValidProxyLink(url), href)
        }

        let invalidHrefs: [String] = [
            // Wrong protocol
            "http://signal.tube/#example.com",
            // Wrong host
            "https://example.net/#example.com",
            "https://signal.org/#example.com",
            // Extra stuff
            "https://user:pass@signal.tube/#example.com",
            "https://signal.tube:1234/#example.com",
            // Invalid or missing hash
            "https://signal.tube",
            "https://signal.tube/example.com",
            "https://signal.tube/#",
            "https://signal.tube/#example",
            "https://signal.tube/#example.com.",
            "https://signal.tube/#example.com/",
            "https://signal.tube/#\(String(repeating: "x", count: 9999)).example.com",
            "https://signal.tube/#https://example.com"
        ]
        for href in invalidHrefs {
            let url = URL(string: href)!
            XCTAssertFalse(SignalProxy.isValidProxyLink(url), href)
        }
    }
}
