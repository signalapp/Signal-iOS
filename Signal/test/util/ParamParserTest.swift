//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import XCTest

class ParamParserTest: XCTestCase {

    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }

    let dict: [String: Any] = ["some_int": 11, "some_string": "asdf", "large_int": Int64.max, "negative_int": -10]
    var parser: ParamParser {
        return ParamParser(dictionary: dict)
    }

    func testExample() {
        XCTAssertEqual(11, try parser.require(key: "some_int"))
        XCTAssertEqual(11, try parser.allow(key: "some_int"))

        let expectedString: String = "asdf"
        XCTAssertEqual(expectedString, try parser.require(key: "some_string"))
        XCTAssertEqual(expectedString, try parser.allow(key: "some_string"))

        XCTAssertEqual(nil, try parser.allow(key: "does_not_exist") as String?)
        XCTAssertThrowsError(try parser.require(key: "does_not_exist") as String)
    }

    func testNumeric() {
        let expectedInt32: Int32 = 11
        XCTAssertEqual(expectedInt32, try parser.require(key: "some_int"))
        XCTAssertEqual(expectedInt32, try parser.allow(key: "some_int"))

        let expectedInt64: Int64 = 11
        XCTAssertEqual(expectedInt64, try parser.require(key: "some_int"))
        XCTAssertEqual(expectedInt64, try parser.allow(key: "some_int"))
    }

    func testNumericSizeFailures() {
        XCTAssertThrowsError(try {
            let _: Int32 = try parser.require(key: "large_int")
        }())

        XCTAssertThrowsError(try {
            let _: Int32? = try parser.allow(key: "large_int")
        }())

        XCTAssertNoThrow(try {
            let _: Int64 = try parser.require(key: "large_int")
        }())
    }

    func testNumericSignFailures() {
        XCTAssertNoThrow(try {
            let _: Int = try parser.require(key: "negative_int")
        }())

        XCTAssertNoThrow(try {
            let _: Int64 = try parser.require(key: "negative_int")
        }())

        XCTAssertThrowsError(try {
            let _: UInt64 = try parser.require(key: "negative_int")
        }())
    }

    func testBase64Data() {
        let originalString = "asdf"
        let utf8Data: Data = originalString.data(using: .utf8)!
        let base64EncodedString = utf8Data.base64EncodedString()

        let dict: [String: Any] = ["some_data": base64EncodedString]
        let parser = ParamParser(dictionary: dict)

        XCTAssertEqual(utf8Data, try parser.requireBase64EncodedData(key: "some_data"))
        XCTAssertEqual(utf8Data, try parser.allowBase64EncodedData(key: "some_data"))

        let data: Data = try! parser.requireBase64EncodedData(key: "some_data")
        let roundTripString = String(data: data, encoding: .utf8)
        XCTAssertEqual(originalString, roundTripString)
    }
}
