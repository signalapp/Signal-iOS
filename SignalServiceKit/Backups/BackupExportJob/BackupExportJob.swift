//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public struct BackupExportJobProgress {
    public enum Step: String {
        case registerBackupId
        case backupExport
        case backupUpload
        case listMedia
        case attachmentOrphaning
        case attachmentUpload
        case offloading

        /// Amount of the overall job progress, relative to other `Step`s, that
        /// a given step should take.
        fileprivate var relativeAllocation: UInt64 {
            switch self {
            case .registerBackupId: 1
            case .backupExport: 40
            case .backupUpload: 10
            case .listMedia: 5
            case .attachmentOrphaning: 2
            case .attachmentUpload: 40
            case .offloading: 2
            }
        }
    }

    public fileprivate(set) var step: Step
    public fileprivate(set) var overallProgress: OWSProgress

#if DEBUG
    public static func forPreview(_ step: Step, _ percentComplete: Float) -> BackupExportJobProgress {
        return BackupExportJobProgress(step: step, overallProgress: .forPreview(percentComplete))
    }
#endif
}

public enum BackupExportJobMode {
    case manual(onProgressUpdate: ((BackupExportJobProgress) -> Void))
    case bgProcessingTask
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

class BackupExportJobImpl: BackupExportJob {
    private let accountKeyStore: AccountKeyStore
    private let attachmentOffloadingManager: AttachmentOffloadingManager
    private let backupArchiveManager: BackupArchiveManager
    private let backupAttachmentDownloadManager: BackupAttachmentDownloadManager
    private let backupAttachmentDownloadQueueStatusManager: BackupAttachmentDownloadQueueStatusManager
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner
    private let backupAttachmentUploadQueueStatusManager: BackupAttachmentUploadQueueStatusManager
    private let backupIdManager: BackupIdManager
    private let backupListMediaManager: BackupListMediaManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let logger: PrefixedLogger
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
        backupIdManager: BackupIdManager,
        backupListMediaManager: BackupListMediaManager,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
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
        self.backupIdManager = backupIdManager
        self.backupListMediaManager = backupListMediaManager
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.logger = PrefixedLogger(prefix: "[BackupExportJob]")
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

        class ProgressUpdater {
            private let onProgressUpdate: (BackupExportJobProgress) -> Void

            var latestProgress: BackupExportJobProgress {
                didSet { onProgressUpdate(latestProgress) }
            }
            var progressSink: OWSProgressSink!

            init(onProgressUpdate: @escaping (BackupExportJobProgress) -> Void) {
                self.onProgressUpdate = onProgressUpdate

                self.latestProgress = BackupExportJobProgress(
                    step: .registerBackupId,
                    overallProgress: .zero
                )
                self.progressSink = OWSProgress.createSink { [weak self] progressUpdate in
                    self?.latestProgress.overallProgress = progressUpdate
                }
            }
        }
        let progressUpdater: ProgressUpdater?
        let registerBackupIdProgress: OWSProgressSource?
        let backupExportProgress: OWSProgressSink?
        let backupUploadProgress: OWSProgressSink?
        let listMediaProgress: OWSProgressSource?
        let attachmentOrphaningProgress: OWSProgressSource?
        let attachmentUploadProgress: OWSProgressSource?
        let offloadingProgress: OWSProgressSource?

        switch mode {
        case .manual(let onProgressUpdate):
            progressUpdater = ProgressUpdater(onProgressUpdate: onProgressUpdate)
            registerBackupIdProgress = await progressUpdater?.progressSink.addSource(.registerBackupId)
            backupExportProgress = await progressUpdater?.progressSink.addChild(.backupExport)
            backupUploadProgress = await progressUpdater?.progressSink.addChild(.backupUpload)
            listMediaProgress = await progressUpdater?.progressSink.addSource(.listMedia)

            // These steps should, on the free tier, be no-ops. We'll still run
            // them below, but as a nicety exclude them from progress reporting.
            switch currentBackupPlan {
            case .disabled, .disabling, .free:
                attachmentOrphaningProgress = nil
                attachmentUploadProgress = nil
                offloadingProgress = nil
            case .paid, .paidExpiringSoon, .paidAsTester:
                attachmentOrphaningProgress = await progressUpdater?.progressSink.addSource(.attachmentOrphaning)
                attachmentUploadProgress = await progressUpdater?.progressSink.addSource(.attachmentUpload)
                offloadingProgress = await progressUpdater?.progressSink.addSource(.offloading)
            }
        case .bgProcessingTask:
            progressUpdater = nil
            registerBackupIdProgress = nil
            backupExportProgress = nil
            backupUploadProgress = nil
            listMediaProgress = nil
            attachmentOrphaningProgress = nil
            attachmentUploadProgress = nil
            offloadingProgress = nil
        }

