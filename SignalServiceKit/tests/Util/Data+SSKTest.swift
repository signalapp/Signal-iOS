//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import XCTest

@testable import SignalServiceKit

class DataSSKTests: XCTestCase {
    func testUUID() {
        let dataValue = Data(0...16)
        let testCases: [(String, Data)] = [
            ("00010203-0405-0607-0809-0A0B0C0D0E0F", dataValue),
            // Test an unaligned load
            ("01020304-0506-0708-090A-0B0C0D0E0F10", dataValue.dropFirst())
        ]
        for (expectedValue, uuidData) in testCases {
            XCTAssertEqual(UUID(data: uuidData)?.uuidString, expectedValue)
            let tupleResult = UUID.from(data: uuidData)
            XCTAssertEqual(tupleResult?.0.uuidString, expectedValue)
            XCTAssertEqual(tupleResult?.1, 16)
        }
    }
}
