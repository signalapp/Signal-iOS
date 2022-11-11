//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import Signal

class ZkGroupIntegrationTest: SignalBaseTest {
    func testServerParamsAreUpToDate() {
        XCTAssertNoThrow(try GroupsV2Protos.serverPublicParams(),
                         "The zkgroup server public parameters have changed!")
    }
}
