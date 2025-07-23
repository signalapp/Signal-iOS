//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// In charge of deleting attachments off the backup cdn after they've been deleted locally (or otherwise orphaned).
public protocol OrphanedBackupAttachmentManager {

    /// Called when creating an attachment with the provided media name, or
    /// when updating an attachment (e.g. after downloading) with the media name.
    /// Required to clean up any pending orphan delete jobs that should now be
    /// invalidated.
    ///
    /// Say we had an attachment with mediaId abcd and deleted it, without having
    /// deleted it on the backup cdn. Later, we list all backup media on the server,
    /// and see mediaId abcd there with no associated local attachment.
    /// We add it to the orphan table to schedule for deletion.
    /// Later, we either send or receive (and download) an attachment with the same
    /// mediaId (same file contents). We don't want to delete the upload anymore,
    /// so dequeue it for deletion.
    func didCreateOrUpdateAttachment(
        withMediaName mediaName: String,
        tx: DBWriteTransaction
    )

    /// Orphan all existing media tier uploads for an attachment, marking them for
    /// deletion from the media tier CDN.
    /// Do this before wiping media tier info on an attachment. Note that this doesn't
    /// need to be done when deleting an attachment, as a SQLite trigger handles
    /// deletion automatically.
    func orphanExistingMediaTierUploads(
        of attachment: Attachment,
        tx: DBWriteTransaction
    ) throws

    /// Run all remote deletions, returning when finished. Supports cooperative cancellation.
    /// Should only be run after backup uploads have finished to avoid races.
    func runIfNeeded() async throws
}

public class OrphanedBackupAttachmentManagerImpl: OrphanedBackupAttachmentManager {

    private let appReadiness: AppReadiness
    private let backupKeyMaterial: BackupKeyMaterial
    private let db: any DB
    private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore
    private let taskQueue: TaskQueueLoader<TaskRunner>
    private let tsAccountManager: TSAccountManager

    public init(
        appReadiness: AppReadiness,
        attachmentStore: AttachmentStore,
        backupKeyMaterial: BackupKeyMaterial,
        backupRequestManager: BackupRequestManager,
        dateProvider: @escaping DateProvider,
        db: any DB,
        orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
        tsAccountManager: TSAccountManager
    ) {
        self.appReadiness = appReadiness
        self.backupKeyMaterial = backupKeyMaterial
        self.db = db
        self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
        self.tsAccountManager = tsAccountManager
        let taskRunner = TaskRunner(
            attachmentStore: attachmentStore,
            backupKeyMaterial: backupKeyMaterial,
            backupRequestManager: backupRequestManager,
            db: db,
            orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
            tsAccountManager: tsAccountManager
        )
        self.taskQueue = TaskQueueLoader(
            maxConcurrentTasks: 1, /* one at a time, speed isn't critical */
            dateProvider: dateProvider,
            db: db,
            runner: taskRunner
        )
    }

