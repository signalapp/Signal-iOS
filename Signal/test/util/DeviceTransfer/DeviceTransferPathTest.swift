//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

final class DeviceTransferPathTest: XCTestCase {
    private var temporaryDirectory: URL!
    private var baseDirectory: URL {
        temporaryDirectory.appendingPathComponent("device-transfer", isDirectory: true)
    }

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true,
        )
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testValidRelativePath() throws {
        XCTAssertEqual(
            try DeviceTransferService.validatedPath(
                for: "Attachments/uuid/file.dat",
                within: baseDirectory,
            ),
            baseDirectory
                .appendingPathComponent("Attachments/uuid/file.dat")
                .resolvingSymlinksInPath()
                .path,
        )
    }

    func testRejectsInvalidPaths() {
        for path in ["", ".", "..", "../outside", "directory/../../outside", "/tmp/outside"] {
            XCTAssertThrowsError(
                try DeviceTransferService.validatedPath(for: path, within: baseDirectory),
                "Expected path to be rejected: \(path)",
            )
        }
    }

    func testAllowsNormalizedPathWithinBaseDirectory() throws {
        XCTAssertEqual(
            try DeviceTransferService.validatedPath(
                for: "Attachments/../file.dat",
                within: baseDirectory,
            ),
            baseDirectory
                .appendingPathComponent("file.dat")
                .resolvingSymlinksInPath()
                .path,
        )
    }

    func testRejectsPathThroughSymlinkOutsideBaseDirectory() throws {
        let outsideDirectory = temporaryDirectory.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outsideDirectory,
            withIntermediateDirectories: true,
        )
        try FileManager.default.createSymbolicLink(
            at: baseDirectory.appendingPathComponent("link"),
            withDestinationURL: outsideDirectory,
        )

        XCTAssertThrowsError(
            try DeviceTransferService.validatedPath(
                for: "link/file.dat",
                within: baseDirectory,
            ),
        )
    }
}
