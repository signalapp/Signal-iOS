//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class DateOWSTests: XCTestCase {

    func testValidHTTPDateParsing() {
        let validTestCases = [
            (string: "Thu, 01 Jan 1970 00:00:00 GMT", date: NSDate(timeIntervalSince1970: 0)),
            (string: "Wed, 21 Oct 2015 07:28:00 GMT", date: NSDate(timeIntervalSince1970: 1445412480)),
            (string: "Wed, 21 Oct 2015 07:28:01 GMT", date: NSDate(timeIntervalSince1970: 1445412481)),
            (string: "Thu, 22 Oct 2015 07:28:00 GMT", date: NSDate(timeIntervalSince1970: 1445498880)),
            (string: "Thu, 22 Oct 2015 07:28:01 GMT", date: NSDate(timeIntervalSince1970: 1445498881)),
            (string: "Tue, 11 Aug 2020 05:54:39 GMT", date: NSDate(timeIntervalSince1970: 1597125279)),

            // Most whitespace should be handled
            (string: "   Tue,     11      Aug     2020   05:  54:  39     GMT   ", date: NSDate(timeIntervalSince1970: 1597125279)),
            (string: "\n\tTue, \n\t11 Aug \t\t     2020 \n  \t  05:  \n\t54:39       GMT", date: NSDate(timeIntervalSince1970: 1597125279))
        ]

        validTestCases.forEach { (string, date) -> Void in
            let parsedDate = NSDate.ows_parseFromHTTPDateString(string)
            XCTAssertEqual(parsedDate, date)
        }
    }

    func testValidISO8601DateParsing() {
        let validTestCases = [
            (string: "1970-01-01T00:00:00+0000", date: NSDate(timeIntervalSince1970: 0)),
            (string: "1969-12-31T16:00:00-0800", date: NSDate(timeIntervalSince1970: 0)),
            (string: "2015-10-21T07:28:00+0000", date: NSDate(timeIntervalSince1970: 1445412480)),
            (string: "2015-10-20T023:28:00-0800", date: NSDate(timeIntervalSince1970: 1445412480)),
            (string: "2015-10-21T07:28:01+0000", date: NSDate(timeIntervalSince1970: 1445412481)),
            (string: "2015-10-22T07:28:00+0000", date: NSDate(timeIntervalSince1970: 1445498880)),
            (string: "2015-10-22T07:28:01+0000", date: NSDate(timeIntervalSince1970: 1445498881)),
            (string: "2020-08-10T21:54:39-0800", date: NSDate(timeIntervalSince1970: 1597125279)),
            (string: "2020-08-11T05:54:39+0000", date: NSDate(timeIntervalSince1970: 1597125279)),

            // Most whitespace should be handled
            (string: "  2020  - 08 - 10T21  :  54  :39   -0800  ", date: NSDate(timeIntervalSince1970: 1597125279)),
            (string: "  \n\t2020\t -\n08-\t10T21:\n54\n:39\t\t -0800\n\t", date: NSDate(timeIntervalSince1970: 1597125279))
        ]

        validTestCases.forEach { (string, date) -> Void in
            let parsedDate = NSDate.ows_parseFromISO8601String(string)
            XCTAssertEqual(parsedDate, date)
        }
    }
}
