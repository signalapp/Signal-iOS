//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest
@testable import SignalServiceKit

final class AppVersionTests: XCTestCase {
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
            ("6.0.0.0", "5.35.1.2", .orderedDescending),

            ("junk", "otherjunk", .orderedSame),
            ("0.foo.0", "0.0.0", .orderedSame),
            ("1.foo.0", "2.bar.0", .orderedAscending),
            ("1.1", "1.foo", .orderedDescending),
            ("1.0", "1.-2", .orderedSame)
        ]

        testCases.forEach { (lhs, rhs, expected) in
            let lCompR = AppVersionImpl.shared.compare(lhs, with: rhs)
            XCTAssertEqual(lCompR, expected, "\(lhs) compared with \(rhs)")

            let rCompL = AppVersionImpl.shared.compare(rhs, with: lhs)
            XCTAssertEqual(rCompL, expected.inverted, "\(rhs) compared with \(lhs)")
        }
    }
}

private extension ComparisonResult {
    var inverted: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedSame: return .orderedSame
        case .orderedDescending: return .orderedAscending
        }
    }
}
