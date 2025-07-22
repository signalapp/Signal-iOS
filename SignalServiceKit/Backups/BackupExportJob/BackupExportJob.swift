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

        /// Out of 100 (all must add to 100)
        fileprivate var percentAllocation: UInt64 {
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

public enum BackupExportJobError: Error {
    case cancellationError
    case unregistered
    case needsWifi
    case backupKeyError(BackupKeyMaterialError)
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
        onProgressUpdate: ((BackupExportJobProgress) -> Void)?
    ) async throws(BackupExportJobError)
}

// MARK: -

class BackupExportJobImpl: BackupExportJob {
    private let attachmentOffloadingManager: AttachmentOffloadingManager
    private let backupArchiveManager: BackupArchiveManager
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner
    private let backupIdManager: BackupIdManager
    private let backupKeyMaterial: BackupKeyMaterial
    private let backupListMediaManager: BackupListMediaManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: DB
    private let logger: PrefixedLogger
    private let messageProcessor: MessageProcessor
    private let orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager
    private let reachabilityManager: SSKReachabilityManager
    private let tsAccountManager: TSAccountManager

    public init(
        attachmentOffloadingManager: AttachmentOffloadingManager,
        backupArchiveManager: BackupArchiveManager,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner,
        backupIdManager: BackupIdManager,
        backupKeyMaterial: BackupKeyMaterial,
        backupListMediaManager: BackupListMediaManager,
        backupSettingsStore: BackupSettingsStore,
        db: DB,
        messageProcessor: MessageProcessor,
        orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager,
        reachabilityManager: SSKReachabilityManager,
        tsAccountManager: TSAccountManager
    ) {
        self.attachmentOffloadingManager = attachmentOffloadingManager
        self.backupArchiveManager = backupArchiveManager
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.backupAttachmentUploadQueueRunner = backupAttachmentUploadQueueRunner
        self.backupIdManager = backupIdManager
        self.backupKeyMaterial = backupKeyMaterial
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
        onProgressUpdate: ((BackupExportJobProgress) -> Void)?
    ) async throws(BackupExportJobError) {
        let (
            localIdentifiers,
            backupKey,
            shouldAllowBackupUploadsOnCellular,
        ) = try db.read { (tx) throws(BackupExportJobError) in
            let backupKey: BackupKey
            do throws(BackupKeyMaterialError) {
                backupKey = try backupKeyMaterial.backupKey(type: .messages, tx: tx)
            } catch {
                throw .backupKeyError(error)
            }
            return (
                tsAccountManager.localIdentifiers(tx: tx),
                backupKey,
                backupSettingsStore.shouldAllowBackupUploadsOnCellular(tx: tx),
            )
        }

        guard let localIdentifiers else {
            owsFailDebug("Creating a backup when unregistered?")
            throw .unregistered
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
                didSet {
                    onProgressUpdate(latestProgress)
                }
            }

            init(
                onProgressUpdate: @escaping (BackupExportJobProgress) -> Void,
                latestProgress: BackupExportJobProgress
            ) {
                self.onProgressUpdate = onProgressUpdate
                self.latestProgress = latestProgress
            }
        }
        let progressUpdater: ProgressUpdater? = onProgressUpdate.map {
            ProgressUpdater(
                onProgressUpdate: $0,
                latestProgress: BackupExportJobProgress(
                    step: .registerBackupId,
                    overallProgress: .zero
                )
            )
        }

        let progress: OWSProgressSink?
        if let progressUpdater {
            progress = OWSProgress.createSink { progressUpdate in
                progressUpdater.latestProgress.overallProgress = progressUpdate
            }
        } else {
            progress = nil
        }

        let registerBackupIdProgress = await progress?.addSource(.registerBackupId)
        let backupExportProgress = await progress?.addChild(.backupExport)
        let backupUploadProgress = await progress?.addChild(.backupUpload)
        let listMediaProgress = await progress?.addSource(.listMedia)
        let attachmentOrphaningProgress = await progress?.addSource(.attachmentOrphaning)
        let attachmentUploadProgress = await progress?.addSource(.attachmentUpload)
        let offloadingProgress = await progress?.addSource(.offloading)

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
                backupKey: backupKey,
                backupPurpose: .remoteBackup,
                progress: backupExportProgress
            )

            logger.info("Uploading backup...")
            progressUpdater?.latestProgress.step = .backupUpload

            try await Retry.performWithBackoffForNetworkRequest(maxAttempts: 3) {
                _ = try await backupArchiveManager.uploadEncryptedBackup(
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
        return await self.addSource(withLabel: step.rawValue, unitCount: step.percentAllocation)
    }

    func addChild(_ step: BackupExportJobProgress.Step) async -> OWSProgressSink {
        return await self.addChild(withLabel: step.rawValue, unitCount: step.percentAllocation)
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
