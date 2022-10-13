//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class OWSFormatTest: SSKBaseTestSwift {

    func testTimeIntervals() throws {
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 0), "0:00")
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 0.4), "0:00")
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 0.6), "0:00")
        XCTAssertEqual(OWSFormat.localizedDurationString(from: 0.999), "0:00")
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

    func testFileSizes() throws {
        let kb: Int64 = 1000
        let mb: Int64 = 1000 * kb
        let gb: Int64 = 1000 * mb
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: 0), "Zero KB")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: 1), "1 byte")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: 60), "60 bytes")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: 1*kb), "1 KB")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: Int64(3.3*Double(kb))), "3 KB")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: Int64(13.5*Double(kb))), "14 KB")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: 100*kb), "100 KB")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: 1*mb), "1 MB")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: Int64(4.32*Double(mb))), "4.3 MB")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: 111*mb), "111 MB")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: 1*gb), "1 GB")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: Int64(2.34*Double(gb))), "2.34 GB")
        XCTAssertEqual(OWSFormat.localizedFileSizeString(from: 56*gb), "56 GB")
    }
}
