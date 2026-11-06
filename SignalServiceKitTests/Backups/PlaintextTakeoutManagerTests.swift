//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import Testing
@testable import SignalServiceKit

final class PlaintextTakeoutManagerTests {
    private let backupArchiveManager: BackupArchiveManagerMock
    private let db: InMemoryDB
    private let destinationFolderUrl: URL
    private let exportDate: Date
    private let plaintextTakeoutManager: PlaintextTakeoutManager

    init() throws {
        let backupArchiveManager = BackupArchiveManagerMock()
        let db = InMemoryDB()
        let attachmentStore = AttachmentStore()
        let exportDate = Date()

        let destinationFolderUrl = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: destinationFolderUrl,
            withIntermediateDirectories: true,
        )

        self.backupArchiveManager = backupArchiveManager
        self.db = db
        self.destinationFolderUrl = destinationFolderUrl
        self.exportDate = exportDate
        self.plaintextTakeoutManager = PlaintextTakeoutManager(
            attachmentStore: attachmentStore,
            backupArchiveManager: backupArchiveManager,
            dateProvider: { exportDate },
            db: db,
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
            tsAccountManager: MockTSAccountManager(),
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: destinationFolderUrl)
    }

    private var expectedExportDirectoryUrl: URL {
        destinationFolderUrl.appendingPathComponent(
            PlaintextTakeoutManager.FileStructure.exportDirectoryName(date: exportDate),
            isDirectory: true,
        )
    }

    private func exportTakeout(includeAttachments: Bool) async throws -> URL {
        return try await plaintextTakeoutManager.exportTakeout(
            destinationFolderUrl: destinationFolderUrl,
            includeAttachments: includeAttachments,
            progress: nil,
        )
    }

    // MARK: -

    @Test
    func testExportWithAttachments() async throws {
        let attachment = try LocalFileBackupTestSupport.makeMockAttachmentWithRealFile()
        let attachmentId = db.write { tx in
            LocalFileBackupTestSupport.insertMockAttachment(attachment, tx: tx)
        }
        // Collected twice, as if referenced by multiple messages.
        backupArchiveManager.exportPlaintextBackupForTakeoutAttachmentIds = [attachmentId, attachmentId]

        let exportDirectoryUrl = try await exportTakeout(includeAttachments: true)
        #expect(exportDirectoryUrl == expectedExportDirectoryUrl)

        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: exportDirectoryUrl.appendingPathComponent("main.jsonl").path))
        #expect(fileManager.fileExists(atPath: exportDirectoryUrl.appendingPathComponent("metadata.json").path))

        let attachmentName = try #require(attachment.plaintextHash).hexadecimalString
        let subdirectoryUrl = exportDirectoryUrl
            .appendingPathComponent("files")
            .appendingPathComponent(String(attachmentName.prefix(2)))

        let attachmentFileNames = try fileManager.contentsOfDirectory(atPath: subdirectoryUrl.path)
        #expect(attachmentFileNames.count == 1)
        #expect(attachmentFileNames.first?.hasPrefix("\(attachmentName).") == true)
    }

    @Test
    func testExportWithoutAttachments() async throws {
        let attachment = try LocalFileBackupTestSupport.makeMockAttachmentWithRealFile()
        let attachmentId = db.write { tx in
            LocalFileBackupTestSupport.insertMockAttachment(attachment, tx: tx)
        }
        backupArchiveManager.exportPlaintextBackupForTakeoutAttachmentIds = [attachmentId]

        let exportDirectoryUrl = try await exportTakeout(includeAttachments: false)

        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: exportDirectoryUrl.appendingPathComponent("main.jsonl").path))
        #expect(fileManager.fileExists(atPath: exportDirectoryUrl.appendingPathComponent("metadata.json").path))
        #expect(!fileManager.fileExists(atPath: exportDirectoryUrl.appendingPathComponent("files").path))
    }

    @Test
    func testFailedExportRemovesExportDirectory() async throws {
        // A stream whose file doesn't exist on disk, so decrypting it during
        // attachment export throws. By then, the export directory exists.
        let attachment = AttachmentStream.mock().attachment
        let attachmentId = db.write { tx in
            LocalFileBackupTestSupport.insertMockAttachment(attachment, tx: tx)
        }
        backupArchiveManager.exportPlaintextBackupForTakeoutAttachmentIds = [attachmentId]

        await #expect(throws: (any Error).self) {
            try await self.exportTakeout(includeAttachments: true)
        }

        #expect(!FileManager.default.fileExists(atPath: expectedExportDirectoryUrl.path))
    }

    @Test
    func testExistingExportDirectoryIsNotRemoved() async throws {
        let existingFileUrl = expectedExportDirectoryUrl.appendingPathComponent("existing")
        try FileManager.default.createDirectory(
            at: expectedExportDirectoryUrl,
            withIntermediateDirectories: true,
        )
        try Data("existing".utf8).write(to: existingFileUrl)

        await #expect(throws: (any Error).self) {
            try await self.exportTakeout(includeAttachments: false)
        }

        #expect(try Data(contentsOf: existingFileUrl) == Data("existing".utf8))
    }
}
