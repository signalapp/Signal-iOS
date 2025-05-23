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
        guard FeatureFlags.Backups.fileAlpha else {
            return
        }
        try! OrphanedBackupAttachment
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaName) == mediaName)
            .deleteAll(tx.database)
        for type in MediaTierEncryptionType.allCases {
            do {
                let mediaId = try backupKeyMaterial.mediaEncryptionMetadata(
                    mediaName: mediaName,
                    type: type,
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
            guard FeatureFlags.Backups.fileAlpha else {
                return .cancelled
            }

            let (localAci, registrationState, attachment) = db.read { tx in
                let attachment: Attachment?
                if let mediaName = record.record.mediaName {
                    attachment = attachmentStore.fetchAttachment(mediaName: mediaName, tx: tx)
                } else {
                    attachment = nil
                }

                return (
                    tsAccountManager.localIdentifiers(tx: tx)?.aci,
                    tsAccountManager.registrationState(tx: tx),
                    attachment
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

            // Check the existing attachment only if this was locally
            // orphaned (the record has a mediaName).
            if record.record.mediaName != nil {
                // If an attachment exists with the same media name, that means a new
                // copy with the same file contents got created between orphan record
                // insertion and now. Most likely we want to cancel this delete.
                if
                    let attachment,
                    attachment.mediaTierInfo?.cdnNumber == nil
                {
                    // The new attachment hasn't been uploaded to backups. It might
                    // be uploading right now, so don't try and delete.
                    return .cancelled
                } else if
                    let attachment,
                    let cdnNumber = attachment.mediaTierInfo?.cdnNumber,
                    cdnNumber == record.record.cdnNumber
                {
                    // The new copy has been uploaded to the same cdn.
                    // Don't delete it.
                    return .cancelled
                } else if
                    let attachment,
                    let cdnNumber = attachment.mediaTierInfo?.cdnNumber,
                    cdnNumber > record.record.cdnNumber
                {
                    // This is rare, but we could end up with two copies of
                    // the same attachment on two cdns (say 3 and 4). We want
                    // to allow deleting the copy on the older cdn but never the newer one.
                    // If the delete record is for 4 and the attachment is uploaded
                    // to 3, for all we know there's a job enqueued right now to
                    // "upload" it to 4 so we don't wanna delete and race with that.
                    Logger.info("Deleting duplicate upload at older cdn \(record.record.cdnNumber)")
                    return .cancelled
                }
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
                let mediaTierEncryptionType: MediaTierEncryptionType
                switch type {
                case .fullsize:
                    mediaTierEncryptionType = .attachment
                case .thumbnail:
                    mediaTierEncryptionType = .thumbnail
                }

                do {
                    (mediaId) = try db.read { tx in
                        (
                            try backupKeyMaterial.mediaEncryptionMetadata(
                                mediaName: mediaName,
                                type: mediaTierEncryptionType,
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

    open func runIfNeeded() async throws {
        // Do nothing
    }
}

#endif
