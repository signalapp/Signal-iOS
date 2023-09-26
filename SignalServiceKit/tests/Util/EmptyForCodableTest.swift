//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class EmptyForCodableTest: XCTestCase {
    private enum SharedCodingKeys: String, CodingKey {
        case prop1
        case prop2
        case prop3
        case prop4
    }

    private struct RegularCodable: Codable {
        private typealias CodingKeys = SharedCodingKeys

        var prop1: String
        var prop2: Bool
        var prop3: [String: String]
        var prop4: [String: String]
    }

    private struct EmptyCodable: Codable {
        private typealias CodingKeys = SharedCodingKeys

        var prop1: String
        var prop2: Bool
        var prop3: [String: String]
        @EmptyForCodable var prop4: [String: String]
    }

    func testEncodesAsEmpty() throws {
        let structToEncode = EmptyCodable(
            prop1: "whirlyball",
            prop2: true,
            prop3: ["great": "sport", "much": "fun"],
            prop4: ["kinda": "jarring", "still": "fun"]
        )

        let encoded = try JSONEncoder().encode(structToEncode)

        let decodedStruct = try JSONDecoder().decode(RegularCodable.self, from: encoded)

        XCTAssertEqual(decodedStruct.prop1, "whirlyball")
        XCTAssertEqual(decodedStruct.prop2, true)
        XCTAssertEqual(decodedStruct.prop3, ["great": "sport", "much": "fun"])
        XCTAssertEqual(decodedStruct.prop4, [:])
    }

    func testDecodesExistingAsEmpty() throws {
        let structToEncode = RegularCodable(
            prop1: "whirlyball",
            prop2: true,
            prop3: ["great": "sport", "much": "fun"],
            prop4: ["kinda": "jarring", "still": "fun"]
        )

        let encoded = try JSONEncoder().encode(structToEncode)

        let decodedAsRegular = try JSONDecoder().decode(RegularCodable.self, from: encoded)
        let decodedAsEmpty = try JSONDecoder().decode(EmptyCodable.self, from: encoded)

        XCTAssertEqual(decodedAsRegular.prop1, "whirlyball")
        XCTAssertEqual(decodedAsRegular.prop2, true)
        XCTAssertEqual(decodedAsRegular.prop3, ["great": "sport", "much": "fun"])
        XCTAssertEqual(decodedAsRegular.prop4, ["kinda": "jarring", "still": "fun"])

        XCTAssertEqual(decodedAsEmpty.prop1, "whirlyball")
        XCTAssertEqual(decodedAsEmpty.prop2, true)
        XCTAssertEqual(decodedAsEmpty.prop3, ["great": "sport", "much": "fun"])
        XCTAssertEqual(decodedAsEmpty.prop4, [:])
    }
}

extension Dictionary: EmptyInitializable {}
