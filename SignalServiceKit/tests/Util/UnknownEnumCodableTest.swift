//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import XCTest

public class UnknownEnumCodableTest: XCTestCase {

    enum StringEnum: String, UnknownEnumCodable {
        case first
        case second
        case unknown
    }

    func test_unknownStringEnum() throws {
        let cases: [String: StringEnum] = [
            "\"first\"": .first,
            "\"second\"": .second,
            "\"unknown\"": .unknown,
            "\"whatever\"": .unknown,
            "\"\"": .unknown
        ]
        let decoder = JSONDecoder()
        for (raw, expected) in cases {
            let parsed = try decoder.decode(StringEnum.self, from: raw.data(using: .utf8)!)
            XCTAssertEqual(parsed, expected)
        }
    }

    enum IntEnum: Int, UnknownEnumCodable {
        case hundo = 100
        case life = 42
        case unknown = -1
    }

    func test_unknownIntEnum() throws {
        let cases: [String: IntEnum] = [
            "100": .hundo,
            "42": .life,
            "-1": .unknown,
            "333": .unknown,
            "0": .unknown
        ]
        let decoder = JSONDecoder()
        for (raw, expected) in cases {
            let parsed = try decoder.decode(IntEnum.self, from: raw.data(using: .utf8)!)
            XCTAssertEqual(parsed, expected)
        }
    }
}
