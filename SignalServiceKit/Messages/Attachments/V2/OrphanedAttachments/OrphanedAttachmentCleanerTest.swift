//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import XCTest
@testable import SignalServiceKit

class OrphanedAttachmentCleanerTest: XCTestCase {

    private var db: InMemoryDB!

    private var attachmentStore: AttachmentStoreImpl!
    private var orphanedAttachmentCleaner: OrphanedAttachmentCleanerImpl!
    private var mockFileSystem: OrphanedAttachmentCleanerImpl.Mocks.OWSFileSystem!
    private var mockTaskScheduler: OrphanedAttachmentCleanerImpl.Mocks.TaskScheduler!

    override func setUp() async throws {
        db = InMemoryDB()
        attachmentStore = AttachmentStoreImpl()
        mockFileSystem = OrphanedAttachmentCleanerImpl.Mocks.OWSFileSystem()
        mockTaskScheduler = OrphanedAttachmentCleanerImpl.Mocks.TaskScheduler()
        orphanedAttachmentCleaner = OrphanedAttachmentCleanerImpl(
            dbProvider: { [db] in db!.databaseQueue },
            fileSystem: mockFileSystem,
            taskScheduler: mockTaskScheduler
        )
    }

    func testDeleteAttachment() async throws {
        let localRelativeFilePath = UUID().uuidString
        let attachmentParams = Attachment.ConstructionParams.mockStream(
            streamInfo: .mock(localRelativeFilePath: localRelativeFilePath)
        )
        let referenceParams = AttachmentReference.ConstructionParams.mock(
            owner: .thread(.globalThreadWallpaperImage(creationTimestamp: Date().ows_millisecondsSince1970))
        )

        try db.write { tx in
            try attachmentStore.insert(
                attachmentParams,
                reference: referenceParams,
                tx: tx
            )
        }

        // Start observing; should have deleted a file _after_ we commit
        // deletion of an attachment.
        orphanedAttachmentCleaner.beginObserving()
        XCTAssertEqual(mockTaskScheduler.tasks.count, 1)
        _ = try await mockTaskScheduler.tasks[0].value
        mockTaskScheduler.tasks = []

        try db.write { tx in
            try Attachment.Record.deleteAll(tx.db)

            // No deletions until the transaction commits!
            XCTAssertEqual(mockTaskScheduler.tasks.count, 0)
        }

        XCTAssertEqual(mockTaskScheduler.tasks.count, 1)
        _ = try await mockTaskScheduler.tasks[0].value

        // Should have deleted the one file.
        XCTAssertEqual(
            mockFileSystem.deletedFiles,
            [AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: localRelativeFilePath)]
            + thumbnailFileURLs(localRelativeFilePath: localRelativeFilePath)
        )

