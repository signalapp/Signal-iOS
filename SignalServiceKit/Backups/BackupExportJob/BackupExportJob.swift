//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public enum BackupExportJobStage: String, OWSSequentialProgressStep {
    /// Steps related to exporting the Backup file.
    case backupFileExport
    /// Steps related to uploading the Backup file.
    case backupFileUpload
    /// Steps related to uploading attachments to the media tier.
    case attachmentUpload
    /// Steps related to attachments, post-upload.
    case attachmentProcessing

    public var progressUnitCount: UInt64 {
        // Callers are only interested in the progress through a given stage,
        // note relative to other stages. Use a large value here so the progress
        // through a given stage can be granular.
        return 1000
    }
}

public enum BackupExportJobMode: CustomStringConvertible {
    case manual
    case bgProcessingTask

    public var description: String {
        switch self {
        case .manual: "Manual"
        case .bgProcessingTask: "BGProcessingTask"
        }
    }
}

public enum BackupExportJobError: Error {
    case needsWifi
}

// MARK: -

/// Responsible for performing direct and ancillary steps to "perform a Backup".
///
/// - Important
/// Only one `BackupExportJob` should run at once; that exclusivity is managed
/// by `BackupExportJobRunner`. Callers should always prefer calling
/// `BackupExportJobRunner` instead of `BackupExportJob`.
class BackupExportJob {

    private let accountKeyStore: AccountKeyStore
    private let backupArchiveManager: BackupArchiveManager
    private let backupAttachmentCoordinator: BackupAttachmentCoordinator
    private let backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let backupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager
    private let backupExportJobStore: BackupExportJobStore
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let logger: PrefixedLogger
    private let messageProcessor: MessageProcessor
    private let reachabilityManager: SSKReachabilityManager
    private let tsAccountManager: TSAccountManager

