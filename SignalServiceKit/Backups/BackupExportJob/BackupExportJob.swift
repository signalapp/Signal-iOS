//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public enum BackupExportJobStep: String, OWSSequentialProgressStep {
    case backupExport
    case backupUpload
    case listMedia
    case attachmentOrphaning
    case attachmentUpload
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
    case cancellationError
    case unregistered
    case needsWifi
    case backupKeyError
    // catch-all for errors thrown by backup steps
    case backupError(Error)
    case networkRequestError(Error)
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
        mode: BackupExportJobMode
    ) async throws(BackupExportJobError)
}

// MARK: -

extension NSNotification.Name {
    public static let backupExportJobDidRun = Notification.Name("BackupExportJob.backupExportJobDidRun")
}

// MARK: -

class BackupExportJobImpl: BackupExportJob {
    private let accountKeyStore: AccountKeyStore
    private let attachmentOffloadingManager: AttachmentOffloadingManager
    private let backupArchiveManager: BackupArchiveManager
    private let backupAttachmentDownloadManager: BackupAttachmentDownloadManager
    private let backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner
    private let backupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager
    private let backupKeyService: BackupKeyService
    private let backupListMediaManager: BackupListMediaManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let logger: PrefixedLogger
    private let messagePipelineSupervisor: MessagePipelineSupervisor
    private let messageProcessor: MessageProcessor
    private let orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager
    private let reachabilityManager: SSKReachabilityManager
    private let tsAccountManager: TSAccountManager

    public init(
        accountKeyStore: AccountKeyStore,
        attachmentOffloadingManager: AttachmentOffloadingManager,
        backupArchiveManager: BackupArchiveManager,
        backupAttachmentDownloadManager: BackupAttachmentDownloadManager,
        backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner,
        backupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager,
        backupKeyService: BackupKeyService,
        backupListMediaManager: BackupListMediaManager,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        messagePipelineSupervisor: MessagePipelineSupervisor,
        messageProcessor: MessageProcessor,
        orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager,
        reachabilityManager: SSKReachabilityManager,
        tsAccountManager: TSAccountManager
    ) {
        self.accountKeyStore = accountKeyStore
        self.attachmentOffloadingManager = attachmentOffloadingManager
        self.backupArchiveManager = backupArchiveManager
        self.backupAttachmentDownloadManager = backupAttachmentDownloadManager
        self.backupAttachmentDownloadQueueStatusManager = backupAttachmentDownloadQueueStatusManager
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.backupAttachmentUploadQueueRunner = backupAttachmentUploadQueueRunner
        self.backupAttachmentUploadQueueStatusManager = backupAttachmentUploadQueueStatusManager
        self.backupKeyService = backupKeyService
        self.backupListMediaManager = backupListMediaManager
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.logger = PrefixedLogger(prefix: "[Backups][ExportJob]")
        self.messagePipelineSupervisor = messagePipelineSupervisor
        self.messageProcessor = messageProcessor
        self.orphanedBackupAttachmentManager = orphanedBackupAttachmentManager
        self.reachabilityManager = reachabilityManager
        self.tsAccountManager = tsAccountManager
    }

    func exportAndUploadBackup(
        mode: BackupExportJobMode
    ) async throws(BackupExportJobError) {
        switch mode {
        case .manual:
            try await _exportAndUploadBackup(mode: mode)
        case .bgProcessingTask:
            await backupAttachmentDownloadQueueStatusManager.setIsMainAppAndActiveOverride(true)
            await backupAttachmentUploadQueueStatusManager.setIsMainAppAndActiveOverride(true)
            let result = await Result<Void, BackupExportJobError>(
                catching: { () async throws(BackupExportJobError) -> Void in
                    try await _exportAndUploadBackup(mode: mode)
                }
            )
            await backupAttachmentDownloadQueueStatusManager.setIsMainAppAndActiveOverride(false)
            await backupAttachmentUploadQueueStatusManager.setIsMainAppAndActiveOverride(false)
            try result.get()
        }
    }

    private func _exportAndUploadBackup(
        mode: BackupExportJobMode
    ) async throws(BackupExportJobError) {
        defer {
            NotificationCenter.default.postOnMainThread(
                name: .backupExportJobDidRun,
                object: nil
            )
        }
        logger.info("\(mode)")

        await db.awaitableWrite {
            self.backupSettingsStore.setIsBackupUploadQueueSuspended(false, tx: $0)
        }

        let (
            localIdentifiers,
            backupKey,
            shouldAllowBackupUploadsOnCellular,
            currentBackupPlan,
        ) = try db.read { (tx) throws(BackupExportJobError) in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                owsFailDebug("Creating a backup when unregistered?")
                throw .unregistered
            }

            guard let backupKey = try? accountKeyStore.getMessageRootBackupKey(aci: localIdentifiers.aci, tx: tx) else {
                owsFailDebug("Failed to read backup key")
                throw .backupKeyError
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
                throw .needsWifi
            }
        }

