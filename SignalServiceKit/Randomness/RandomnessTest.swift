//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

@testable import SignalServiceKit
import XCTest

final class RandomnessTest: XCTestCase {

    func testGenerateRandomBytes() {
        let data = Randomness.generateRandomBytes(32)
        XCTAssertEqual(data.count, 32)

        // this is not technically impossible, but exceedingly unlikely to occur if the method is implemented correctly p=2^-256
        XCTAssertFalse(data.allSatisfy { $0 == 0 })

        // ensure we don't crash on this nonsense case
        let nonsense = Randomness.generateRandomBytes(0)
        XCTAssertEqual(nonsense.count, 0)

        // check that calls are returning things that are different
        // once again this is not technically impossible just highly improbable to fail with a correct implementation
        let data2 = Randomness.generateRandomBytes(16)
        XCTAssertEqual(data2.count, 16)
        let data3 = Randomness.generateRandomBytes(16)
        XCTAssertEqual(data3.count, 16)
        XCTAssertNotEqual(data2, data3)
    }
}
