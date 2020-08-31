//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit

#if BROKEN_TESTS

class ContactDiscoveryOperationTest: SignalBaseTest {
    func test_uuidArrayFromEmptyData() {
        let data = Data()
        let uuids = CDSBatchOperation.uuidArray(from: data)
        XCTAssertEqual([], uuids)
    }

    func test_uuidArrayFromZeroBytes() {
        let data = Data(repeating: 0x00, count: 16)
        let uuids = CDSBatchOperation.uuidArray(from: data)
        XCTAssertEqual([UUID(uuidString: "00000000-0000-0000-0000-000000000000")], uuids)
    }

    func test_uuidArrayFromBytes() {
        let bytes: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10
        ]
        let data = Data(bytes)
        let uuids = CDSBatchOperation.uuidArray(from: data)
        let expected = [UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
                        UUID(uuidString: "00000000-0000-0000-0000-000000000000"),
                        UUID(uuidString: "01020304-0506-0708-090A-0B0C0D0E0F10")]
        XCTAssertEqual(expected, uuids)
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

#endif
