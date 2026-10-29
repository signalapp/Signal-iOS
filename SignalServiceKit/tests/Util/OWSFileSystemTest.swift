//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import XCTest

class OWSFileSystemTest: XCTestCase {
    func testFreeSpaceInBytes() throws {
        let result = try OWSFileSystem.freeSpaceInBytes()
        XCTAssertGreaterThan(result, 1)
    }

    func testTemporaryFileUrlWithFileNameUsesDedicatedDirectory() throws {
        let file1 = OWSFileSystem.temporaryFileUrl(fileName: "output", fileExtension: "mp4", isAvailableWhileDeviceLocked: false)
        let file2 = OWSFileSystem.temporaryFileUrl(fileName: "output", fileExtension: "mp4", isAvailableWhileDeviceLocked: false)
        let dir1 = file1.deletingLastPathComponent()
        let dir2 = file2.deletingLastPathComponent()
        defer {
            try? FileManager.default.removeItem(at: dir1)
            try? FileManager.default.removeItem(at: dir2)
        }

        XCTAssertEqual(file1.lastPathComponent, "output.mp4")
        XCTAssertNotEqual(dir1, dir2)
        for dir in [dir1, dir2] {
            var isDirectory: ObjCBool = false
            XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDirectory))
            XCTAssertTrue(isDirectory.boolValue)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
        }
    }
}
