//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public enum LocalFileBackupExportJobMode: CustomStringConvertible {
    case manual
    case bgProcessingTask

    public var description: String {
        switch self {
        case .manual: "Manual"
        case .bgProcessingTask: "BGProcessingTask"
        }
    }
}

// MARK: -

class LocalFileBackupExportJob {
    private let accountKeyStore: AccountKeyStore
    private let backupArchiveManager: BackupArchiveManager
    private let db: DB
    private let logger: PrefixedLogger
    private let tsAccountManager: TSAccountManager
    private let localFileBackupManager: LocalFileBackupManager
    private let securityScopedBookmarkAccess: SecurityScopedBookmarkAccess
    private let localFileBackupExportJobStore: LocalFileBackupExportJobStore
    private let localFileBackupStore: LocalFileBackupStore

    init(
        accountKeyStore: AccountKeyStore,
        backupArchiveManager: BackupArchiveManager,
        db: DB,
        tsAccountManager: TSAccountManager,
        localFileBackupManager: LocalFileBackupManager,
        securityScopedBookmarkAccess: SecurityScopedBookmarkAccess,
        localFileBackupExportJobStore: LocalFileBackupExportJobStore,
        localFileBackupStore: LocalFileBackupStore,
    ) {
        self.accountKeyStore = accountKeyStore
        self.backupArchiveManager = backupArchiveManager
        self.db = db
        self.logger = PrefixedLogger(prefix: "[LocalFileBackups][ExportJob]")
        self.tsAccountManager = tsAccountManager
        self.localFileBackupManager = localFileBackupManager
        self.securityScopedBookmarkAccess = securityScopedBookmarkAccess
        self.localFileBackupExportJobStore = localFileBackupExportJobStore
        self.localFileBackupStore = localFileBackupStore
    }

    // MARK: -

    func run(
        mode: LocalFileBackupExportJobMode,
        resumptionPoint: LocalFileBackupExportJobStore.ResumptionPoint?,
    ) async throws {
        try await _run(
            mode: mode,
            resumptionPoint: resumptionPoint,
        )
    }

    private func _run(
        mode: LocalFileBackupExportJobMode,
        resumptionPoint: LocalFileBackupExportJobStore.ResumptionPoint?,
    ) async throws {
        let (localIdentifiers, backupKey) = try db.read { tx in
            guard
                tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
                let aep = accountKeyStore.getAccountEntropyPool(tx: tx),
                let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
            else {
                throw NotRegisteredError()
            }

            let backupKey = try MessageRootBackupKey(
                accountEntropyPool: aep,
                aci: localIdentifiers.aci,
            )
            return (localIdentifiers, backupKey)
        }

        let localFileBackupAttachmentCollector = LocalFileBackupAttachmentCollector()

        logger.info("Starting. Resumption point: \(resumptionPoint as Optional)")

        guard let resolvedURL = try await localFileBackupManager.getSavedSecurityScopedBookmark() else {
            throw OWSAssertionError("No local file backup location bookmark data stored")
        }

        let hasAccess = securityScopedBookmarkAccess.startAccessToSecurityScopedBookmark(url: resolvedURL)
        guard hasAccess else {
            throw LocalFileBackupError.unableToAccessLocalFile(.noAccess)
        }

        defer {
            securityScopedBookmarkAccess.stopAccessToSecurityScopedBookmark(url: resolvedURL)
        }

        let backupsRootDirectory = LocalFileBackupManager.FileStructure.rootDirectoryInFileLocation(resolvedURL)
        let currentDirectoryName: String
        do {
            switch resumptionPoint {
            case nil:
                logger.info("Ensuring attachment metadata exists...")
                await localFileBackupManager.ensureAttachmentMetadataExists()

                logger.info("Exporting backup...")
                // TODO: [KC] backup progress
                let metadata = try await backupArchiveManager.exportEncryptedBackup(
                    localIdentifiers: localIdentifiers,
                    backupPurpose: .localExport(key: backupKey, attachmentCollector: localFileBackupAttachmentCollector),
                    progress: nil,
                    logger: logger,
                )

                logger.info("Queueing local attachments for export...")
                try await localFileBackupManager.queueLocalBackupAttachmentsForExport(
                    localFileBackupAttachmentCollector: localFileBackupAttachmentCollector,
                )

                logger.info("Copying local backup to disk...")
                let currentBackupDirectoryName = try await localFileBackupManager.copyBackupToDisk(
                    backupTempFileURL: metadata.fileUrl,
                    messageRootBackupKey: backupKey,
                    localBackupURL: resolvedURL,
                )
                currentDirectoryName = currentBackupDirectoryName

                let backupFileSizeBytes = UInt64(safeCast: metadata.encryptedDataLength)
                let backupMediaSizeBytes = metadata.attachmentByteSize
                await db.awaitableWrite { tx in
                    localFileBackupStore.setLastBackupDetails(
                        date: metadata.exportStartDate,
                        backupSizeBytes: backupFileSizeBytes + backupMediaSizeBytes,
                        tx: tx,
                    )
                }
                await db.awaitableWrite { tx in
                    localFileBackupExportJobStore.setReachedResumptionPoint(.postBackupFileCopy(directoryName: currentDirectoryName), tx: tx)
                }
            case .postBackupFileCopy(let directoryName):
                currentDirectoryName = directoryName
            }

            logger.info("Copying attachments to disk...")
            try await localFileBackupManager.writeQueuedAttachmentsToDisk(
                backupsRootDirectory: backupsRootDirectory,
                currentBackupDirectoryName: currentDirectoryName,
            )

            logger.info("Cleaning up orphaned attachments and old backups...")
            try await localFileBackupManager.cleanUpOldBackupsAndOrphanedAttachments(backupsRootDirectory: backupsRootDirectory)

            await db.awaitableWrite { tx in
                localFileBackupExportJobStore.setReachedResumptionPoint(nil, tx: tx)
            }
            logger.info("Done!")
        } catch let error as CancellationError {
            await db.awaitableWrite { tx in
                localFileBackupExportJobStore.setReachedResumptionPoint(nil, tx: tx)
            }
            logger.warn("Cancelled!")
            throw error
        } catch let error {
            await db.awaitableWrite { tx in
                localFileBackupExportJobStore.setReachedResumptionPoint(nil, tx: tx)
            }
            logger.warn("Failed! \(error)")
            throw error
        }
    }
}