        do {
            logger.info("Starting...")

            let registeredBackupIDToken = try await withEstimatedProgressUpdates(
                estimatedTimeToCompletion: 0.5,
                progress: registerBackupIdProgress,
            ) { [backupIdManager] in
                try await backupIdManager.registerBackupId(
                    localIdentifiers: localIdentifiers,
                    auth: .implicit()
                )
            }

            logger.info("Exporting backup...")
            progressUpdater?.latestProgress.step = .backupExport

            let uploadMetadata = try await backupArchiveManager.exportEncryptedBackup(
                localIdentifiers: localIdentifiers,
                backupPurpose: .remoteExport(
                    key: backupKey,
                    chatAuth: .implicit()
                ),
                progress: backupExportProgress
            )

            logger.info("Uploading backup...")
            progressUpdater?.latestProgress.step = .backupUpload

            try await Retry.performWithBackoffForNetworkRequest(maxAttempts: 3) {
                _ = try await backupArchiveManager.uploadEncryptedBackup(
                    backupKey: backupKey,
                    metadata: uploadMetadata,
                    registeredBackupIDToken: registeredBackupIDToken,
                    auth: .implicit(),
                    progress: backupUploadProgress,
                )
            }

            logger.info("Listing media...")
            progressUpdater?.latestProgress.step = .listMedia

            try await withEstimatedProgressUpdates(
                estimatedTimeToCompletion: 5,
                progress: listMediaProgress,
            ) { [backupListMediaManager] in
                try await Retry.performWithBackoffForNetworkRequest(maxAttempts: 3) {
                    try await backupListMediaManager.queryListMediaIfNeeded()
                }
            }

            logger.info("Deleting orphaned attachments...")
            progressUpdater?.latestProgress.step = .attachmentOrphaning

            try await withEstimatedProgressUpdates(
                estimatedTimeToCompletion: 2,
                progress: attachmentOrphaningProgress,
            ) { [orphanedBackupAttachmentManager] in
                try await orphanedBackupAttachmentManager.runIfNeeded()
            }

            logger.info("Uploading attachments...")
            progressUpdater?.latestProgress.step = .attachmentUpload

            var uploadObserver: BackupAttachmentUploadProgressObserver?
            if let attachmentUploadProgress {
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
            try await backupAttachmentUploadQueueRunner.backUpAllAttachments()
            _ = uploadObserver.take()
            uploadObserver = nil

            switch mode {
            case .manual:
                break
            case .bgProcessingTask:
                try? await backupAttachmentDownloadManager.restoreAttachmentsIfNeeded()
            }

            logger.info("Offloading attachments...")
            progressUpdater?.latestProgress.step = .offloading

            try await withEstimatedProgressUpdates(
                estimatedTimeToCompletion: 2,
                progress: offloadingProgress,
            ) { [attachmentOffloadingManager] in
                try await attachmentOffloadingManager.offloadAttachmentsIfNeeded()
            }

            logger.info("Done!")
        } catch is CancellationError {
            throw .cancellationError
        } catch let error {
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

fileprivate extension OWSProgressSink {

    func addSource(_ step: BackupExportJobProgress.Step) async -> OWSProgressSource {
        return await self.addSource(withLabel: step.rawValue, unitCount: step.relativeAllocation)
    }

    func addChild(_ step: BackupExportJobProgress.Step) async -> OWSProgressSink {
        return await self.addChild(withLabel: step.rawValue, unitCount: step.relativeAllocation)
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
