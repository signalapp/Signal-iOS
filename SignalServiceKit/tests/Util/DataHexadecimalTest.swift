//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

final class DataHexadecimalTest: XCTestCase {

    func testFromHex() {
        XCTAssertEqual(Data([0x1A]), Data(hex: "1A"))
        XCTAssertEqual(Data([0x1A, 0x2B, 0x3C, 0x4D, 0x5E, 0x6F]), Data(hex: "1A2B3C4D5E6F"))
        XCTAssertNil(Data(hex: "FOO"))
        XCTAssertNil(Data(hex: "1"))
        XCTAssertEqual(Data([0]), Data(hex: "00"))
        XCTAssertEqual(Data([255]), Data(hex: "FF"))
        XCTAssertEqual(Data([255, 254, 253, 252, 251, 250, 249, 248]), Data(hex: "fffefdfcfbfaf9f8"))
        XCTAssertEqual(Data(), Data(hex: ""))
        XCTAssertNil(Data(hex: "-0"))
        XCTAssertNil(Data(hex: "+0"))
        XCTAssertNil(Data(hex: "-00"))
        XCTAssertNil(Data(hex: "+00"))
        XCTAssertNil(Data(hex: "12+3"))
        XCTAssertNil(Data(hex: "45-6"))
    }

    func testToHex() {
        XCTAssertEqual("1a", Data([0x1A]).hexadecimalString)
        XCTAssertEqual("1a2b3c4d5e6f", Data([0x1A, 0x2B, 0x3C, 0x4D, 0x5E, 0x6F]).hexadecimalString)
        XCTAssertEqual("00", Data([0]).hexadecimalString)
        XCTAssertEqual("ff", Data([255]).hexadecimalString)
        XCTAssertEqual("", Data().hexadecimalString)
        XCTAssertEqual("fffefdfcfbfaf9f8", Data([255, 254, 253, 252, 251, 250, 249, 248]).hexadecimalString)
    }

    func testRoundTripRandomStrings() {
        let table: [Character] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f"]

        let trials = 100
        for _ in 0..<trials {
            let byteLength = UInt8.random(in: .min ... .max)
            var s = ""
            for _ in 0..<byteLength {
                let v = UInt8.random(in: .min ... .max)
                let hi = Int(v / 16)
                let lo = Int(v % 16)
                s.append(table[hi])
                s.append(table[lo])
            }

            let d = Data(hex: s)
            XCTAssertNotNil(d)
            XCTAssertEqual(s, d!.hexadecimalString)
        }
    }
}
