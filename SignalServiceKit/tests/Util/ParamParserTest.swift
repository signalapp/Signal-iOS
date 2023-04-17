//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

import SignalServiceKit

class ParamParserTest: XCTestCase {
    let dict: [String: Any] = ["some_int": 11, "some_string": "asdf", "large_int": Int64.max, "negative_int": -10]
    var parser: ParamParser {
        return ParamParser(dictionary: dict)
    }

    func testExample() {
        XCTAssertEqual(11, try parser.required(key: "some_int"))
        XCTAssertEqual(11, try parser.optional(key: "some_int"))

        let expectedString: String = "asdf"
        XCTAssertEqual(expectedString, try parser.required(key: "some_string"))
        XCTAssertEqual(expectedString, try parser.optional(key: "some_string"))

        XCTAssertEqual(nil, try parser.optional(key: "does_not_exist") as String?)
        XCTAssertThrowsError(try parser.required(key: "does_not_exist") as String)
    }

    func testCastingFailures() {
        // Required
        do {
            let _: Int = try parser.required(key: "some_string")
            XCTFail("Expected last statement to throw")
        } catch ParamParser.ParseError.invalidFormat(let key, let description) {
            XCTAssertEqual(key, "some_string")
            XCTAssertNotNil(description, "Expected description string explaining failed cast")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // Optional
        do {
            let _: Int? = try parser.optional(key: "some_string")
            XCTFail("Expected last statement to throw")
        } catch ParamParser.ParseError.invalidFormat(let key, let description) {
            XCTAssertEqual(key, "some_string")
            XCTAssertNotNil(description, "Expected description string explaining failed cast")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNumeric() {
        let expectedInt32: Int32 = 11
        XCTAssertEqual(expectedInt32, try parser.required(key: "some_int"))
        XCTAssertEqual(expectedInt32, try parser.optional(key: "some_int"))

        let expectedInt64: Int64 = 11
        XCTAssertEqual(expectedInt64, try parser.required(key: "some_int"))
        XCTAssertEqual(expectedInt64, try parser.optional(key: "some_int"))
    }

    func testNumericSizeFailures() {
        XCTAssertThrowsError(try {
            let _: Int32 = try parser.required(key: "large_int")
        }())

        XCTAssertThrowsError(try {
            let _: Int32? = try parser.optional(key: "large_int")
        }())

        XCTAssertNoThrow(try {
            let _: Int64 = try parser.required(key: "large_int")
        }())
    }

    func testNumericSignFailures() {
        XCTAssertNoThrow(try {
            let _: Int = try parser.required(key: "negative_int")
        }())

        XCTAssertNoThrow(try {
            let _: Int64 = try parser.required(key: "negative_int")
        }())

        XCTAssertThrowsError(try {
            let _: UInt64 = try parser.required(key: "negative_int")
        }())
    }

    func testUUID() {
        let uuid = UUID()
        let parser = ParamParser(dictionary: ["uuid": uuid.uuidString])

        XCTAssertEqual(uuid, try parser.required(key: "uuid"))
        XCTAssertEqual(uuid, try parser.optional(key: "uuid"))

        XCTAssertNil(try parser.optional(key: "nope") as UUID?)
        XCTAssertThrowsError(try parser.required(key: "nope") as UUID?)
    }

    func testUUIDFormatFailure() {
        XCTAssertThrowsError(try {
            let parser = ParamParser(dictionary: ["uuid": ""])
            let _: UUID = try parser.required(key: "uuid")
        }())

        XCTAssertThrowsError(try {
            let parser = ParamParser(dictionary: ["uuid": "not-a-uuid"])
            let _: UUID = try parser.required(key: "uuid")
        }())

        XCTAssertThrowsError(try {
            let parser = ParamParser(dictionary: ["uuid": 0])
            let _: UUID = try parser.required(key: "uuid")
        }())
    }

    // MARK: Base64EncodedData

    func testBase64Data_Valid() {
        let originalString = "asdf"
        let utf8Data: Data = originalString.data(using: .utf8)!
        let base64EncodedString = utf8Data.base64EncodedString()

        let dict: [String: Any] = ["some_data": base64EncodedString]
        let parser = ParamParser(dictionary: dict)

        XCTAssertEqual(utf8Data, try parser.requiredBase64EncodedData(key: "some_data"))
        XCTAssertEqual(utf8Data, try parser.optionalBase64EncodedData(key: "some_data"))

        let data: Data = try! parser.requiredBase64EncodedData(key: "some_data")
        let roundTripString = String(data: data, encoding: .utf8)
        XCTAssertEqual(originalString, roundTripString)
    }

    func testBase64Data_EmptyString() {
        let dict: [String: Any] = ["some_data": ""]
        let parser = ParamParser(dictionary: dict)

        XCTAssertThrowsError(try parser.requiredBase64EncodedData(key: "some_data"))
        XCTAssertEqual(nil, try parser.optionalBase64EncodedData(key: "some_data"))
    }

    func testBase64Data_NSNull() {
        let dict: [String: Any] = ["some_data": NSNull()]
        let parser = ParamParser(dictionary: dict)

        XCTAssertThrowsError(try parser.requiredBase64EncodedData(key: "some_data"))
        XCTAssertEqual(nil, try parser.optionalBase64EncodedData(key: "some_data"))
    }

    func testBase64Data_Invalid() {
        // invalid base64 data
        let base64EncodedString = "YXNkZg"

        let dict: [String: Any] = ["some_data": base64EncodedString]
        let parser = ParamParser(dictionary: dict)

        XCTAssertThrowsError(try parser.requiredBase64EncodedData(key: "some_data"))
        XCTAssertThrowsError(try parser.optionalBase64EncodedData(key: "some_data"))
    }
}
