//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Testing
@testable import LibSignalClient
@testable import SignalServiceKit

struct LocalFileBackupExportJobRunnerTests {
    private let jobRunner: LocalFileBackupExportJobRunner
    private let db: DB = InMemoryDB()
    private let backupsURL: URL
    private let backupExportLock: BackupExportLock
    private let localFileBackupExportJobStore: LocalFileBackupExportJobStore
    private let localFileBackupManager: LocalFileBackupManager

    init() {
        self.backupExportLock = BackupExportLock()
        let dateProvider = { Date() }

        let localFileBackupStore = LocalFileBackupStore()
        db.write { tx in
            localFileBackupStore.storeBookmarkData(bookmarkData: SecurityScopedBookmark(rawValue: Data()), tx: tx)
        }

        backupsURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        let securityScopedBookmark = SecurityScopedBookmarkAccessMock(hasAccess: true, url: backupsURL)

        self.localFileBackupManager = LocalFileBackupManager(
            db: db,
            dateProvider: dateProvider,
            attachmentStore: AttachmentStore(),
            attachmentValidator: AttachmentContentValidatorMock(),
            orphanedAttachmentCleaner: OrphanedAttachmentCleanerImpl(dateProvider: dateProvider, db: db),
            localFileBackupStore: localFileBackupStore,
            securityScopedBookmarkAccess: securityScopedBookmark,
        )

        self.localFileBackupExportJobStore = LocalFileBackupExportJobStore()

        let mockTSAccountManager = MockTSAccountManager()
        mockTSAccountManager.localIdentifiersMock = {
            return LocalIdentifiers(
                aci: Aci.randomForTesting(),
                pni: Pni.randomForTesting(),
                e164: E164("+16505550101")!,
            )
        }

        let accountKeyStore = AccountKeyStore(backupSettingsStore: BackupSettingsStore())
        let aep = AccountEntropyPool()
        db.write { tx in
            accountKeyStore.setAccountEntropyPool(aep, tx: tx)
        }

        self.jobRunner = LocalFileBackupExportJobRunnerImpl(
            localFileBackupExportJob: .init(
                accountKeyStore: accountKeyStore,
                backupArchiveManager: BackupArchiveManagerMock(),
                db: db,
                tsAccountManager: MockTSAccountManager(),
                localFileBackupManager: localFileBackupManager,
                securityScopedBookmarkAccess: securityScopedBookmark,
                localFileBackupExportJobStore: localFileBackupExportJobStore,
                localFileBackupStore: localFileBackupStore,
            ),
            localFileBackupExportJobStore: localFileBackupExportJobStore,
            db: db,
            backupExportLock: backupExportLock,
        )
    }

    @Test
    func localFileBackup_happyPath() async throws {
        _ = await self.jobRunner.startIfNecessary(mode: .manual).result

        let backupsRootDirectory = LocalFileBackupManager.FileStructure.rootDirectoryInFileLocation(backupsURL)
        #expect(FileManager.default.fileExists(atPath: backupsRootDirectory.path))
    }

    @Test
    func localFileBackup_resumedAfterCopy() async throws {
        let currentBackupDir = LocalFileBackupManager.FileStructure.backupDirectory(date: Date())
        let backupsRootDir = LocalFileBackupManager.FileStructure.rootDirectoryInFileLocation(backupsURL)
        try FileManager.default.createDirectory(
            at: backupsRootDir.appendingPathComponent(currentBackupDir),
            withIntermediateDirectories: true,
        )

        // Put attachments in the queue as if we made a backup then paused.
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

        // Seed the store with a resumption point
        await db.awaitableWrite { tx in
            localFileBackupExportJobStore.setReachedResumptionPoint(.postBackupFileCopy(directoryName: currentBackupDir), tx: tx)
        }

        _ = await jobRunner.resumeIfNecessary()?.result

        let backupsRootDirectory = LocalFileBackupManager.FileStructure.rootDirectoryInFileLocation(backupsURL)
        #expect(FileManager.default.fileExists(atPath: backupsRootDirectory.path))

        let filesUrl = backupsRootDirectory.appendingPathComponent(LocalFileBackupManager.FileStructure.attachmentDirectory.rawValue)
        #expect(FileManager.default.fileExists(atPath: filesUrl.path))
        let contents = try FileManager.default.contentsOfDirectory(atPath: filesUrl.path)
        #expect(!contents.isEmpty)
    }

    @Test
    func localFileBackup_errorIfRemoteIsRunning() async throws {
        // Claim the lock as a remote backup.
        let claim = backupExportLock.tryClaim(asHolder: .remote, start: {
            return Task {}
        })
        #expect({
            if case .claimed = claim { return true }
            return false
        }())

        await #expect(throws: BackupExportLockError.remoteBackupInProgress.self) {
            try await self.jobRunner.startIfNecessary(mode: .manual).value
        }

        // Unblock the remote backup.
        backupExportLock.release(holder: .remote)

        _ = await self.jobRunner.startIfNecessary(mode: .manual).result
        let backupsRootDirectory = LocalFileBackupManager.FileStructure.rootDirectoryInFileLocation(backupsURL)
        #expect(FileManager.default.fileExists(atPath: backupsRootDirectory.path))
    }

}
