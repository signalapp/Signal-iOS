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

/// TODO: [KC] dont make this public, it should only be accessed via a job runner
public class LocalFileBackupExportJob {

    private let accountKeyStore: AccountKeyStore
    private let backupArchiveManager: BackupArchiveManager
    private let db: DB
    private let logger: PrefixedLogger
    private let tsAccountManager: TSAccountManager
    private let localFileBackupManager: LocalFileBackupManager
    private let securityScopedBookmarkAccess: SecurityScopedBookmarkAccess

    public init(
        accountKeyStore: AccountKeyStore,
        backupArchiveManager: BackupArchiveManager,
        db: DB,
        tsAccountManager: TSAccountManager,
        localFileBackupManager: LocalFileBackupManager,
        securityScopedBookmarkAccess: SecurityScopedBookmarkAccess,
    ) {
        self.accountKeyStore = accountKeyStore
        self.backupArchiveManager = backupArchiveManager
        self.db = db
        self.logger = PrefixedLogger(prefix: "[LocalFileBackups][ExportJob]")
        self.tsAccountManager = tsAccountManager
        self.localFileBackupManager = localFileBackupManager
        self.securityScopedBookmarkAccess = securityScopedBookmarkAccess
    }

    // MARK: -

    public func run(
        mode: LocalFileBackupExportJobMode,
    ) async throws {
        switch mode {
        case .manual:
            try await _run(
                mode: mode,
            )
        case .bgProcessingTask:
            let result = await Result(
                catching: { () async throws -> Void in
                    try await _run(
                        mode: mode,
                    )
                },
            )
            try result.get()
        }
    }

    private func _run(
        mode: LocalFileBackupExportJobMode,
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

        await localFileBackupManager.ensureAttachmentMetadataExists()

        // TODO: [KC] backup progress
        let metadata = try await backupArchiveManager.exportEncryptedBackup(
            localIdentifiers: localIdentifiers,
            backupPurpose: .localExport(key: backupKey, attachmentCollector: localFileBackupAttachmentCollector),
            progress: nil,
            logger: logger,
        )

        try await localFileBackupManager.queueLocalBackupAttachmentsForExport(
            localFileBackupAttachmentCollector: localFileBackupAttachmentCollector,
        )

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

        let (backupsRootDirectory, currentBackupDirectoryName) = try await localFileBackupManager.copyBackupToDisk(
            backupTempFileURL: metadata.fileUrl,
            messageRootBackupKey: backupKey,
            localBackupURL: resolvedURL,
        )

        try await localFileBackupManager.writeQueuedAttachmentsToDisk(
            backupsRootDirectory: backupsRootDirectory,
            currentBackupDirectoryName: currentBackupDirectoryName,
        )

        // TODO: [KC] limit local file backups to 2, delete older ones
        // TODO: [KC] delete orphaned attachments
    }
}
