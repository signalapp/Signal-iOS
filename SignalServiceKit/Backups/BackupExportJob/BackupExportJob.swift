//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public enum BackupExportJobStep: String, OWSSequentialProgressStep {
    case backupExport
    case backupUpload
    case listMedia
    case attachmentUpload
    case attachmentOrphaning
    case offloading

    /// Amount of the overall job progress, relative to other `Step`s, that
    /// a given step should take.
    public var progressUnitCount: UInt64 {
        switch self {
        case .backupExport: 40
        case .backupUpload: 10
        case .listMedia: 5
        case .attachmentOrphaning: 3
        case .attachmentUpload: 40
        case .offloading: 2
        }
    }
}

public enum BackupExportJobMode: CustomStringConvertible {
    case manual(OWSSequentialProgressRootSink<BackupExportJobStep>)
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

/// Responsible for performing direct and ancillary steps to "export a Backup".
///
/// - Important
/// Callers should be careful about the possibility of running overlapping
/// Backup export jobs, and may prefer to call ``BackupExportJobRunner`` rather
/// than this type directly.
public protocol BackupExportJob {

    /// Export and upload a backup, then run all ancillary jobs
    /// (attachment upload, orphaning, and offloading).
    ///
    /// Cooperatively cancellable.
    func exportAndUploadBackup(
        mode: BackupExportJobMode,
    ) async throws
}

// MARK: -

class BackupExportJobImpl: BackupExportJob {
    private let accountKeyStore: AccountKeyStore
    private let backupArchiveManager: BackupArchiveManager
    private let backupAttachmentCoordinator: BackupAttachmentCoordinator
    private let backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let backupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager
    private let backupKeyService: BackupKeyService
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let logger: PrefixedLogger
    private let messagePipelineSupervisor: MessagePipelineSupervisor
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
        backupKeyService: BackupKeyService,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        messagePipelineSupervisor: MessagePipelineSupervisor,
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
        self.backupKeyService = backupKeyService
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.logger = PrefixedLogger(prefix: "[Backups][ExportJob]")
        self.messagePipelineSupervisor = messagePipelineSupervisor
        self.messageProcessor = messageProcessor
        self.reachabilityManager = reachabilityManager
        self.tsAccountManager = tsAccountManager
    }

    func exportAndUploadBackup(
        mode: BackupExportJobMode,
    ) async throws {
        switch mode {
        case .manual:
            try await _exportAndUploadBackup(mode: mode)
        case .bgProcessingTask:
            await backupAttachmentDownloadQueueStatusManager.setIsMainAppAndActiveOverride(true)
            await backupAttachmentUploadQueueStatusManager.setIsMainAppAndActiveOverride(true)
            let result = await Result(
                catching: { () async throws -> Void in
                    try await _exportAndUploadBackup(mode: mode)
                },
            )
            await backupAttachmentDownloadQueueStatusManager.setIsMainAppAndActiveOverride(false)
            await backupAttachmentUploadQueueStatusManager.setIsMainAppAndActiveOverride(false)
            try result.get()
        }
    }

    private func _exportAndUploadBackup(
        mode: BackupExportJobMode,
    ) async throws {
        let logger = logger.suffixed(with: "[\(mode)]")
        logger.info("Starting...")

        await db.awaitableWrite {
            self.backupSettingsStore.setIsBackupUploadQueueSuspended(false, tx: $0)
        }

        let (
            localIdentifiers,
            backupKey,
            shouldAllowBackupUploadsOnCellular,
            currentBackupPlan,
        ) = try db.read { tx throws in
            guard
                tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
                let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)
            else {
                throw NotRegisteredError()
            }

            guard let backupKey = try? accountKeyStore.getMessageRootBackupKey(aci: localIdentifiers.aci, tx: tx) else {
                throw OWSAssertionError("Missing or invalid message root backup key.")
            }

            return (
                localIdentifiers,
                backupKey,
                backupSettingsStore.shouldAllowBackupUploadsOnCellular(tx: tx),
                backupSettingsStore.backupPlan(tx: tx),
            )
        }

        if !shouldAllowBackupUploadsOnCellular {
            // The job requires uploading the backup; if we're not on wifi
            // and therefore can't upload don't even bother generating the backup.
            if !reachabilityManager.isReachable(via: .wifi) {
                logger.info("Giving up; not connected to wifi & cellular uploads disabled")
                throw BackupExportJobError.needsWifi
            }
        }

        // We wait for message processing to finish before emitting a backup, to ensure
        // we put as much up-to-date message history into the backup as possible.
        // This is especially important for users with notifications disabled;
        // the launch of the BGProcessingTask may be the first chance we get
        // to fetch messages in a while, and its good practice to back those up.
        logger.info("Waiting on message processing...")
        try await messageProcessor.waitForFetchingAndProcessing()

        let progress: OWSSequentialProgressRootSink<BackupExportJobStep>?
        switch mode {
        case .manual(let _progress):
            progress = _progress

            // These steps should, on the free tier, be no-ops. We'll still run
            // them below, but as a nicety exclude them from progress reporting.
            switch currentBackupPlan {
            case .disabled, .disabling, .free:
                _ = await progress?.child(for: .attachmentOrphaning)
                    .addSource(withLabel: "", unitCount: 0)
                _ = await progress?.child(for: .attachmentUpload)
                    .addSource(withLabel: "", unitCount: 0)
                _ = await progress?.child(for: .offloading)
                    .addSource(withLabel: "", unitCount: 0)
            case .paid, .paidExpiringSoon, .paidAsTester:
                break
            }
        case .bgProcessingTask:
            progress = nil
        }

