//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class DataSSKTests: XCTestCase {
    func testUUID() {
        let dataValue = Data(0...16)
        let testCases: [(String, Data)] = [
            ("00010203-0405-0607-0809-0A0B0C0D0E0F", dataValue),
            // Test an unaligned load
            ("01020304-0506-0708-090A-0B0C0D0E0F10", dataValue.dropFirst())
        ]
        for (expectedValue, uuidData) in testCases {
            XCTAssertEqual(UUID(data: uuidData)?.uuidString, expectedValue)
            let tupleResult = UUID.from(data: uuidData)
            XCTAssertEqual(tupleResult?.0.uuidString, expectedValue)
            XCTAssertEqual(tupleResult?.1, 16)
        }
    }

    func testFixedWidthInteger() {
        let dataValue = Data(1...9)
        let testCases: [(UInt64, Data)] = [
            // Test byte ordering and considering all bytes
            (0x01_02_03_04_05_06_07_08, dataValue),
            // Test an unaligned load
            (0x02_03_04_05_06_07_08_09, dataValue.dropFirst())
        ]
        for (expectedValue, bigEndianData) in testCases {
            XCTAssertEqual(UInt64(bigEndianData: bigEndianData), expectedValue)
            let tupleResult = UInt64.from(bigEndianData: bigEndianData)
            XCTAssertEqual(tupleResult?.0, expectedValue)
            XCTAssertEqual(tupleResult?.1, 8)
        }
    }

    func testBase64EncodedStringWithoutPadding() {
        XCTAssertEqual(Data(count: 0).base64EncodedStringWithoutPadding(), "")
        XCTAssertEqual(Data(count: 1).base64EncodedStringWithoutPadding(), "AA")
        XCTAssertEqual(Data(count: 2).base64EncodedStringWithoutPadding(), "AAA")
        XCTAssertEqual(Data(count: 3).base64EncodedStringWithoutPadding(), "AAAA")
        XCTAssertEqual(Data(count: 4).base64EncodedStringWithoutPadding(), "AAAAAA")
    }
}
