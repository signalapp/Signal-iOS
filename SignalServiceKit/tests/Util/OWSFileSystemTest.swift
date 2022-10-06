//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class OWSFileSystemTest: XCTestCase {
    func testFreeSpaceInBytes() throws {
        let path = URL(fileURLWithPath: "/tmp")
        let result = try XCTUnwrap(OWSFileSystem.freeSpaceInBytes(forPath: path))
        XCTAssertGreaterThan(result, 1)
    }
}
