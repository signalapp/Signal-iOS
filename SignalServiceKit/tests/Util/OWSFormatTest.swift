//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class OWSFormatTest: SSKBaseTestSwift  {

    func testTimeIntervals() throws {
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 1), "0:01")
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 60), "1:00")
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 60+12), "1:12")
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 25*60+45), "25:45")
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 60*60-1), "59:59")
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 60*60), "1:00:00")
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 3*60*60+4*60+37), "3:04:37")
    }

    func testDecimals() throws {
        XCTAssertEqual(OWSFormat.localizedDecimalString(from: 0), "0")
        XCTAssertEqual(OWSFormat.localizedDecimalString(from: 1), "1")
        XCTAssertEqual(OWSFormat.localizedDecimalString(from: 1000), "1,000")
        XCTAssertEqual(OWSFormat.localizedDecimalString(from: 1234567), "1,234,567")

    }
}