        do {
            logger.info("Exporting backup...")

            let uploadMetadata = try await backupArchiveManager.exportEncryptedBackup(
                localIdentifiers: localIdentifiers,
                backupPurpose: .remoteExport(
                    key: backupKey,
                    chatAuth: .implicit(),
                ),
                progress: progress?.child(for: .backupExport),
            )

            logger.info("Uploading backup...")

            try await Retry.performWithBackoff(
                maxAttempts: 3,
                isRetryable: { error in
                    if error.isNetworkFailureOrTimeout || error.is5xxServiceResponse {
                        return true
                    }

                    guard let uploadError = error as? Upload.Error else {
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
                },
                block: {
                    _ = try await backupArchiveManager.uploadEncryptedBackup(
                        backupKey: backupKey,
                        metadata: uploadMetadata,
                        auth: .implicit(),
                        progress: progress?.child(for: .backupUpload),
                    )
                },
            )

            logger.info("Listing media...")

            let hasConsumedMediaTierCapacity = db.read { tx in
                backupSettingsStore.hasConsumedMediaTierCapacity(tx: tx)
            }

            try await withEstimatedProgressUpdates(
                estimatedTimeToCompletion: 5,
                progress: progress?.child(for: .listMedia).addSource(withLabel: "", unitCount: 1),
            ) { [backupAttachmentCoordinator, logger] in
                try await Retry.performWithBackoffForNetworkRequest(maxAttempts: 3) {
                    try await backupAttachmentCoordinator.queryListMediaIfNeeded()
                    if hasConsumedMediaTierCapacity {
                        // Run orphans now; include it in the list media progress for simplicity.
                        logger.info("Deleting orphaned attachments...")
                        try await backupAttachmentCoordinator.deleteOrphansIfNeeded()
                    }
                }
            }

            logger.info("Uploading attachments...")

            var uploadObserver: BackupAttachmentUploadProgressObserver?
            if
                let attachmentUploadProgress = await progress?
                    .child(for: .attachmentUpload)
                    .addSource(withLabel: "", unitCount: 100)
            {
                uploadObserver = try await backupAttachmentUploadProgress.addObserver({ progress in
                    let newUnitCount = UInt64((Float(attachmentUploadProgress.totalUnitCount) * progress.percentComplete).rounded())
                    guard newUnitCount > attachmentUploadProgress.completedUnitCount else {
                        return
                    }
                    attachmentUploadProgress.incrementCompletedUnitCount(
                        by: newUnitCount - attachmentUploadProgress.completedUnitCount,
                    )
                })
            }

            let waitOnThumbnails = switch mode {
            case .bgProcessingTask: true
            case .manual: false
            }

            try await backupAttachmentCoordinator.backUpAllAttachments(waitOnThumbnails: waitOnThumbnails)
            _ = uploadObserver.take()
            uploadObserver = nil

            switch mode {
            case .manual:
                break
            case .bgProcessingTask:
                try? await backupAttachmentCoordinator.restoreAttachmentsIfNeeded()
            }

            if !hasConsumedMediaTierCapacity {
                logger.info("Deleting orphaned attachments...")

                try await withEstimatedProgressUpdates(
                    estimatedTimeToCompletion: 2,
                    progress: progress?.child(for: .attachmentOrphaning).addSource(withLabel: "", unitCount: 1),
                ) { [backupAttachmentCoordinator] in
                    try await backupAttachmentCoordinator.deleteOrphansIfNeeded()
                }
            }

            logger.info("Offloading attachments...")

            try await withEstimatedProgressUpdates(
                estimatedTimeToCompletion: 2,
                progress: progress?.child(for: .offloading).addSource(withLabel: "", unitCount: 1),
            ) { [backupAttachmentCoordinator] in
                try await backupAttachmentCoordinator.offloadAttachmentsIfNeeded()
            }

            logger.info("Done!")
        } catch let error as CancellationError {
            await db.awaitableWrite {
                switch mode {
                case .bgProcessingTask:
                    self.backupSettingsStore.incrementBackgroundBackupErrorCount(tx: $0)
                case .manual:
                    self.backupSettingsStore.setIsBackupUploadQueueSuspended(true, tx: $0)
                }
            }

            logger.warn("Canceled!")
            throw error
        } catch let error {
            await db.awaitableWrite {
                switch mode {
                case .bgProcessingTask:
                    self.backupSettingsStore.incrementBackgroundBackupErrorCount(tx: $0)
                case .manual:
                    self.backupSettingsStore.incrementInteractiveBackupErrorCount(tx: $0)
                }
            }

            logger.warn("Failed! \(error)")
            throw error
        }
    }

    private func withEstimatedProgressUpdates<T>(
        estimatedTimeToCompletion: TimeInterval,
        progress: OWSProgressSource?,
        work: @escaping () async throws -> T,
    ) async rethrows -> T {
        guard let progress else {
            return try await work()
        }
        return try await progress.updatePeriodically(estimatedTimeToCompletion: estimatedTimeToCompletion, work: work)
    }
}

// MARK: -

private extension Retry {
    static func performWithBackoffForNetworkRequest<T>(
        maxAttempts: Int,
        block: () async throws -> T,
    ) async throws -> T {
        return try await performWithBackoff(
            maxAttempts: maxAttempts,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
            block: block,
        )
    }
}
