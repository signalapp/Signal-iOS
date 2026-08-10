//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import Foundation
import GRDB
import Testing
@testable import LibSignalClient
@testable import SignalServiceKit

typealias Attachment = SignalServiceKit.Attachment

struct LocalFileBackupManagerTests {
    private let localFileBackupManager: LocalFileBackupManager
    private let db = InMemoryDB()
    private let attachmentStore = AttachmentStore()
    private let backupArchiveManager = BackupArchiveManagerMock()

    init() {
        let orphanedAttachmentCleaner = OrphanedAttachmentCleanerImpl(dateProvider: { Date() }, db: db)
        let validator = AttachmentContentValidatorImpl(
            attachmentStore: attachmentStore,
            audioWaveformManager: AudioWaveformManagerMock(),
            dateProvider: { Date() },
            db: db,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
        )

        self.localFileBackupManager = LocalFileBackupManager(
            db: db,
            dateProvider: { Date() },
            attachmentStore: attachmentStore,
            attachmentValidator: validator,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            localFileBackupStore: LocalFileBackupStore(),
            securityScopedBookmarkAccess: SecurityScopedBookmarkAccessMock(hasAccess: true, url: nil),
        )
    }

    @Test
    func testEnsureMetadataExists() async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32

        let mockAttachment = AttachmentStream.mock(
            streamInfo: .mock(
                encryptedByteCount: encryptedSize,
                unencryptedByteCount: unencryptedSize,
            ),
        ).attachment

        let id = db.write { tx in
            LocalFileBackupTestSupport.insertMockAttachment(mockAttachment, tx: tx)
        }

        await localFileBackupManager.ensureAttachmentMetadataExists()

        let metadata = try db.read { tx in
            try BackupLocalFileAttachmentMetadataRecord
                .filter(Column(BackupLocalFileAttachmentMetadataRecord.CodingKeys.attachmentRowId) == id)
                .fetchOne(tx.database)
        }

