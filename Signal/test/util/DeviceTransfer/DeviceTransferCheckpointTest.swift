//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import Signal

class DeviceTransferCheckpointTest: XCTestCase {

    private var storage: InMemoryCheckpointStorage!
    private var dateProvider: MockCheckpointDateProvider!
    private var checkpoint: DeviceTransferCheckpoint!

    override func setUp() {
        super.setUp()
        storage = InMemoryCheckpointStorage()
        dateProvider = MockCheckpointDateProvider()
        checkpoint = DeviceTransferCheckpoint(
            storage: storage,
            dateProvider: dateProvider,
            queue: DispatchQueue(label: "test.checkpoint")
        )
    }

    override func tearDown() {
        storage = nil
        dateProvider = nil
        checkpoint = nil
        super.tearDown()
    }

    // MARK: - Basic Save/Load Tests

    func testSaveAndLoad() {
        let manifestHash = Data("test-manifest".utf8)
        var data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )
        data.transferredFileIds.insert("file1")
        data.transferredFileIds.insert("file2")

        checkpoint.save(data)

        // Wait for async save
        let expectation = self.expectation(description: "save completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        let loaded = checkpoint.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.manifestHash, manifestHash)
        XCTAssertEqual(loaded?.transferredFileIds, ["file1", "file2"])
        XCTAssertEqual(loaded?.isIncoming, false)
        XCTAssertEqual(loaded?.estimatedTotalSize, 1000)
    }

    func testLoadReturnsNilWhenNoCheckpointExists() {
        let loaded = checkpoint.load()
        XCTAssertNil(loaded)
    }

    func testClear() {
        let manifestHash = Data("test-manifest".utf8)
        let data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        checkpoint.save(data)

        // Wait for async save
        let saveExpectation = self.expectation(description: "save completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            saveExpectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        XCTAssertNotNil(checkpoint.load())

        checkpoint.clearSync()

        XCTAssertNil(checkpoint.load())
    }

    // MARK: - Checkpoint Creation Tests

    func testCreateForOutgoingTransfer() {
        let manifestHash = Data("test-manifest".utf8)
        let data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 5000,
            manifestHash: manifestHash
        )

        XCTAssertFalse(data.isIncoming)
        XCTAssertEqual(data.estimatedTotalSize, 5000)
        XCTAssertEqual(data.manifestHash, manifestHash)
        XCTAssertTrue(data.transferredFileIds.isEmpty)
        XCTAssertTrue(data.skippedFileIds.isEmpty)
    }

    func testCreateForIncomingTransfer() {
        let manifestHash = Data("test-manifest".utf8)
        let data = checkpoint.createForIncomingTransfer(
            estimatedTotalSize: 3000,
            manifestHash: manifestHash
        )

        XCTAssertTrue(data.isIncoming)
        XCTAssertEqual(data.estimatedTotalSize, 3000)
        XCTAssertEqual(data.manifestHash, manifestHash)
        XCTAssertTrue(data.transferredFileIds.isEmpty)
        XCTAssertTrue(data.skippedFileIds.isEmpty)
    }

    // MARK: - File Tracking Tests

    func testMarkFileTransferred() {
        let manifestHash = Data("test-manifest".utf8)
        var data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        XCTAssertFalse(data.transferredFileIds.contains("file1"))

        checkpoint.markFileTransferred("file1", in: &data)

        XCTAssertTrue(data.transferredFileIds.contains("file1"))

        checkpoint.markFileTransferred("file2", in: &data)

        XCTAssertEqual(data.transferredFileIds, ["file1", "file2"])
    }

    func testMarkFileSkipped() {
        let manifestHash = Data("test-manifest".utf8)
        var data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        XCTAssertFalse(data.skippedFileIds.contains("missing-file"))

        checkpoint.markFileSkipped("missing-file", in: &data)

        XCTAssertTrue(data.skippedFileIds.contains("missing-file"))
    }

