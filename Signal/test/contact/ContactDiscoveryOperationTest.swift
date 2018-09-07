//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import SignalServiceKit

class ContactDiscoveryOperationTest: SignalBaseTest {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    func tesBoolArrayFromEmptyData() {
        let data = Data()
        let bools = CDSBatchOperation.boolArray(data: data)
        XCTAssert(bools == [])
    }

    func testBoolArrayFromFalseByte() {
        let data = Data(repeating: 0x00, count: 4)
        let bools = CDSBatchOperation.boolArray(data: data)
        XCTAssert(bools == [false, false, false, false])
    }

    func testBoolArrayFromTrueByte() {
        let data = Data(repeating: 0x01, count: 4)
        let bools = CDSBatchOperation.boolArray(data: data)
        XCTAssert(bools == [true, true, true, true])
    }

    func testBoolArrayFromMixedBytes() {
        let data = Data(bytes: [0x01, 0x00, 0x01, 0x01])
        let bools = CDSBatchOperation.boolArray(data: data)
        XCTAssert(bools == [true, false, true, true])
    }

    func testEncodeNumber() {
        let recipientIds = [ "+1011" ]
        let actual = try! CDSBatchOperation.encodePhoneNumbers(recipientIds: recipientIds)
        let expected: Data = Data(bytes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xf3])

        XCTAssertEqual(expected, actual)
    }

    func testEncodeMultipleNumber() {
        let recipientIds = [ "+1011", "+15551231234"]
        let actual = try! CDSBatchOperation.encodePhoneNumbers(recipientIds: recipientIds)
        let expected: Data = Data(bytes: [0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xf3,
                                          0x00, 0x00, 0x00, 0x03, 0x9e, 0xec, 0xf5, 0x02])

        XCTAssertEqual(expected, actual)
    }
}
