//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class AppVersionTests: SSKBaseTestSwift {

    func testVersionComparisons() {
        let testCases: [(String, String, ComparisonResult)] = [
            ("0", "0", .orderedSame),
            ("0", "0.0.0", .orderedSame),
            ("1", "1.0", .orderedSame),
            ("1", "1.0.0.0.0", .orderedSame),
            ("1.0.0", "1.0.0.0.0", .orderedSame),

            ("0", "1", .orderedAscending),
            ("0", "2", .orderedAscending),
            ("1", "1.1", .orderedAscending),
            ("1", "2", .orderedAscending),
            ("1", "1.0.0.0.1", .orderedAscending),
            ("1.1", "1.0.0.0.1", .orderedDescending),

            ("5.34.0.14", "5.35.1.2", .orderedAscending),
            ("5.35.0.50", "5.35.1.2", .orderedAscending),
            ("5.35.1.1", "5.35.1.2", .orderedAscending),
            ("5.35.1.2", "5.35.1.2", .orderedSame),
            ("5.35.1.3", "5.35.1.2", .orderedDescending),
            ("5.35.2.0", "5.35.1.2", .orderedDescending),
            ("5.36.0.0", "5.35.1.2", .orderedDescending),
            ("6.0.0.0", "5.35.1.2", .orderedDescending)
        ]

        testCases.forEach {
            XCTAssertEqual(AppVersion.compare($0.0, with: $0.1), $0.2)
            XCTAssertEqual(AppVersion.compare($0.1, with: $0.0), $0.2.inverted)
        }
    }
}

extension ComparisonResult {
    var inverted: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedSame: return .orderedSame
        case .orderedDescending: return .orderedAscending
        }
    }
}
