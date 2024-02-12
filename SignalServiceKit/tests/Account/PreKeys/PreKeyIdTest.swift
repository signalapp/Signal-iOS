//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class PreKeyIdTest: XCTestCase {
    func testMaximumRandomValue() {
        XCTAssertEqual(
            PreKeyId.nextPreKeyId(lastPreKeyId: 0, minimumCapacity: 0xFFFFFF),
            1
        )
    }

    func testMaximumNextValue() {
        XCTAssertEqual(
            PreKeyId.nextPreKeyId(lastPreKeyId: 0xFFFFFC, minimumCapacity: 3),
            0xFFFFFD
        )
    }

    func testWrapping() {
        XCTAssertEqual(
            PreKeyId.nextPreKeyId(lastPreKeyId: 0xFFFFFC, minimumCapacity: 4),
            1
        )
    }
}