        logger.info("Waiting on message processing...")
        // We wait for message processing to finish before emitting a backup, to ensure
        // we put as much up-to-date message history into the backup as possible.
        // This is especially important for users with notifications disabled;
        // the launch of the BGProcessingTask may be the first chance we get
        // to fetch messages in a while, and its good practice to back those up.
        do throws(CancellationError) {
            try await messageProcessor.waitForFetchingAndProcessing()
        } catch {
            throw .cancellationError
        }

        let progress: OWSSequentialProgressRootSink<BackupExportJobStep>?
        let suspensionHandle: MessagePipelineSuspensionHandle?
        switch mode {
        case .manual(let _progress):
            progress = _progress
            suspensionHandle = nil

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
            suspensionHandle = messagePipelineSupervisor.suspendMessageProcessing(
                for: .backupBGProcessingTask
            )
        }

        defer {
            suspensionHandle?.invalidate()
        }

        do {
            logger.info("Exporting backup...")

            let uploadMetadata = try await backupArchiveManager.exportEncryptedBackup(
                localIdentifiers: localIdentifiers,
                backupPurpose: .remoteExport(
                    key: backupKey,
                    chatAuth: .implicit()
                ),
                progress: progress?.child(for: .backupExport)
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
                }
            )

            let hasConsumedMediaTierCapacity = db.read { tx in
                backupSettingsStore.hasConsumedMediaTierCapacity(tx: tx)
            }

            var downloadSuspendHandle: BackupAttachmentDownloadSuspensionHandle?
            if hasConsumedMediaTierCapacity {
                // If capacity is reached, we want to force a list media to run (to discover
                // any new things we can delete) and then run all our deletions.
                // In order to do so safely, we must first ensure the upload and download queues
                // aren't running, otherwise their state updates will race with list/delete ops.
                // Don't assign progress to these as both queues should be suspended and we are
                // just waiting on them to clean up any currently-running task.
                downloadSuspendHandle = await backupAttachmentDownloadQueueStatusManager.suspendDownloadsInMemory()
                try? await backupAttachmentDownloadManager.restoreAttachmentsIfNeeded()
                try? await backupAttachmentUploadQueueRunner.backUpAllAttachments(waitOnThumbnails: true)
            }

            logger.info("Listing media...")

            try await withEstimatedProgressUpdates(
                estimatedTimeToCompletion: 5,
                progress: progress?.child(for: .listMedia).addSource(withLabel: "", unitCount: 1),
            ) { [backupListMediaManager] in
                try await Retry.performWithBackoffForNetworkRequest(maxAttempts: 3) {
                    if hasConsumedMediaTierCapacity {
                        try await backupListMediaManager.forceQueryListMedia()
                    } else {
                        try await backupListMediaManager.queryListMediaIfNeeded()
                    }
                }
            }

            await downloadSuspendHandle?.release()

            logger.info("Deleting orphaned attachments...")

            try await withEstimatedProgressUpdates(
                estimatedTimeToCompletion: 2,
                progress: progress?.child(for: .attachmentOrphaning).addSource(withLabel: "", unitCount: 1),
            ) { [orphanedBackupAttachmentManager] in
                try await orphanedBackupAttachmentManager.runIfNeeded()
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
                        by: newUnitCount - attachmentUploadProgress.completedUnitCount
                    )
                })
            }

            let waitOnThumbnails = switch mode {
            case .bgProcessingTask: true
            case .manual: false
            }

            try await backupAttachmentUploadQueueRunner.backUpAllAttachments(waitOnThumbnails: waitOnThumbnails)
            _ = uploadObserver.take()
            uploadObserver = nil

            switch mode {
            case .manual:
                break
            case .bgProcessingTask:
                try? await backupAttachmentDownloadManager.restoreAttachmentsIfNeeded()
            }

            logger.info("Offloading attachments...")

            try await withEstimatedProgressUpdates(
                estimatedTimeToCompletion: 2,
                progress: progress?.child(for: .offloading).addSource(withLabel: "", unitCount: 1),
            ) { [attachmentOffloadingManager] in
                try await attachmentOffloadingManager.offloadAttachmentsIfNeeded()
            }

            logger.info("Done!")
        } catch is CancellationError {
            await db.awaitableWrite {
                switch mode {
                case .bgProcessingTask:
                    self.backupSettingsStore.setLastBackupFailed(tx: $0)
                case .manual:
                    self.backupSettingsStore.setIsBackupUploadQueueSuspended(true, tx: $0)
                }
            }

            throw .cancellationError
        } catch {
            await db.awaitableWrite {
                self.backupSettingsStore.setLastBackupFailed(tx: $0)
            }

            if error.isNetworkFailureOrTimeout || error.is5xxServiceResponse {
                throw .networkRequestError(error)
            } else {
                throw .backupError(error)
            }
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
        block: () async throws -> T
    ) async throws -> T {
        return try await performWithBackoff(
            maxAttempts: maxAttempts,
            isRetryable: { $0.isNetworkFailureOrTimeout || $0.is5xxServiceResponse },
            block: block
        )
    }
}
