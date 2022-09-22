//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import SignalServiceKit

class OWSFileSystemTest: XCTestCase {
    private class MockFileManager: FileManagerProtocol {
        public var attributesOfFileSystemHandler: (String) throws -> [FileAttributeKey: Any] = { _ in
            [:]
        }
        func attributesOfFileSystem(forPath path: String) throws -> [FileAttributeKey: Any] {
            try attributesOfFileSystemHandler(path)
        }
    }

    func testFreeSpaceInBytes() throws {
        let fileManager = MockFileManager()
        fileManager.attributesOfFileSystemHandler = { _ in
            [.systemFreeSize: NSNumber(value: 1234)]
        }

        let result = try XCTUnwrap(
            OWSFileSystem.freeSpaceInBytes(forPath: "/tmp", fileManager: fileManager)
        )

        XCTAssertEqual(result, 1234)
    }
}
