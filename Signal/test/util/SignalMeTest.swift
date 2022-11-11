//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class SignalMeTest: XCTestCase {
    func testIsPossibleUrl() throws {
        let validStrings = [
            "https://signal.me/#p/+14085550123",
            "hTTPs://sigNAL.mE/#P/+14085550123",
            "https://signal.me/#p/+9",
            "sgnl://signal.me/#p/+14085550123"
        ]
        for string in validStrings {
            let url = try XCTUnwrap(URL(string: string))
            XCTAssertTrue(SignalMe.isPossibleUrl(url), "\(url)")
        }

        let invalidStrings = [
            // Invalid protocols
            "http://signal.me/#p/+14085550123",
            "signal://signal.me/#p/+14085550123",
            // Extra auth
            "https://user:pass@signal.me/#p/+14085550123",
            // Invalid host
            "https://example.me/#p/+14085550123",
            "https://signal.org/#p/+14085550123",
            "https://signal.group/#p/+14085550123",
            "https://signal.art/#p/+14085550123",
            "https://signal.me:80/#p/+14085550123",
            "https://signal.me:443/#p/+14085550123",
            // Wrong path or hash
            "https://signal.me/foo#p/+14085550123",
            "https://signal.me/#+14085550123",
            "https://signal.me/#p+14085550123",
            "https://signal.me/#u/+14085550123",
            "https://signal.me//#p/+14085550123",
            "https://signal.me/?query=string#p/+14085550123",
            // Invalid E164s
            "https://signal.me/#p/4085550123",
            "https://signal.me/#p/+",
            "https://signal.me/#p/+one",
            "https://signal.me/#p/+14085550123x",
            "https://signal.me/#p/+14085550123/"
        ]
        for string in invalidStrings {
            let url = try XCTUnwrap(URL(string: string))
            XCTAssertFalse(SignalMe.isPossibleUrl(url), "\(url)")
        }
    }
}
