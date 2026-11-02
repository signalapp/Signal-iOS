//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct OWSLocalizedStringTest {
    @Test
    func testNonPluralLocalizedStringWithFormat() {
        #expect(String.nonPluralLocalizedStringWithFormat("") == "")
        #expect(String.nonPluralLocalizedStringWithFormat("A B C") == "A B C")
        #expect(String.nonPluralLocalizedStringWithFormat("A %@ B %@ C", "1", "2") == "A 1 B 2 C")
        #expect(String.nonPluralLocalizedStringWithFormat("A %@ %% %d C", "1", "2") == "A 1 % 2 C")
        #expect(String.nonPluralLocalizedStringWithFormat("A %1$@ B %1$@ C", "1", "2") == "A 1 B 1 C")
        #expect(String.nonPluralLocalizedStringWithFormat("A %2$d B %1$@ C", "1", "2") == "A 2 B 1 C")
    }
}