    init(
        accountKeyStore: AccountKeyStore,
        backupArchiveManager: BackupArchiveManager,
        backupAttachmentCoordinator: BackupAttachmentCoordinator,
        backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        backupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager,
        backupExportJobStore: BackupExportJobStore,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        messageProcessor: MessageProcessor,
        reachabilityManager: SSKReachabilityManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.accountKeyStore = accountKeyStore
        self.backupArchiveManager = backupArchiveManager
        self.backupAttachmentCoordinator = backupAttachmentCoordinator
        self.backupAttachmentDownloadQueueStatusManager = backupAttachmentDownloadQueueStatusManager
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.backupAttachmentUploadQueueStatusManager = backupAttachmentUploadQueueStatusManager
        self.backupExportJobStore = backupExportJobStore
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.logger = PrefixedLogger(prefix: "[Backups][ExportJob]")
        self.messageProcessor = messageProcessor
        self.reachabilityManager = reachabilityManager
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    func run(
        mode: BackupExportJobMode,
        resumptionPoint: BackupExportJobStore.ResumptionPoint?,
        progress: OWSSequentialProgressRootSink<BackupExportJobStage>,
    ) async throws {
        switch mode {
        case .manual:
            try await _run(
                mode: mode,
                resumptionPoint: resumptionPoint,
                progress: progress,
            )
        case .bgProcessingTask:
            await backupAttachmentDownloadQueueStatusManager.setIsMainAppAndActiveOverride(true)
            await backupAttachmentUploadQueueStatusManager.setIsMainAppAndActiveOverride(true)
            let result = await Result(
                catching: { () async throws -> Void in
                    try await _run(
                        mode: mode,
                        resumptionPoint: resumptionPoint,
                        progress: progress,
                    )
                },
            )
            await backupAttachmentDownloadQueueStatusManager.setIsMainAppAndActiveOverride(false)
            await backupAttachmentUploadQueueStatusManager.setIsMainAppAndActiveOverride(false)
            try result.get()
        }
    }

    private func _run(
        mode: BackupExportJobMode,
        resumptionPoint: BackupExportJobStore.ResumptionPoint?,
        progress: OWSSequentialProgressRootSink<BackupExportJobStage>,
    ) async throws {
        let aep: AccountEntropyPool
        let backupKey: MessageRootBackupKey
        let backupPlan: BackupPlan
        let hasConsumedMediaTierCapacity: Bool
        let localIdentifiers: LocalIdentifiers
        let shouldAllowBackupUploadsOnCellular: Bool
        (
            aep,
            backupPlan,
            backupKey,
            hasConsumedMediaTierCapacity,
            localIdentifiers,
            shouldAllowBackupUploadsOnCellular,
        ) = try await db.awaitableWrite { tx throws in
            backupSettingsStore.setIsBackupUploadQueueSuspended(false, tx: tx)

            guard
                tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
                let aep = accountKeyStore.getAccountEntropyPool(tx: tx),
                let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
            else {
                throw NotRegisteredError()
            }

            guard
                let backupKey = try? MessageRootBackupKey(
                    accountEntropyPool: aep,
                    aci: localIdentifiers.aci,
                )
            else {
                throw OWSAssertionError("Missing or invalid message root backup key.")
            }

            return (
                aep,
                backupSettingsStore.backupPlan(tx: tx),
                backupKey,
                backupSettingsStore.hasConsumedMediaTierCapacity(tx: tx),
                localIdentifiers,
                backupSettingsStore.shouldAllowBackupUploadsOnCellular(tx: tx),
            )
        }

        let logger = logger.suffixed(with: "[\(mode)][\(aep.getLoggingKey())]")
        logger.info("Starting. Resumption point: \(resumptionPoint as Optional)")

        switch backupPlan {
        case .disabling, .disabled:
            throw OWSAssertionError("Running, but Backups are disabled!", logger: logger)
        case .free, .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        if !shouldAllowBackupUploadsOnCellular {
            // The job requires uploading the backup; if we're not on wifi
            // and therefore can't upload don't even bother generating the backup.
            if !reachabilityManager.isReachable(via: .wifi) {
                logger.info("Giving up; not connected to wifi & cellular uploads disabled")
                throw BackupExportJobError.needsWifi
            }
        }

        do {
            await db.awaitableWrite { tx in
                backupExportJobStore.setReachedResumptionPoint(.beginning, tx: tx)
            }

            switch resumptionPoint {
            case nil, .beginning:
                // Wait for message processing before creating a Backup, to maximize
                // the amount of message history we get into the Backup.
                logger.info("Waiting on message processing...")
                try? await messageProcessor.waitForFetchingAndProcessing()

                logger.info("Exporting backup...")
                let uploadMetadata = try await backupArchiveManager.exportEncryptedBackup(
                    localIdentifiers: localIdentifiers,
                    backupPurpose: .remoteExport(
                        key: backupKey,
                        chatAuth: .implicit(),
                    ),
                    progress: progress.child(for: .backupFileExport),
                    logger: logger,
                )

                logger.info("Uploading backup...")
                try await Retry.performWithBackoff(
                    maxAttempts: 3,
                    isRetryable: { error in
                        error.isRetryableNetworkOrUploadError
                    },
                    block: {
                        _ = try await backupArchiveManager.uploadEncryptedBackup(
                            backupKey: backupKey,
                            metadata: uploadMetadata,
                            auth: .implicit(),
                            progress: progress.child(for: .backupFileUpload),
                            logger: logger,
                        )
                    },
                )
            case .postBackupFile:
                // Need to complete the progress children, or
                // OWSSequentialProgress reports them as the "current step".
                await performWithDummyProgress(progress.child(for: .backupFileExport), work: {})
                await performWithDummyProgress(progress.child(for: .backupFileUpload), work: {})
            }

            await db.awaitableWrite { tx in
                backupExportJobStore.setReachedResumptionPoint(.postBackupFile, tx: tx)
            }

            // Callers interested in detailed upload progress should use
            // BackupAttachmentUploadProgress or BackupAttachmentUploadTracker.
            try await performWithDummyProgress(progress.child(for: .attachmentUpload)) {
                logger.info("Listing media...")
                try await Retry.performWithBackoff(
                    maxAttempts: 3,
                    isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
                ) {
                    try await backupAttachmentCoordinator.queryListMediaIfNeeded()

                    if hasConsumedMediaTierCapacity {
                        // Run orphans now; include it in the list media progress for simplicity.
                        logger.info("Deleting orphaned attachments...")
                        try await backupAttachmentCoordinator.deleteOrphansIfNeeded()
                    }
                }

                logger.info("Uploading attachments...")
                let waitOnThumbnails = switch mode {
                case .bgProcessingTask: true
                case .manual: false
                }

                try await backupAttachmentCoordinator.backUpAllAttachments(waitOnThumbnails: waitOnThumbnails)
            }

            try await performWithDummyProgress(progress.child(for: .attachmentProcessing)) {
                switch mode {
                case .manual:
                    break
                case .bgProcessingTask:
                    try? await backupAttachmentCoordinator.restoreAttachmentsIfNeeded()
                }

                if !hasConsumedMediaTierCapacity {
                    logger.info("Deleting orphaned attachments...")
                    try await backupAttachmentCoordinator.deleteOrphansIfNeeded()
                }

                logger.info("Offloading attachments...")
                try await backupAttachmentCoordinator.offloadAttachmentsIfNeeded()
            }

            await db.awaitableWrite { tx in
                backupExportJobStore.setReachedResumptionPoint(nil, tx: tx)
            }

            logger.info("Done!")
        } catch let error as CancellationError {
            await db.awaitableWrite { tx in
                backupExportJobStore.setReachedResumptionPoint(nil, tx: tx)

                switch mode {
                case .bgProcessingTask:
                    self.backupSettingsStore.incrementBackgroundBackupErrorCount(tx: tx)
                case .manual:
                    self.backupSettingsStore.setIsBackupUploadQueueSuspended(true, tx: tx)
                }
            }

            logger.warn("Canceled!")
            throw error
        } catch let error {
            await db.awaitableWrite { tx in
                backupExportJobStore.setReachedResumptionPoint(nil, tx: tx)

                switch mode {
                case .bgProcessingTask:
                    self.backupSettingsStore.incrementBackgroundBackupErrorCount(tx: tx)
                case .manual:
                    self.backupSettingsStore.incrementInteractiveBackupErrorCount(tx: tx)
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

        await progress
            .addSource(withLabel: "", unitCount: 1)
            .complete()
    }
}

// MARK: -

private extension Error {
    var isRetryableNetworkOrUploadError: Bool {
        if isNetworkFailureOrTimeout || is5xxServiceResponse {
            return true
        }

        guard let uploadError = self as? Upload.Error else {
            return false
        }

        switch uploadError {
        case
            .networkError,
            .networkTimeout,
            .partialUpload,
            .uploadFailure(recovery: .restart),
            .uploadFailure(recovery: .resume):
            return true
        case .uploadFailure(recovery: .noMoreRetries):
            return false
        case .invalidUploadURL, .unsupportedEndpoint, .unexpectedResponseStatusCode, .missingFile, .unknown:
            return false
        }
    }
}
