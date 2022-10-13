//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

class DataMessagePaddingTests: XCTestCase {
    func testPadding() {
        for i in 1...158 {
            XCTAssertEqual(Data(count: i).paddedMessageBody.count, 159)
        }

        for i in 159...318 {
            XCTAssertEqual(Data(count: i).paddedMessageBody.count, 319)
        }

        for i in 319...478 {
            XCTAssertEqual(Data(count: i).paddedMessageBody.count, 479)
        }
    }

    func testRandomPadding() {
        for _ in 0...1000 {
            let randomMessage = Cryptography.generateRandomBytes(501)
            let paddedMessage = randomMessage.paddedMessageBody
            XCTAssertEqual(paddedMessage.withoutPadding(), randomMessage)
        }
    }

    func testWithoutPadding() {
        let original = Data([1, 2, 3, 0x80, 4, 5, 6])
        let padded = original + [0x80] + Data(count: 99)
        XCTAssertEqual(padded.withoutPadding(), original)
    }

    func testWithoutPaddingInvalid() {
        let testCases: [Data] = [
            // No padding at all
            Data([1, 2, 3]),
            // No separator
            Data([1, 2, 3, 0, 0, 0]),
            // Non-zeroes after separator
            Data([1, 2, 3, 0x80, 4, 5, 6, 0])
        ]
        for testCase in testCases {
            XCTAssertEqual(testCase.withoutPadding(), testCase)
        }
    }
}
