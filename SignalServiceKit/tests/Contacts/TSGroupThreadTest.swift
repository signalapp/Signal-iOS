//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class TSGroupThreadTest: XCTestCase {
    func testHasSafetyNumbers() throws {
        let groupThread = try TSGroupThread(dictionary: [:])
        XCTAssertFalse(groupThread.hasSafetyNumbers())
    }
}
