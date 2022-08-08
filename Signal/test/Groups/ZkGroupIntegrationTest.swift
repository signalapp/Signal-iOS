//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
@testable import Signal

class ZkGroupIntegrationTest: SignalBaseTest {
    func testServerParamsAreUpToDate() {
        XCTAssertNoThrow(try GroupsV2Protos.serverPublicParams(),
                         "The zkgroup server public parameters have changed!")
    }
}