    public func didCreateOrUpdateAttachment(
        withMediaName mediaName: String,
        tx: DBWriteTransaction
    ) {
        guard FeatureFlags.Backups.supported else {
            return
        }
        try! OrphanedBackupAttachment
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaName) == mediaName)
            .deleteAll(tx.database)
        for type in OrphanedBackupAttachment.SizeType.allCases {
            do {
                let mediaId = try backupKeyMaterial.mediaEncryptionMetadata(
                    mediaName: {
                        switch type {
                        case .fullsize:
                            mediaName
                        case .thumbnail:
                            AttachmentBackupThumbnail
                                .thumbnailMediaName(fullsizeMediaName: mediaName)
                        }
                    }(),
                    // Doesn't matter what we use, we just want the mediaId.
                    type: .outerLayerFullsizeOrThumbnail,
                    tx: tx
                ).mediaId
                try! OrphanedBackupAttachment
                    .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == mediaId)
                    .deleteAll(tx.database)
            } catch let backupKeyMaterialError {
                switch backupKeyMaterialError {
                case .missingMediaRootBackupKey:
                    // If we don't have root keys, we definitely don't have any
                    // orphaned backup media. quit.
                    continue
                case .missingMessageBackupKey, .derivationError:
                    owsFailDebug("Unexpected encryption material error")
                }
            }

        }
    }

    public func orphanExistingMediaTierUploads(
        of attachment: Attachment,
        tx: DBWriteTransaction
    ) throws {
        guard let mediaName = attachment.mediaName else {
            // If we didn't have a mediaName assigned,
            // there's no uploads to orphan (that we know of locally).
            return
        }
        if
            let mediaTierInfo = attachment.mediaTierInfo,
            let cdnNumber = mediaTierInfo.cdnNumber
        {
            var fullsizeOrphanRecord = OrphanedBackupAttachment.locallyOrphaned(
                cdnNumber: cdnNumber,
                mediaName: mediaName,
                type: .fullsize
            )
            try orphanedBackupAttachmentStore.insert(&fullsizeOrphanRecord, tx: tx)
        }
        if
            let thumbnailMediaTierInfo = attachment.thumbnailMediaTierInfo,
            let cdnNumber = thumbnailMediaTierInfo.cdnNumber
        {
            var fullsizeOrphanRecord = OrphanedBackupAttachment.locallyOrphaned(
                cdnNumber: cdnNumber,
                mediaName: AttachmentBackupThumbnail.thumbnailMediaName(
                    fullsizeMediaName: mediaName
                ),
                type: .thumbnail
            )
            try orphanedBackupAttachmentStore.insert(&fullsizeOrphanRecord, tx: tx)
        }
    }

    public func runIfNeeded() async throws {
        try await appReadiness.waitForAppReady()
        try Task.checkCancellation()
        guard tsAccountManager.localIdentifiersWithMaybeSneakyTransaction != nil else {
            return
        }
        try await taskQueue.loadAndRunTasks()
    }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let attachmentStore: AttachmentStore
        private let backupKeyMaterial: BackupKeyMaterial
        private let backupRequestManager: BackupRequestManager
        private let db: any DB
        private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore
        private let tsAccountManager: TSAccountManager

        let store: TaskStore

        init(
            attachmentStore: AttachmentStore,
            backupKeyMaterial: BackupKeyMaterial,
            backupRequestManager: BackupRequestManager,
            db: any DB,
            orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
            tsAccountManager: TSAccountManager
        ) {
            self.attachmentStore = attachmentStore
            self.backupKeyMaterial = backupKeyMaterial
            self.backupRequestManager = backupRequestManager
            self.db = db
            self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
            self.tsAccountManager = tsAccountManager

            self.store = TaskStore(orphanedBackupAttachmentStore: orphanedBackupAttachmentStore)
        }

        private actor ErrorCounts {
            var counts = [TaskRecord.IDType: Int]()

            func updateCount(_ id: TaskRecord.IDType) -> Int {
                let count = (counts[id] ?? 0) + 1
                counts[id] = count
                return count
            }
        }

        private let errorCounts = ErrorCounts()

        func runTask(record: Store.Record, loader: TaskQueueLoader<TaskRunner>) async -> TaskRecordResult {
            guard FeatureFlags.Backups.supported else {
                return .cancelled
            }

            let (localAci, registrationState) = db.read { tx in
                return (
                    tsAccountManager.localIdentifiers(tx: tx)?.aci,
                    tsAccountManager.registrationState(tx: tx),
                )
            }

            switch registrationState {
            case
                    .unregistered,
                    .reregistering,
                    .deregistered,
                    .transferringIncoming,
                    .transferringPrimaryOutgoing,
                    .transferred:
                // These states are potentially temporary. Return a retryable error
                // but cancel the task.
                Logger.info("Stopping when unregistered")
                let error = OWSRetryableError()
                try? await loader.stop(reason: error)
                return .retryableError(error)
            case
                    .relinking,
                    .delinked,
                    .transferringLinkedOutgoing,
                    .provisioned:
                // Linked devices never issue these delete requests.
                // Cancel the task so we never run it again.
                return .cancelled
            case .registered:
                break
            }

            guard let localAci else {
                let error = OWSAssertionError("Deleting without being registered")
                try? await loader.stop(reason: error)
                return .retryableError(error)
            }

            let mediaId: Data

            if let recordMediaId = record.record.mediaId {
                mediaId = recordMediaId
            } else if let type = record.record.type, let mediaName = record.record.mediaName {
                let mediaNameToUse: String
                switch type {
                case .fullsize:
                    mediaNameToUse = mediaName
                case .thumbnail:
                    mediaNameToUse = AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName)
                }

                do {
                    (mediaId) = try db.read { tx in
                        (
                            try backupKeyMaterial.mediaEncryptionMetadata(
                                mediaName: mediaNameToUse,
                                // Doesn't matter what we use, we just want the mediaId.
                                type: .outerLayerFullsizeOrThumbnail,
                                tx: tx
                            ).mediaId
                        )
                    }
                } catch let error {
                    Logger.error("Failed to generate media IDs")
                    return .unretryableError(error)
                }
            } else {
                return .unretryableError(OWSAssertionError("Invalid record"))
            }

            let backupAuth: BackupServiceAuth
            do {
                backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                    for: .media,
                    localAci: localAci,
                    auth: .implicit()
                )
            } catch let error {
                try? await loader.stop(reason: error)
                return .unretryableError(error)
            }

            do {
                try await backupRequestManager.deleteMediaObjects(
                    objects: [BackupArchive.Request.DeleteMediaTarget(
                        cdn: record.record.cdnNumber,
                        mediaId: mediaId
                    )],
                    auth: backupAuth
                )
            } catch let error {
                if error.isNetworkFailureOrTimeout {
                    let errorCount = await errorCounts.updateCount(record.id)
                    if error.isRetryable, errorCount < Constants.maxRetryableErrorCount {
                        return .retryableError(error)
                    } else {
                        return .unretryableError(error)
                    }
                } else {
                    return .unretryableError(error)
                }
            }

            return .success
        }

        func didSucceed(record: Store.Record, tx: DBWriteTransaction) throws {
            Logger.info("Finished deleting backup attachment \(record.id)")
        }

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            Logger.warn("Failed deleting backup attachment \(record.id), isRetryable: \(isRetryable), error: \(error)")
        }

        func didCancel(record: Store.Record, tx: DBWriteTransaction) throws {
            Logger.info("Cancelled deleting backup attachment \(record.id)")
        }
    }

    // MARK: - TaskRecordStore

    struct TaskRecord: SignalServiceKit.TaskRecord {
        let id: OrphanedBackupAttachment.IDType
        let record: OrphanedBackupAttachment
    }

    class TaskStore: TaskRecordStore {

        private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore

        init(orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore) {
            self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
        }

        func peek(count: UInt, tx: DBReadTransaction) throws -> [TaskRecord] {
            return try orphanedBackupAttachmentStore.peek(count: count, tx: tx).map { record in
                return TaskRecord(id: record.id!, record: record)
            }
        }

        func removeRecord(_ record: TaskRecord, tx: DBWriteTransaction) throws {
            try orphanedBackupAttachmentStore.remove(record.record, tx: tx)
        }
    }

    private enum Constants {
        static let maxRetryableErrorCount = 2
    }
}

#if TESTABLE_BUILD

open class OrphanedBackupAttachmentManagerMock: OrphanedBackupAttachmentManager {

    public init() {}

    open func didCreateOrUpdateAttachment(
        withMediaName mediaName: String,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }

    open func orphanExistingMediaTierUploads(
        of attachment: Attachment,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    open func runIfNeeded() async throws {
        // Do nothing
    }
}

#endif
