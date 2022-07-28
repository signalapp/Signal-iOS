//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class OWSAnalyticsTests: XCTestCase {
    func testOrderOfMagnitudeOf() throws {
        XCTAssertEqual(0, OWSAnalytics.orderOfMagnitude(of: -1))
        XCTAssertEqual(0, OWSAnalytics.orderOfMagnitude(of: 0))
        XCTAssertEqual(1, OWSAnalytics.orderOfMagnitude(of: 1))
        XCTAssertEqual(1, OWSAnalytics.orderOfMagnitude(of: 5))
        XCTAssertEqual(1, OWSAnalytics.orderOfMagnitude(of: 9))
        XCTAssertEqual(10, OWSAnalytics.orderOfMagnitude(of: 10))
        XCTAssertEqual(10, OWSAnalytics.orderOfMagnitude(of: 11))
        XCTAssertEqual(10, OWSAnalytics.orderOfMagnitude(of: 19))
        XCTAssertEqual(10, OWSAnalytics.orderOfMagnitude(of: 99))
        XCTAssertEqual(100, OWSAnalytics.orderOfMagnitude(of: 100))
        XCTAssertEqual(100, OWSAnalytics.orderOfMagnitude(of: 303))
        XCTAssertEqual(100, OWSAnalytics.orderOfMagnitude(of: 999))
        XCTAssertEqual(1000, OWSAnalytics.orderOfMagnitude(of: 1000))
        XCTAssertEqual(1000, OWSAnalytics.orderOfMagnitude(of: 3030))
        XCTAssertEqual(10000, OWSAnalytics.orderOfMagnitude(of: 10000))
        XCTAssertEqual(10000, OWSAnalytics.orderOfMagnitude(of: 30303))
        XCTAssertEqual(10000, OWSAnalytics.orderOfMagnitude(of: 99999))
        XCTAssertEqual(100000, OWSAnalytics.orderOfMagnitude(of: 100000))
        XCTAssertEqual(100000, OWSAnalytics.orderOfMagnitude(of: 303030))
        XCTAssertEqual(100000, OWSAnalytics.orderOfMagnitude(of: 999999))
    }
}