        #expect(metadata != nil)
    }

    @Test
    func testQueueAttachments() async throws {
        let encryptedSize: UInt32 = 20
        let unencryptedSize: UInt32 = 32

        let mockAttachment1 = AttachmentStream.mock(
            streamInfo: .mock(
                encryptedByteCount: encryptedSize,
                unencryptedByteCount: unencryptedSize,
            ),
        ).attachment

        let mockAttachment2 = AttachmentStream.mock(
            streamInfo: .mock(
                encryptedByteCount: encryptedSize,
                unencryptedByteCount: unencryptedSize,
            ),
        ).attachment

        let (id1, id2) = db.write { tx in
            let id1 = LocalFileBackupTestSupport.insertMockAttachment(mockAttachment1, tx: tx)
            let id2 = LocalFileBackupTestSupport.insertMockAttachment(mockAttachment2, tx: tx)
            return (id1, id2)
        }

        let localFileBackupAttachmentCollector = LocalFileBackupAttachmentCollector()
        localFileBackupAttachmentCollector.append(id: id1)
        localFileBackupAttachmentCollector.append(id: id2)

        try await localFileBackupManager.queueLocalBackupAttachmentsForExport(localFileBackupAttachmentCollector: localFileBackupAttachmentCollector)

        let attachments = try db.read { tx in
            try BackupLocalFileAttachmentExportRecord
                .fetchAll(tx.database)
        }

        #expect(attachments.count == 2)
        let attachmentIds = Set(attachments.map(\.attachmentRowId))
        #expect(attachmentIds.contains(id1))
        #expect(attachmentIds.contains(id2))
    }

    @Test
    func testCopyBackupToDisk() async throws {
        let localIdentifiers = LocalIdentifiers.forUnitTests
        let aep = AccountEntropyPool()

        let backupKey = try MessageRootBackupKey(accountEntropyPool: aep, aci: localIdentifiers.aci)

        let backupFile = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try Data("test".utf8).write(to: backupFile)

        let localBackupURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: localBackupURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: localBackupURL)
            try? FileManager.default.removeItem(at: backupFile)
        }

        let currentBackupDirectoryName = try await localFileBackupManager.copyBackupToDisk(
            backupTempFileURL: backupFile,
            messageRootBackupKey: backupKey,
            localBackupURL: localBackupURL,
        )

        let backupsRootDirectory = LocalFileBackupManager.FileStructure.rootDirectoryInFileLocation(localBackupURL)
        let currentBackupPath = backupsRootDirectory.appendingPathComponent(currentBackupDirectoryName)
        let mainFilePath = currentBackupPath.appendingPathComponent("main")
        let metadataFilePath = currentBackupPath.appendingPathComponent("metadata")

        #expect(FileManager.default.fileExists(atPath: backupsRootDirectory.path))
        #expect(FileManager.default.fileExists(atPath: currentBackupPath.path))
        #expect(FileManager.default.fileExists(atPath: mainFilePath.path))
        #expect(FileManager.default.fileExists(atPath: metadataFilePath.path))

        let metadataFileContents = try Data(contentsOf: metadataFilePath)
        let metadataProto = try LocalBackupProto_Metadata(serializedBytes: metadataFileContents)

        #expect(metadataProto.version == 1)
        let localBackupMetadataKey = backupKey.backupKey.deriveLocalBackupMetadataKey()
        let iv = metadataProto.backupID.iv
        let nonce = iv + Data(count: 4) // Last 4 bytes are 0 for the counter.
        var decryptedBackupId = metadataProto.backupID.encryptedID
        try Aes256Ctr32.process(&decryptedBackupId, key: localBackupMetadataKey, nonce: nonce)

        #expect(decryptedBackupId == backupKey.backupId)
    }

    @Test
    func testCopyAttachmentsToDisk() async throws {
        let mockAttachment1 = try LocalFileBackupTestSupport.makeMockAttachmentWithRealFile()
        let mockAttachment2 = try LocalFileBackupTestSupport.makeMockAttachmentWithRealFile()

        let (id1, id2) = db.write { tx in
            let id1 = LocalFileBackupTestSupport.insertMockAttachment(mockAttachment1, tx: tx)
            let id2 = LocalFileBackupTestSupport.insertMockAttachment(mockAttachment2, tx: tx)
            return (id1, id2)
        }

        await localFileBackupManager.ensureAttachmentMetadataExists()

        let localFileBackupAttachmentCollector = LocalFileBackupAttachmentCollector()
        localFileBackupAttachmentCollector.append(id: id1)
        localFileBackupAttachmentCollector.append(id: id2)

        try await localFileBackupManager.queueLocalBackupAttachmentsForExport(localFileBackupAttachmentCollector: localFileBackupAttachmentCollector)

        let localBackupURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: localBackupURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: localBackupURL)
        }

        let currentBackupDirectoryName = LocalFileBackupManager.FileStructure.backupDirectory(date: Date())
        let currentBackupDir = localBackupURL.appendingPathComponent(currentBackupDirectoryName)
        try FileManager.default.createDirectory(at: currentBackupDir, withIntermediateDirectories: true)

        let filesDir = localBackupURL.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)

        let filesMetadata = localBackupURL
            .appendingPathComponent(currentBackupDirectoryName)
            .appendingPathComponent("files")

        try await localFileBackupManager.writeQueuedAttachmentsToDisk(
            backupsRootDirectory: localBackupURL,
            currentBackupDirectoryName: currentBackupDirectoryName,
        )

        #expect(FileManager.default.fileExists(atPath: filesDir.path))
        #expect(FileManager.default.fileExists(atPath: filesMetadata.path))

        let localKey1 = try db.read { tx in
            try BackupLocalFileAttachmentMetadataRecord
                .filter(key: id1)
                .fetchOne(tx.database)!.localKey
        }

        let localKey2 = try db.read { tx in
            try BackupLocalFileAttachmentMetadataRecord
                .filter(key: id2)
                .fetchOne(tx.database)!.localKey
        }

        let mediaName1 = await localFileBackupManager.mediaNameForAttachment(
            localKey: localKey1,
            plaintextHash: mockAttachment1.plaintextHash!,
        )
        let mediaName2 = await localFileBackupManager.mediaNameForAttachment(
            localKey: localKey2,
            plaintextHash: mockAttachment2.plaintextHash!,
        )

        let mediaNameDir1 = filesDir.appendingPathComponent(String(mediaName1.prefix(2)))
        let mediaNameDir2 = filesDir.appendingPathComponent(String(mediaName2.prefix(2)))

        #expect(FileManager.default.fileExists(atPath: mediaNameDir1.path))
        #expect(FileManager.default.fileExists(atPath: mediaNameDir2.path))

        let mediaPath1 = mediaNameDir1.appendingPathComponent(mediaName1)
        let mediaPath2 = mediaNameDir2.appendingPathComponent(mediaName2)

        #expect(FileManager.default.fileExists(atPath: mediaPath1.path))
        #expect(FileManager.default.fileExists(atPath: mediaPath2.path))
    }

    func writeAttachmentToFilesDir(
        filesDir: URL,
        plaintextData: Data,
        localKey: AttachmentKey,
        plaintextHash: Data,
    ) throws {
        let plaintextURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try plaintextData.write(to: plaintextURL)
        defer { try? FileManager.default.removeItem(at: plaintextURL) }

        let mediaName = localFileBackupManager.mediaNameForAttachment(
            localKey: localKey.combinedKey,
            plaintextHash: plaintextHash,
        )
        let subdir = filesDir.appendingPathComponent(String(mediaName.prefix(2)))
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        let _ = try Cryptography.encryptAttachment(
            at: plaintextURL,
            output: subdir.appendingPathComponent(mediaName),
            attachmentKey: localKey,
        )
    }

    @Test
    func testRestoreAttachments() async throws {
        /* put encrypted attachments at a mock local backup location */

        let localBackupURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: localBackupURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: localBackupURL)
        }

        let filesDir = localBackupURL.appendingPathComponent("files")

        let localKey = Randomness.generateRandomBytes(64)
        let plaintextData = Data("test".utf8)
        var sha = SHA256()
        sha.update(data: plaintextData)
        let plaintextHash = Data(sha.finalize())

        try writeAttachmentToFilesDir(
            filesDir: filesDir,
            plaintextData: plaintextData,
            localKey: AttachmentKey(combinedKey: localKey),
            plaintextHash: plaintextHash,
        )

        /* pre-populate as if we've done a backup restore */

        let mockAttachment = Attachment.mock(plaintextHash: plaintextHash)
        let attachmentId = db.write { tx in
            var record = Attachment.Record(attachment: mockAttachment)
            try! record.insert(tx.database)
            let id = record.sqliteId!
            try! BackupLocalFileAttachmentMetadataRecord(
                attachmentRowId: id,
                localKey: localKey,
                unencryptedByteCount: UInt32(plaintextData.count),
            ).insert(tx.database)
            try! BackupLocalFileAttachmentImportRecord(attachmentRowId: id).insert(tx.database)
            return id
        }

        /* restore */

        try await localFileBackupManager._restoreLocalFileBackupAttachments(resolvedURL: localBackupURL)

        let importRecords = try db.read { tx in
            try BackupLocalFileAttachmentImportRecord.fetchAll(tx.database)
        }
        #expect(importRecords.isEmpty)

        let attachment = db.read { tx in
            attachmentStore.fetch(id: attachmentId, tx: tx)
        }

        #expect(attachment != nil)
        #expect(attachment!.streamInfo != nil)
        #expect(attachment!.plaintextHash == plaintextHash)
    }

    @Test
    func testCleanUpOldBackups() async throws {
        let localBackupURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: localBackupURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: localBackupURL)
        }

        let oldBackup1 = LocalFileBackupManager.FileStructure.backupDirectory(date: Date.distantPast)
        let oldBackup2 = LocalFileBackupManager.FileStructure.backupDirectory(date: Date.now.advanced(by: -10000))
        let currentBackup1 = LocalFileBackupManager.FileStructure.backupDirectory(date: Date())
        let currentBackup2 = LocalFileBackupManager.FileStructure.backupDirectory(date: Date.now.advanced(by: -10))

        try FileManager.default.createDirectory(at: localBackupURL.appendingPathComponent(oldBackup1), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localBackupURL.appendingPathComponent(oldBackup2), withIntermediateDirectories: true)

        try FileManager.default.createDirectory(at: localBackupURL.appendingPathComponent(currentBackup1), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localBackupURL.appendingPathComponent(currentBackup2), withIntermediateDirectories: true)

        #expect(try FileManager.default.contentsOfDirectory(atPath: localBackupURL.path).count == 4)

        try await localFileBackupManager.cleanUpOldBackupsAndOrphanedAttachments(backupsRootDirectory: localBackupURL)

        let backups = try FileManager.default.contentsOfDirectory(atPath: localBackupURL.path)
        #expect(backups.count == 2)
        #expect(backups.contains(currentBackup1))
        #expect(backups.contains(currentBackup2))
    }

    @Test
    func testCleanUpOrphanAttachments() async throws {
        let localBackupURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: localBackupURL, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: localBackupURL)
        }

        let currentBackup1 = LocalFileBackupManager.FileStructure.backupDirectory(date: Date())
        let currentBackup2 = LocalFileBackupManager.FileStructure.backupDirectory(date: Date.now.advanced(by: -10))

        try FileManager.default.createDirectory(at: localBackupURL.appendingPathComponent(currentBackup1), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localBackupURL.appendingPathComponent(currentBackup2), withIntermediateDirectories: true)

        let filesDir = localBackupURL.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)

        let plaintextData = Data("test".utf8)
        var sha = SHA256()
        sha.update(data: plaintextData)
        let plaintextHash = Data(sha.finalize())

        // Put a bunch of attachments in the files dir
        for _ in 0..<10 {
            let localKey = Randomness.generateRandomBytes(64)
            try writeAttachmentToFilesDir(
                filesDir: filesDir,
                plaintextData: plaintextData,
                localKey: AttachmentKey(combinedKey: localKey),
                plaintextHash: plaintextHash,
            )
        }

        // Now write some attachments to disk that are in a backup metadata file.
        // These should not be deleted.

        let mockAttachment1 = try LocalFileBackupTestSupport.makeMockAttachmentWithRealFile()
        let mockAttachment2 = try LocalFileBackupTestSupport.makeMockAttachmentWithRealFile()

        let (id1, id2) = db.write { tx in
            let id1 = LocalFileBackupTestSupport.insertMockAttachment(mockAttachment1, tx: tx)
            let id2 = LocalFileBackupTestSupport.insertMockAttachment(mockAttachment2, tx: tx)
            return (id1, id2)
        }

        await localFileBackupManager.ensureAttachmentMetadataExists()

        let localFileBackupAttachmentCollector = LocalFileBackupAttachmentCollector()
        localFileBackupAttachmentCollector.append(id: id1)
        localFileBackupAttachmentCollector.append(id: id2)

        try await localFileBackupManager.queueLocalBackupAttachmentsForExport(localFileBackupAttachmentCollector: localFileBackupAttachmentCollector)

        try await localFileBackupManager.writeQueuedAttachmentsToDisk(
            backupsRootDirectory: localBackupURL,
            currentBackupDirectoryName: currentBackup1,
        )

        let localKey1 = try db.read { tx in
            try BackupLocalFileAttachmentMetadataRecord
                .filter(Column(BackupLocalFileAttachmentMetadataRecord.CodingKeys.attachmentRowId) == id1)
                .fetchOne(tx.database)
                .map { $0.localKey }
        }

        let localKey2 = try db.read { tx in
            try BackupLocalFileAttachmentMetadataRecord
                .filter(Column(BackupLocalFileAttachmentMetadataRecord.CodingKeys.attachmentRowId) == id2)
                .fetchOne(tx.database)
                .map { $0.localKey }
        }

        let mediaName1 = await localFileBackupManager.mediaNameForAttachment(
            localKey: localKey1!,
            plaintextHash: mockAttachment1.plaintextHash!,
        )
        let mediaName2 = await localFileBackupManager.mediaNameForAttachment(
            localKey: localKey2!,
            plaintextHash: mockAttachment2.plaintextHash!,
        )

        let enumeratorBefore = FileManager.default.enumerator(
            at: filesDir,
            includingPropertiesForKeys: [.isDirectoryKey],
        )!
        let fileCountBefore = try enumeratorBefore.reduce(0) { count, item in
            guard let fileURL = item as? URL else { return count }
            let isDir = try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            return isDir ? count : count + 1
        }

        #expect(fileCountBefore == 12)

        try await localFileBackupManager.cleanUpOldBackupsAndOrphanedAttachments(backupsRootDirectory: localBackupURL)

        let enumeratorAfter = FileManager.default.enumerator(
            at: filesDir,
            includingPropertiesForKeys: [.isDirectoryKey],
        )!

        let filesAfter = try enumeratorAfter.compactMap { item -> URL? in
            guard let fileURL = item as? URL else { return nil }
            let isDir = try fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
            return isDir ? nil : fileURL
        }

        let fileNamesAfter = Set(filesAfter.map(\.lastPathComponent))

        #expect(filesAfter.count == 2)
        #expect(fileNamesAfter.contains(mediaName1))
        #expect(fileNamesAfter.contains(mediaName2))
    }
}

