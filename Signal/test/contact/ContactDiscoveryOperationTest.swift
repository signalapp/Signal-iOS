//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit

class ContactDiscoveryOperationTest: SignalBaseTest {
    func test_boolArrayFromEmptyData() {
        let data = Data()
        let bools = CDSBatchOperation.boolArray(from: data)
        XCTAssert(bools == [])
    }

    func test_boolArrayFromFalseBytes() {
        let data = Data(repeating: 0x00, count: 4)
        let bools = CDSBatchOperation.boolArray(from: data)
        XCTAssert(bools == [false, false, false, false])
    }

    func test_boolArrayFromTrueBytes() {
        let data = Data(repeating: 0x01, count: 4)
        let bools = CDSBatchOperation.boolArray(from: data)
        XCTAssert(bools == [true, true, true, true])
    }

    func test_boolArrayFromMixedBytes() {
        let data = Data([0x01, 0x00, 0x01, 0x01])
        let bools = CDSBatchOperation.boolArray(from: data)
        XCTAssert(bools == [true, false, true, true])
    }

    func test_encodeNumber() {
        let phoneNumbers = [ "+1011" ]
        let actual = try! CDSBatchOperation.encodePhoneNumbers(phoneNumbers)
        let expected: Data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xf3])

        XCTAssertEqual(expected, actual)
    }

    func test_encodeMultipleNumber() {
        let phoneNumbers = [ "+1011", "+15551231234"]
        let actual = try! CDSBatchOperation.encodePhoneNumbers(phoneNumbers)
        let expected: Data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xf3,
                                   0x00, 0x00, 0x00, 0x03, 0x9e, 0xec, 0xf5, 0x02])

        XCTAssertEqual(expected, actual)
    }
}
