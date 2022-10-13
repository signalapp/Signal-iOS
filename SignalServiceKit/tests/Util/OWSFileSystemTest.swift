//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
