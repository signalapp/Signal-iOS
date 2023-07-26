//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

class ServiceIdTest: XCTestCase {
    func testInit() {
        let uuidValue = UUID()
        XCTAssertEqual(UntypedServiceId(uuidValue).uuidValue, uuidValue)
        XCTAssertEqual(UntypedServiceId(uuidString: uuidValue.uuidString)?.uuidValue, uuidValue)
    }

    func testCodable() throws {
        let serviceId = try XCTUnwrap(UntypedServiceId(uuidString: "61C5DC1F-8198-4303-B862-9C0E81C5D8D4"))
        let expectedValue = #"{"key":"61C5DC1F-8198-4303-B862-9C0E81C5D8D4"}"#

        struct KeyedValue: Codable {
            var key: UntypedServiceId
        }

        // Decoding
        do {
            let encodedData = try XCTUnwrap(expectedValue.data(using: .utf8))
            let keyedValue = try JSONDecoder().decode(KeyedValue.self, from: encodedData)
            XCTAssertEqual(keyedValue.key, serviceId)
        }

        // Encoding
        do {
            let keyedValue = KeyedValue(key: serviceId)
            let encodedData = try JSONEncoder().encode(keyedValue)
            XCTAssertEqual(String(data: encodedData, encoding: .utf8), expectedValue)
        }
    }
}