public enum LocalFileBackupTestSupport {
    static func makeMockAttachmentWithRealFile() throws -> Attachment {
        let key = AttachmentKey.generate()
        let plaintextData = Data("test".utf8)
        let localRelativeFilePath = AttachmentStream.newRelativeFilePath()

        let plaintextURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try plaintextData.write(to: plaintextURL)
        defer { try? FileManager.default.removeItem(at: plaintextURL) }

        let attachmentFileURL = AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: localRelativeFilePath)
        try FileManager.default.createDirectory(
            at: attachmentFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        let encryptionMetadata = try Cryptography.encryptAttachment(
            at: plaintextURL,
            output: attachmentFileURL,
            attachmentKey: key,
        )

        return AttachmentStream.mock(
            streamInfo: .mock(
                encryptionKey: key,
                encryptedByteCount: UInt32(clamping: encryptionMetadata.encryptedLength),
                unencryptedByteCount: UInt32(plaintextData.count),
                localRelativeFilePath: localRelativeFilePath,
            ),
        ).attachment
    }

    static func insertMockAttachment(_ attachment: Attachment, tx: DBWriteTransaction) -> Attachment.IDType {
        var record = Attachment.Record(attachment: attachment)
        try! record.insert(tx.database)
        return record.sqliteId!
    }
}
