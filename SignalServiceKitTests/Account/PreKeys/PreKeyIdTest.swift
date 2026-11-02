//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class PreKeyIdTest: XCTestCase {
    func testMaximumRandomValue() {
        XCTAssertEqual(
            PreKeyId.nextPreKeyIds(lastPreKeyId: 0, count: 0xFFFFFF).lowerBound,
            1,
        )
    }

    func testMaximumNextValue() {
        XCTAssertEqual(
            PreKeyId.nextPreKeyIds(lastPreKeyId: 0xFFFFFC, count: 3).lowerBound,
            0xFFFFFD,
        )
    }

    func testWrapping() {
        XCTAssertEqual(
            PreKeyId.nextPreKeyIds(lastPreKeyId: 0xFFFFFC, count: 4).lowerBound,
            1,
        )
    }
}