    func testMarkFileSavesCheckpoint() {
        let manifestHash = Data("test-manifest".utf8)
        var data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        checkpoint.markFileTransferred("file1", in: &data)

        // Wait for async save
        let expectation = self.expectation(description: "save completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        let loaded = checkpoint.load()
        XCTAssertNotNil(loaded)
        XCTAssertTrue(loaded?.transferredFileIds.contains("file1") ?? false)
    }

    // MARK: - Validation Tests

    func testHasValidCheckpointReturnsFalseWhenNoCheckpoint() {
        let manifestHash = Data("test-manifest".utf8)
        let isValid = checkpoint.hasValidCheckpoint(for: manifestHash, isIncoming: false)
        XCTAssertFalse(isValid)
    }

    func testHasValidCheckpointReturnsTrueForMatchingCheckpoint() {
        let manifestHash = Data("test-manifest".utf8)
        let data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        checkpoint.save(data)

        // Wait for async save
        let expectation = self.expectation(description: "save completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        let isValid = checkpoint.hasValidCheckpoint(for: manifestHash, isIncoming: false)
        XCTAssertTrue(isValid)
    }

    func testHasValidCheckpointReturnsFalseForDifferentManifestHash() {
        let manifestHash1 = Data("manifest-1".utf8)
        let manifestHash2 = Data("manifest-2".utf8)

        let data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash1
        )

        checkpoint.save(data)

        // Wait for async save
        let expectation = self.expectation(description: "save completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        // Different manifest hash should not be valid
        let isValid = checkpoint.hasValidCheckpoint(for: manifestHash2, isIncoming: false)
        XCTAssertFalse(isValid)
    }

    func testHasValidCheckpointReturnsFalseForDifferentDirection() {
        let manifestHash = Data("test-manifest".utf8)

        // Create an outgoing checkpoint
        let data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        checkpoint.save(data)

        // Wait for async save
        let expectation = self.expectation(description: "save completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        // Checking for incoming should not be valid
        let isValid = checkpoint.hasValidCheckpoint(for: manifestHash, isIncoming: true)
        XCTAssertFalse(isValid)
    }

    func testHasValidCheckpointReturnsFalseForExpiredCheckpoint() {
        let manifestHash = Data("test-manifest".utf8)

        // Create checkpoint at "now"
        let data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        checkpoint.save(data)

        // Wait for async save
        let saveExpectation = self.expectation(description: "save completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            saveExpectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        // Advance time by more than 24 hours
        dateProvider.currentDate = Date().addingTimeInterval(25 * 60 * 60)

        let isValid = checkpoint.hasValidCheckpoint(for: manifestHash, isIncoming: false)
        XCTAssertFalse(isValid)
    }

    func testHasValidCheckpointReturnsTrueForRecentCheckpoint() {
        let manifestHash = Data("test-manifest".utf8)

        let data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        checkpoint.save(data)

        // Wait for async save
        let saveExpectation = self.expectation(description: "save completes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            saveExpectation.fulfill()
        }
        waitForExpectations(timeout: 1)

        // Advance time by less than 24 hours
        dateProvider.currentDate = Date().addingTimeInterval(23 * 60 * 60)

        let isValid = checkpoint.hasValidCheckpoint(for: manifestHash, isIncoming: false)
        XCTAssertTrue(isValid)
    }

    // MARK: - Edge Cases

    func testMultipleFilesCanBeTracked() {
        let manifestHash = Data("test-manifest".utf8)
        var data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        for i in 1...100 {
            checkpoint.markFileTransferred("file-\(i)", in: &data)
        }

        XCTAssertEqual(data.transferredFileIds.count, 100)
        XCTAssertTrue(data.transferredFileIds.contains("file-1"))
        XCTAssertTrue(data.transferredFileIds.contains("file-50"))
        XCTAssertTrue(data.transferredFileIds.contains("file-100"))
    }

    func testDuplicateFileIdsAreIgnored() {
        let manifestHash = Data("test-manifest".utf8)
        var data = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        checkpoint.markFileTransferred("file1", in: &data)
        checkpoint.markFileTransferred("file1", in: &data)
        checkpoint.markFileTransferred("file1", in: &data)

        XCTAssertEqual(data.transferredFileIds.count, 1)
    }

    func testTransferIdIsUnique() {
        let manifestHash = Data("test-manifest".utf8)

        let data1 = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        let data2 = checkpoint.createForOutgoingTransfer(
            estimatedTotalSize: 1000,
            manifestHash: manifestHash
        )

        XCTAssertNotEqual(data1.transferId, data2.transferId)
    }
}
