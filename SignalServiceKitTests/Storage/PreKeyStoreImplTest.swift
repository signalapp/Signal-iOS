//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing

@testable import SignalServiceKit

struct PreKeyStoreImplTest {
    @Test
    func testGenerate() {
        let preKeys = PreKeyStoreImpl.generatePreKeyRecords(forPreKeyIds: 2...3)
        #expect(preKeys.count == 2)
        #expect(preKeys[0].id == 2)
        #expect(preKeys[1].id == 3)
    }
}
