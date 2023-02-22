//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

class ContactDiscoveryE164CollectionTest: XCTestCase {
    func test_encodeNumber() throws {
        let phoneNumbers = [try XCTUnwrap(E164("+1011"))]
        let actual = ContactDiscoveryE164Collection(phoneNumbers).encodedValues
        let expected: Data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xf3])

        XCTAssertEqual(expected, actual)
    }

    func test_encodeMultipleNumber() throws {
        let phoneNumbers = [ try XCTUnwrap(E164("+1011")), try XCTUnwrap(E164("+19875550123")) ]
        let actual = ContactDiscoveryE164Collection(phoneNumbers).encodedValues
        let expected: Data = Data([
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xf3,
            0x00, 0x00, 0x00, 0x04, 0xa0, 0xac, 0xd3, 0xab
        ])
        XCTAssertEqual(expected, actual)
    }
}