        // And no rows left.
        try db.read { tx in
            XCTAssertNil(try OrphanedAttachmentRecord.fetchOne(tx.db))
        }
    }

    func testDeleteMultiple() async throws {
        let filePaths = (0...5).map { _ in UUID().uuidString }

        try db.write { tx in
            try filePaths.forEach { filePath in
                var record = OrphanedAttachmentRecord(
                    localRelativeFilePath: filePath,
                    localRelativeFilePathThumbnail: nil,
                    localRelativeFilePathAudioWaveform: nil,
                    localRelativeFilePathVideoStillFrame: nil
                )
                try record.insert(tx.db)
            }
        }

        // Should delete all existing rows as soon as we start observing.
        orphanedAttachmentCleaner.beginObserving()

        XCTAssertEqual(mockTaskScheduler.tasks.count, 1)
        _ = try await mockTaskScheduler.tasks[0].value

        XCTAssertEqual(
            mockFileSystem.deletedFiles,
            filePaths.flatMap {
                return [AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: $0)]
                    + thumbnailFileURLs(localRelativeFilePath: $0)
            }
        )

        // And no rows left.
        try db.read { tx in
            XCTAssertNil(try OrphanedAttachmentRecord.fetchOne(tx.db))
        }
    }

    func testIgnoreFailingRowIds() async throws {
        let filePath1 = UUID().uuidString
        let url1 = AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: filePath1)
        let filePath2 = UUID().uuidString
        let url2 = AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: filePath2)

        try db.write { tx in
            try [filePath1, filePath2].forEach { filePath in
                var record = OrphanedAttachmentRecord(
                    localRelativeFilePath: filePath,
                    localRelativeFilePathThumbnail: nil,
                    localRelativeFilePathAudioWaveform: nil,
                    localRelativeFilePathVideoStillFrame: nil
                )
                try record.insert(tx.db)
            }
        }

        struct SomeError: Error {}

        let allThumbnailFilePaths = thumbnailFileURLs(localRelativeFilePath: filePath1)
            + thumbnailFileURLs(localRelativeFilePath: filePath2)

        var file1WasAttempted = false
        mockFileSystem.deleteFileMock = { url in
            if url == url1 {
                file1WasAttempted = true
                throw SomeError()
            } else if url == url2 {
                guard file1WasAttempted else {
                    XCTFail("Unexpected deletion order")
                    return
                }
            } else if allThumbnailFilePaths.contains(url) {
                return
            } else {
                XCTFail("Unexpected file deleted")
            }
        }

        // Should delete all existing rows as soon as we start observing.
        orphanedAttachmentCleaner.beginObserving()

        XCTAssertEqual(mockTaskScheduler.tasks.count, 1)
        _ = try await mockTaskScheduler.tasks[0].value

        // The fact that the first failed shouldn't have stopped the second.
        XCTAssertEqual(
            mockFileSystem.deletedFiles,
            [url2]
            + thumbnailFileURLs(localRelativeFilePath: filePath2)
        )

        // The first row should still be around.
        try db.read { tx in
            let record = try OrphanedAttachmentRecord.fetchOne(tx.db)
            XCTAssertEqual(record?.localRelativeFilePath, filePath1)
        }

        // If we insert again the first row should be ignored.
        mockFileSystem.deletedFiles = []
        mockTaskScheduler.tasks = []
        let filePath3 = UUID().uuidString
        let url3 = AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: filePath3)

        mockFileSystem.deleteFileMock = { url in
            if url == url3 {
                return
            } else if self.thumbnailFileURLs(localRelativeFilePath: filePath3).contains(url) {
                return
            } else {
                XCTFail("Unexpected file deleted")
            }
        }

        try db.write { tx in
            var record = OrphanedAttachmentRecord(
                localRelativeFilePath: filePath3,
                localRelativeFilePathThumbnail: nil,
                localRelativeFilePathAudioWaveform: nil,
                localRelativeFilePathVideoStillFrame: nil
            )
            try record.insert(tx.db)
        }

        XCTAssertEqual(mockTaskScheduler.tasks.count, 1)
        _ = try await mockTaskScheduler.tasks[0].value

        // The fact that the first failed shouldn't have stopped the third.
        XCTAssertEqual(
            mockFileSystem.deletedFiles,
            [url3]
            + thumbnailFileURLs(localRelativeFilePath: filePath3)
        )

        // The first row should still be around.
        try db.read { tx in
            let record = try OrphanedAttachmentRecord.fetchOne(tx.db)
            XCTAssertEqual(record?.localRelativeFilePath, filePath1)
        }
    }

    func testOrphanRecordFieldCoverage() async throws {
        var record = OrphanedAttachmentRecord(
            localRelativeFilePath: UUID().uuidString,
            localRelativeFilePathThumbnail: UUID().uuidString,
            localRelativeFilePathAudioWaveform: UUID().uuidString,
            localRelativeFilePathVideoStillFrame: UUID().uuidString
        )

        try db.write { tx in
            try record.insert(tx.db)
        }

        // Should delete all existing rows as soon as we start observing.
        orphanedAttachmentCleaner.beginObserving()
        XCTAssertEqual(mockTaskScheduler.tasks.count, 1)
        _ = try await mockTaskScheduler.tasks[0].value

        // Check that all string fields were deleted.
        // If a new non-file string field is added, make sure to exclude it here.
        var fieldCount = 0
        for (_, value) in Mirror(reflecting: record).children {
            guard type(of: value) == String.self || type(of: value) == Optional<String>.self else {
                continue
            }
            let url = AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: value as! String)
            XCTAssert(mockFileSystem.deletedFiles.contains(url))
            fieldCount += 1
        }

        // Should also get a deletion for every thumbnail size.
        fieldCount += AttachmentThumbnailQuality.allCases.count

        XCTAssertEqual(mockFileSystem.deletedFiles.count, fieldCount)
    }

    // MARK: - Helpers

    private func thumbnailFileURLs(localRelativeFilePath: String) -> [URL] {
        return AttachmentThumbnailQuality.allCases.map { quality in
            return AttachmentThumbnailQuality.thumbnailCacheFileUrl(
                attachmentLocalRelativeFilePath: localRelativeFilePath,
                at: quality
            )
        }
    }
}

extension OrphanedAttachmentCleanerImpl {
    enum Mocks {
        fileprivate typealias OWSFileSystem = _OrphanedAttachmentCleanerImpl_OWSFileSystemMock
        fileprivate typealias TaskScheduler = _OrphanedAttachmentCleanerImpl_TaskSchedulerMock
    }
}

private class _OrphanedAttachmentCleanerImpl_OWSFileSystemMock: _OrphanedAttachmentCleanerImpl_OWSFileSystemShim {

    init() {}

    func fileOrFolderExists(url: URL) -> Bool {
        true
    }

    var deletedFiles = [URL]()
    var deleteFileMock: (URL) throws -> Void = { _ in }

    func deleteFileIfExists(url: URL) throws {
        try deleteFileMock(url)
        deletedFiles.append(url)
    }
}

private class _OrphanedAttachmentCleanerImpl_TaskSchedulerMock: _OrphanedAttachmentCleanerImpl_TaskSchedulerShim {

    init() {}

    var tasks = [Task<Void, Error>]()

    func task(_ block: @escaping () async throws -> Void) {
        let task = Task {
            try await block()
        }
        tasks.append(task)
    }
}
