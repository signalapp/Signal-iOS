//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import Testing

struct IntTest {
    @Test
    func testSafeCast() {
        _ = Int64(safeCast: UInt32.max)
        _ = Int64(safeCast: UInt16.max)
        _ = Int64(safeCast: UInt8.max)

        // This is least safe of the safe casts, though it would require
        // UInt.bitWidth to be larger than UInt64.bitWidth. That's not currently a
        // thing, and it seems unlikely to change in the foreseeable future.
        _ = UInt64(safeCast: UInt.max)
    }
}

struct UInt64Test {
    @Test(arguments: [
        (-5.0, 0),
        (42.7, 42),
        (1e30, .max),
        (.nan, 0),
        (.infinity, .max),
    ])
    func testDoubleClamp(double: Double, clamped: UInt64) async throws {
        #expect(UInt64(clamping: double) == clamped)
    }
}
