//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class NSHTTPURLResponseTests: SSKBaseTestSwift {

    func testHTTPDateRetryAfter() {
        let strings = [
            "Thu, 01 Jan 1970 00:00:00 GMT",
            "Wed, 21 Oct 2015 07:28:00 GMT",
            "Wed, 21 Oct 2015 07:28:01 GMT",
            "Thu, 22 Oct 2015 07:28:00 GMT",
            "Thu, 22 Oct 2015 07:28:01 GMT",
            "Tue, 11 Aug 2020 05:54:39 GMT"
        ]
        strings.forEach { string in
            XCTAssertEqual(OWSHttpHeaders.parseRetryAfterHeaderValue(string), Date.ows_parseFromHTTPDateString(string)!)
        }
    }

    func testISO8601RetryAfter() {
        let strings = [
            "1970-01-01T00:00:00+0000",
            "1969-12-31T16:00:00-0800",
            "2015-10-21T07:28:00+0000",
            "2015-10-20T023:28:00-0800",
            "2015-10-21T07:28:01+0000",
            "2015-10-22T07:28:00+0000",
            "2015-10-22T07:28:01+0000",
            "2020-08-10T21:54:39-0800",
            "2020-08-11T05:54:39+0000"
        ]
        strings.forEach { string in
            XCTAssertEqual(OWSHttpHeaders.parseRetryAfterHeaderValue(string), Date.ows_parseFromISO8601String(string)!)
        }
    }

    // Verifies that double retry-after values are parsed as a delay from the current time
    func testDelayRetryAfter() {
        let delayStrings = [
            "1",
            "2",
            "1.001",
            "120",
            "1200.0",
            "1200.1",
            "86400.000",
            "   86400.000    ",
            " \t  \t86400.000\t  \t  "
        ]
        delayStrings.forEach { (string) in
            let date = OWSHttpHeaders.parseRetryAfterHeaderValue(string)
            XCTAssertEqual(
                date!.timeIntervalSinceNow,
                Double(string.trimmingCharacters(in: .whitespacesAndNewlines))!,
                accuracy: 0.1)
        }
    }

    // Verifies that if we can't parse a retry-after string, we'll default to 60s
    func testInvalidRetryAfter() {
        let invalidStrings = [
            "8/11/1994 01:02:03",
            "blahhh",
            "one",
            "soon",
            "later"
        ]
        invalidStrings.forEach { (string) in
            let date = OWSHttpHeaders.parseRetryAfterHeaderValue(string)
            XCTAssertEqual(date!.timeIntervalSinceNow, 60, accuracy: 0.1)
        }
    }

    func testEmptyRetryAfter() {
        XCTAssertNil(OWSHttpHeaders.parseRetryAfterHeaderValue(nil))
        XCTAssertNil(OWSHttpHeaders.parseRetryAfterHeaderValue(""))
        XCTAssertNil(OWSHttpHeaders.parseRetryAfterHeaderValue("      "))
        XCTAssertNil(OWSHttpHeaders.parseRetryAfterHeaderValue("\n"))
    }
}
