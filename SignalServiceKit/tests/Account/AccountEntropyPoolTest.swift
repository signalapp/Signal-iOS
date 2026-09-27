//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct AccountEntropyPoolTest {
    @Test
    func testDeprecated() throws {
        let encodedValue = #"{"rawData":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}"#
        let decodedValue = try JSONDecoder().decode(DeprecatedAccountEntropyPool.self, from: Data(encodedValue.utf8))
        #expect(decodedValue.wrappedValue.rawString == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    }

    @Test
    func testMalformed() throws {
        let wellFormedAep = #""aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa""#
        _ = try JSONDecoder().decode(AccountEntropyPool.self, from: Data(wellFormedAep.utf8))
        let malformedAep = #""aaaa""#
        #expect(throws: OWSGenericError.self) {
            _ = try JSONDecoder().decode(AccountEntropyPool.self, from: Data(malformedAep.utf8))
        }
    }
}
