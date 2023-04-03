//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import SignalServiceKit

final class AccountDataReportTest: XCTestCase {
    func testWithValidData() throws {
        let rawData = "{\"foo\":\"bar\", \"text\": \"baz\"}".data(using: .ascii)!
        let report = try XCTUnwrap(AccountDataReport(rawData: rawData))

        let parsedJson = try {
            let jsonValue = try JSONSerialization.jsonObject(with: report.formattedJsonData)
            return jsonValue as! [String: String]
        }()
        XCTAssertEqual(parsedJson, ["foo": "bar", "text": "baz"])
        XCTAssertEqual(report.textData, "baz".data(using: .ascii)!)
    }

    func testWithValidDataButNoText() throws {
        let rawData = "{\"foo\": \"bar\"}".data(using: .ascii)!
        let report = try XCTUnwrap(AccountDataReport(rawData: rawData))

        XCTAssertEqual(report.formattedJsonData, "{\n  \"foo\" : \"bar\"\n}".data(using: .ascii)!)
        XCTAssertNil(report.textData)
    }

    func testWithValidDataButNonstringText() throws {
        let jsonStrings: [String] = [
            "{}",
            "{\"missing\": \"text field\"}",
            "{\"text\": null}",
            "{\"text\": 123}",
            "{\"TEXT\": \"should be ignored\"}"
        ]

        for jsonString in jsonStrings {
            let rawData = jsonString.data(using: .ascii)!
            let report = try XCTUnwrap(AccountDataReport(rawData: rawData))

            XCTAssertNil(report.textData)
        }
    }

    func testWithInvalidData() {
        let rawDatas: [Data] = [
            Data(),
            Data([1, 2, 3]),
            "\"not an object\"".data(using: .ascii)!,
            "[\"not an object\"]".data(using: .ascii)!,
            "{ \"foo\":".data(using: .ascii)!
        ]

        for rawData in rawDatas {
            XCTAssertThrowsError(try AccountDataReport(rawData: rawData))
        }
    }
}
