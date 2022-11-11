//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import XCTest

@testable import SignalServiceKit

class FeatureFlagsTests: XCTestCase {
    /// Test that all `@objc static let` properties are fetched from `TestFlags`.
    func testAllFlags() {
        let expectedKeys = [
            "trueProperty",
            "falseProperty",
            "testableFlag"
        ]
        let actualKeys = Array(TestFlags.allFlags().keys)
        XCTAssertEqual(actualKeys.sorted(), expectedKeys.sorted())
    }

    /// Test that the correct number of properties with type `FeatureFlag` are returned.
    func testAllTestableFlags() {
        XCTAssertEqual(TestFlags.allTestableFlags().count, 1)
    }
}

class TestFlags: BaseFlags {
    @objc
    public static let trueProperty = true

    @objc
    public static let falseProperty = false

    // This can be any TestableFlag -- if this one is removed, just pick another.
    @objc
    public static let testableFlag = DebugFlags.disableMessageProcessing
}
