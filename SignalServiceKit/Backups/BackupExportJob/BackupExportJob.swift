//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public enum BackupExportProgressStep: String {
    case registerBackupId
    case backupExport
    case backupUpload
    case listMedia
    case attachmentOrphaning
    case attachmentUpload
    case offloading

    /// Out of 100 (all must add to 100)
    var percentAllocation: UInt64 {
        switch self {
        case .registerBackupId:
            return 1
        case .backupExport:
            return 40
        case .backupUpload:
            return 10
        case .listMedia:
            return 5
        case .attachmentOrphaning:
            return 2
        case .attachmentUpload:
            return 40
        case .offloading:
            return 2
        }
    }
}

public protocol BackupExportJob {

    /// Export and upload a backup, then run all ancillary jobs
    /// (attachment upload, orphaning, and offloading).
    ///
    /// Cooperatively cancellable.
    func exportAndUploadBackup(
        progress: OWSProgressSink?
    ) async throws
}

public class BackupExportJobImpl: BackupExportJob {

    private let attachmentOffloadingManager: AttachmentOffloadingManager
    private let backupArchiveManager: BackupArchiveManager
    private let backupAttachmentUploadProgress: BackupAttachmentUploadProgress
    private let backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner
    private let backupIdManager: BackupIdManager
    private let backupKeyMaterial: BackupKeyMaterial
    private let backupListMediaManager: BackupListMediaManager
    private let db: DB
    private let orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager
    private let tsAccountManager: TSAccountManager

    private let logger = PrefixedLogger(prefix: "[BackupExportJob]")

    public init(
        attachmentOffloadingManager: AttachmentOffloadingManager,
        backupArchiveManager: BackupArchiveManager,
        backupAttachmentUploadProgress: BackupAttachmentUploadProgress,
        backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner,
        backupIdManager: BackupIdManager,
        backupKeyMaterial: BackupKeyMaterial,
        backupListMediaManager: BackupListMediaManager,
        db: DB,
        orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager,
        tsAccountManager: TSAccountManager
    ) {
        self.attachmentOffloadingManager = attachmentOffloadingManager
        self.backupArchiveManager = backupArchiveManager
        self.backupAttachmentUploadProgress = backupAttachmentUploadProgress
        self.backupAttachmentUploadQueueRunner = backupAttachmentUploadQueueRunner
        self.backupIdManager = backupIdManager
        self.backupKeyMaterial = backupKeyMaterial
        self.backupListMediaManager = backupListMediaManager
        self.db = db
        self.orphanedBackupAttachmentManager = orphanedBackupAttachmentManager
        self.tsAccountManager = tsAccountManager
    }

    public func exportAndUploadBackup(
        progress: OWSProgressSink?
    ) async throws {
        let (
            localIdentifiers,
            backupKey,
        ) = try db.read { tx in
            return (
                tsAccountManager.localIdentifiers(tx: tx),
                try backupKeyMaterial.backupKey(type: .messages, tx: tx),
            )
        }

        guard let localIdentifiers else {
            throw OWSAssertionError("Creating a backup when unregistered?")
        }

        logger.info("Starting...")

        let registerBackupIdProgress = await progress?.addSource(.registerBackupId)
        let backupExportProgress = await progress?.addChild(.backupExport)
        let backupUploadProgress = await progress?.addChild(.backupUpload)
        let listMediaProgress = await progress?.addSource(.listMedia)
        let attachmentOrphaningProgress = await progress?.addSource(.attachmentOrphaning)
        let attachmentUploadProgress = await progress?.addSource(.attachmentUpload)
        let offloadingProgress = await progress?.addSource(.offloading)

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

        let uploadMetadata = try await backupArchiveManager.exportEncryptedBackup(
            localIdentifiers: localIdentifiers,
            backupKey: backupKey,
            backupPurpose: .remoteBackup,
            progress: backupExportProgress
        )

        logger.info("Uploading backup...")

        _ = try await backupArchiveManager.uploadEncryptedBackup(
            metadata: uploadMetadata,
            registeredBackupIDToken: registeredBackupIDToken,
            localIdentifiers: localIdentifiers,
            auth: .implicit(),
            progress: backupUploadProgress,
        )

        logger.info("Listing media...")

        try await withEstimatedProgressUpdates(
            estimatedTimeToCompletion: 5,
            progress: listMediaProgress,
        ) { [backupListMediaManager] in
            try await backupListMediaManager.queryListMediaIfNeeded()
        }

        logger.info("Deleting orphaned attachments...")

        try await withEstimatedProgressUpdates(
            estimatedTimeToCompletion: 2,
            progress: attachmentOrphaningProgress,
        ) { [orphanedBackupAttachmentManager] in
            try await orphanedBackupAttachmentManager.runIfNeeded()
        }

        logger.info("Uploading attachments...")

        var uploadObserver: BackupAttachmentUploadProgress.Observer?
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

        try await withEstimatedProgressUpdates(
            estimatedTimeToCompletion: 2,
            progress: offloadingProgress,
        ) { [attachmentOffloadingManager] in
            try await attachmentOffloadingManager.offloadAttachmentsIfNeeded()
        }

        logger.info("Done!")
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

    func addSource(_ step: BackupExportProgressStep) async -> OWSProgressSource {
        return await self.addSource(withLabel: step.rawValue, unitCount: step.percentAllocation)
    }

    func addChild(_ step: BackupExportProgressStep) async -> OWSProgressSink {
        return await self.addChild(withLabel: step.rawValue, unitCount: step.percentAllocation)
    }
}
