//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import Testing
@testable import Signal

struct DisplayableAccountEntropyPoolTest {
    private static let aepLength = AccountEntropyPool.Constants.byteLength

    private let rawString = "0o0ooaa" + String(repeating: "a", count: Self.aepLength - 7)
    private var aep: AccountEntropyPool { try! AccountEntropyPool(key: rawString) }
    private let expectedDisplayString = "=#=##AA" + String(repeating: "A", count: Self.aepLength - 7)

    @Test
    func displayString_filters() {
        let display = DisplayableAccountEntropyPool(aep: aep)

        #expect(display.rawValue == aep)
        #expect(display.displayString == expectedDisplayString)
    }

    @Test
    func displayString_constructs() throws {
        let display = try DisplayableAccountEntropyPool(
            displayString: "=#0oOaA" + String(repeating: "a", count: Self.aepLength - 7),
        )

        #expect(display.rawValue == aep)
        #expect(display.displayString == expectedDisplayString)
    }
}
