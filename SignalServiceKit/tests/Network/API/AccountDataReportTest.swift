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

    func testWithInvalidData() {
        let rawDatas: [Data] = [
            Data(),
            Data([1, 2, 3]),
            "\"not an object\"".data(using: .ascii)!,
            "[\"not an object\"]".data(using: .ascii)!,
            "{ \"foo\":".data(using: .ascii)!,
            "{}".data(using: .ascii)!,
            "{\"missing\": \"text field\"}".data(using: .ascii)!,
            "{\"text\": null}".data(using: .ascii)!,
            "{\"text\": 123}".data(using: .ascii)!,
            "{\"TEXT\": \"should be ignored\"}".data(using: .ascii)!
        ]

        for rawData in rawDatas {
            XCTAssertThrowsError(try AccountDataReport(rawData: rawData))
        }
    }
}
