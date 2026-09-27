//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public enum LocalFileBackupExportJobStage: String, OWSSequentialProgressStep {
    /// Steps related to making sure we have all metadata for attachments
    case attachmentMetadataPrep
    /// Steps related to exporting the Backup file.
    case backupFileExport
    /// Steps related to copying attachments to disk.
    case attachmentCopy

    public var progressUnitCount: UInt64 {
        // Callers are only interested in the progress through a given stage,
        // note relative to other stages. Use a large value here so the progress
        // through a given stage can be granular.
        return 1000
    }
}

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
        progress: OWSSequentialProgressRootSink<LocalFileBackupExportJobStage>,
    ) async throws {
        try await _run(
            mode: mode,
            resumptionPoint: resumptionPoint,
            progress: progress,
        )
    }

    private func _run(
        mode: LocalFileBackupExportJobMode,
        resumptionPoint: LocalFileBackupExportJobStore.ResumptionPoint?,
        progress: OWSSequentialProgressRootSink<LocalFileBackupExportJobStage>,
    ) async throws {
        let (localIdentifiers, backupKey) = try db.read { tx in
            guard
                tsAccountManager.registrationState(tx: tx).isRegistered,
                let aep = accountKeyStore.getAccountEntropyPool(tx: tx),
                let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
            else {
                throw NotRegisteredError()
            }

            let backupKey = MessageRootBackupKey(
                accountEntropyPool: aep,
                aci: localIdentifiers.aci,
            )
            return (localIdentifiers, backupKey)
        }

        do {
            let localFileBackupAttachmentCollector = LocalFileBackupAttachmentCollector()

            logger.info("Starting. Resumption point: \(resumptionPoint as Optional)")

            guard let resolvedURL = try await localFileBackupManager.getSavedSecurityScopedBookmark(type: .archive) else {
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

            switch resumptionPoint {
            case nil:
                logger.info("Ensuring attachment metadata exists...")
                await localFileBackupManager.ensureAttachmentMetadataExists(progressSink: progress.child(for: .attachmentMetadataPrep))

                logger.info("Exporting backup...")
                let metadata = try await backupArchiveManager.exportEncryptedBackup(
                    localIdentifiers: localIdentifiers,
                    backupPurpose: .localExport(key: backupKey, attachmentCollector: localFileBackupAttachmentCollector),
                    progress: progress.child(for: .backupFileExport),
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
                let backupMediaSizeBytes = metadata.localAttachmentByteSize
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
                await performWithDummyProgress(progress.child(for: .attachmentMetadataPrep), work: {})
                await performWithDummyProgress(progress.child(for: .backupFileExport), work: {})
                currentDirectoryName = directoryName
            }

            logger.info("Copying attachments to disk...")
            try await localFileBackupManager.writeQueuedAttachmentsToDisk(
                backupsRootDirectory: backupsRootDirectory,
                currentBackupDirectoryName: currentDirectoryName,
                progress: progress.child(for: .attachmentCopy),
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
        } catch LocalFileBackupError.unableToAccessLocalFile(let reason) {
            await db.awaitableWrite { tx in
                localFileBackupExportJobStore.setReachedResumptionPoint(nil, tx: tx)
                switch mode {
                case .bgProcessingTask:
                    self.localFileBackupStore.incrementBackgroundLocalFileBackupErrorCount(tx: tx)
                case .manual:
                    self.localFileBackupStore.incrementInteractiveLocalFileBackupErrorCount(tx: tx)
                }

                switch reason {
                case .stale, .missing, .failedToResolveBookmark, .trashed:
                    logger.error("Unable to export local file backup (\(reason))")
                    // Prompt the user to pick a new backup location on next load of the chat list.
                    localFileBackupManager.setChooseNewLocalBackupLocation(tx: tx)
                case .noAccess:
                    logger.error("Unable to export local file backup (no access)")
                }
            }
            throw LocalFileBackupError.unableToAccessLocalFile(reason)
        } catch let error {
            await db.awaitableWrite { tx in
                localFileBackupExportJobStore.setReachedResumptionPoint(nil, tx: tx)
                switch mode {
                case .bgProcessingTask:
                    self.localFileBackupStore.incrementBackgroundLocalFileBackupErrorCount(tx: tx)
                case .manual:
                    self.localFileBackupStore.incrementInteractiveLocalFileBackupErrorCount(tx: tx)
                }
            }
            logger.warn("Failed! \(error)")
            throw error
        }
    }

    /// Run the given block, which does not itself track progress, and complete
    /// the given "dummy" progress when the block is complete.
    private func performWithDummyProgress(
        _ progress: OWSProgressSink,
        work: () async throws -> Void,
    ) async rethrows {
        try await work()

        progress.addSource(withLabel: "", unitCount: 1).complete()
    }
}
