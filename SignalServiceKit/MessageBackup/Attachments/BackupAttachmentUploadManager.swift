//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol BackupAttachmentUploadManager {

    /// "Enqueue" an attachment from a backup for upload, if needed and eligible, otherwise do nothing.
    ///
    /// If the same attachment is already enqueued, updates it to the greater of the old and new timestamp.
    ///
    /// Doesn't actually trigger an upload; callers must later call `backUpAllAttachments()` to upload.
    func enqueueIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        currentUploadEra: String,
        tx: DBWriteTransaction
    ) throws

    /// Backs up all pending attachments in the BackupAttachmentUploadQueue.
    ///
    /// Will keep backing up attachments until there are none left, then returns.
    /// Is cooperatively cancellable; will check and early terminate if the task is cancelled
    /// in between individual attachments.
    ///
    /// Returns immediately if there's no attachments left to back up.
    ///
    /// Each individual attachments is either freshly uploaded or copied from the transit
    /// tier to the media tier as needed. Thumbnail versions are also created, uploaded, and
    /// backed up as needed.
    ///
    /// Throws an error IFF something would prevent all attachments from backing up (e.g. network issue).
    func backUpAllAttachments() async throws

    /// Cancel any pending attachment uploads, e.g. when backups are disabled.
    /// Removes all enqueued uploads and attempts to cancel in progress ones.
    func cancelPendingUploads() async throws
}

public class BackupAttachmentUploadManagerImpl: BackupAttachmentUploadManager {

    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
    private let db: any DB
    private let taskQueue: TaskQueueLoader<TaskRunner>

    public init(
        attachmentStore: AttachmentStore,
        attachmentUploadManager: AttachmentUploadManager,
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
        messageBackupRequestManager: MessageBackupRequestManager,
        tsAccountManager: TSAccountManager
    ) {
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.db = db
        let taskRunner = TaskRunner(
            attachmentStore: attachmentStore,
            attachmentUploadManager: attachmentUploadManager,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            dateProvider: dateProvider,
            db: db,
            messageBackupRequestManager: messageBackupRequestManager,
            tsAccountManager: tsAccountManager
        )
        self.taskQueue = TaskQueueLoader(
            maxConcurrentTasks: Constants.numParallelUploads,
            dateProvider: dateProvider,
            db: db,
            runner: taskRunner
        )
    }

    public func enqueueIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        currentUploadEra: String,
        tx: DBWriteTransaction
    ) throws {
        guard FeatureFlags.messageBackupFileAlpha else {
            return
        }
        if MessageBackupMessageAttachmentArchiver.isFreeTierBackup() {
            return
        }
        guard let referencedStream = referencedAttachment.asReferencedStream else {
            // We only upload streams
            return
        }
        let stream = referencedStream.attachmentStream
        guard
            stream.needsMediaTierUpload(currentUploadEra: currentUploadEra)
            || stream.needsMediaTierThumbnailUpload(currentUploadEra: currentUploadEra)
        else {
            // If we don't need fullsize or thumbnail upload, dont bother enqueuing.
            return
        }
        try backupAttachmentUploadStore.enqueue(
            referencedStream,
            tx: tx
        )
    }

    public func backUpAllAttachments() async throws {
        if MessageBackupMessageAttachmentArchiver.isFreeTierBackup() {
            return
        }
        try await taskQueue.loadAndRunTasks()
    }

    public func cancelPendingUploads() async throws {
        try await taskQueue.stop()
        try await self.db.awaitableWrite { tx in
            try self.backupAttachmentUploadStore.removeAll(tx: tx)
        }
    }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let attachmentStore: AttachmentStore
        private let attachmentUploadManager: AttachmentUploadManager
        private let backupAttachmentUploadStore: BackupAttachmentUploadStore
        private let dateProvider: DateProvider
        private let db: any DB
        private let messageBackupRequestManager: MessageBackupRequestManager
        private let tsAccountManager: TSAccountManager

        let store: TaskStore

        init(
            attachmentStore: AttachmentStore,
            attachmentUploadManager: AttachmentUploadManager,
            backupAttachmentUploadStore: BackupAttachmentUploadStore,
            dateProvider: @escaping DateProvider,
            db: any DB,
            messageBackupRequestManager: MessageBackupRequestManager,
            tsAccountManager: TSAccountManager
        ) {
            self.attachmentStore = attachmentStore
            self.attachmentUploadManager = attachmentUploadManager
            self.backupAttachmentUploadStore = backupAttachmentUploadStore
            self.dateProvider = dateProvider
            self.db = db
            self.messageBackupRequestManager = messageBackupRequestManager
            self.tsAccountManager = tsAccountManager

            self.store = TaskStore(backupAttachmentUploadStore: backupAttachmentUploadStore)
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
            guard FeatureFlags.messageBackupFileAlpha else {
                return .cancelled
            }
            let attachment = db.read { tx in
                return self.attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx)
            }
            guard let attachment else {
                // Attachment got deleted; early exit.
                return .cancelled
            }

            guard let stream = attachment.asStream() else {
                // We only back up attachments we've downloaded (streams)
                return .cancelled
            }

            if MessageBackupMessageAttachmentArchiver.isFreeTierBackup() {
                return .cancelled
            }

            // TODO: [Backups] get the real upload era
            let currentUploadEra: String
            do {
                currentUploadEra = try MessageBackupMessageAttachmentArchiver.currentUploadEra()
            } catch let error {
                try? await loader.stop(reason: error)
                return .unretryableError(OWSAssertionError("Unable to get current upload era: \(error)"))
            }

            let needsMediaTierUpload = stream.needsMediaTierUpload(currentUploadEra: currentUploadEra)
            let needsThumbnailUpload = stream.needsMediaTierThumbnailUpload(currentUploadEra: currentUploadEra)

            guard needsMediaTierUpload || needsThumbnailUpload else {
                return .success
            }

            let localAci = db.read { tx in
                return self.tsAccountManager.localIdentifiers(tx: tx)?.aci
            }
            guard let localAci else {
                let error = OWSAssertionError("Not registered!")
                try? await loader.stop(reason: error)
                return .unretryableError(error)
            }

            let messageBackupAuth: MessageBackupServiceAuth
            do {
                messageBackupAuth = try await messageBackupRequestManager.fetchBackupServiceAuth(
                    for: .media,
                    localAci: localAci,
                    auth: .implicit()
                )
            } catch let error {
                try? await loader.stop(reason: error)
                return .unretryableError(error)
            }

            // Upload thumbnail first
            if needsThumbnailUpload {
                do {
                    try await attachmentUploadManager.uploadMediaTierThumbnailAttachment(
                        attachmentId: attachment.id,
                        uploadEra: currentUploadEra,
                        localAci: localAci,
                        auth: messageBackupAuth
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
                        // Ignore the error if we e.g. fail to generate a thumbnail;
                        // just upload the fullsize.
                        Logger.error("Failed to upload thumbnail; proceeding")
                    }
                }
            }

            // Upload fullsize next
            if needsMediaTierUpload {
                do {
                    try await attachmentUploadManager.uploadMediaTierAttachment(
                        attachmentId: attachment.id,
                        uploadEra: currentUploadEra,
                        localAci: localAci,
                        auth: messageBackupAuth
                    )
                } catch let error {
                    switch error as? MessageBackup.Response.CopyToMediaTierError {
                    case .sourceObjectNotFound:
                        // Any time we find this error, retry. It means the upload
                        // expired, and so the copy failed. This is always transient
                        // and can always be fixed by reuploading, don't even increment
                        // the retry count.
                        return .retryableError(error)
                    default:
                        // All other errors should be treated as per normal.
                        let errorCount = await errorCounts.updateCount(record.id)
                        if error.isRetryable, errorCount < Constants.maxRetryableErrorCount {
                            return .retryableError(error)
                        } else {
                            return .unretryableError(error)
                        }
                    }
                }
            }

            return .success
        }

        func didSucceed(record: Store.Record, tx: any DBWriteTransaction) throws {
            Logger.info("Finished backing up attachment \(record.id)")
        }

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: any DBWriteTransaction) throws {
            Logger.warn("Failed backing up attachment \(record.id), isRetryable: \(isRetryable), error: \(error)")
        }

        func didCancel(record: Store.Record, tx: any DBWriteTransaction) throws {
            Logger.warn("Cancelled backing up attachment \(record.id)")
        }
    }

    // MARK: - TaskRecordStore

    struct TaskRecord: SignalServiceKit.TaskRecord {
        let id: Int64
        let record: QueuedBackupAttachmentUpload
    }

    class TaskStore: TaskRecordStore {

        private let backupAttachmentUploadStore: BackupAttachmentUploadStore

        init(backupAttachmentUploadStore: BackupAttachmentUploadStore) {
            self.backupAttachmentUploadStore = backupAttachmentUploadStore
        }

        func peek(count: UInt, tx: DBReadTransaction) throws -> [TaskRecord] {
            return try backupAttachmentUploadStore.fetchNextUploads(count: count, tx: tx).map {
                return .init(id: $0.id!, record: $0)
            }
        }

        func removeRecord(_ record: Record, tx: DBWriteTransaction) throws {
            try backupAttachmentUploadStore.removeQueuedUpload(for: record.record.attachmentRowId, tx: tx)
        }
    }

    // MARK: -

    private enum Constants {
        static let numParallelUploads: UInt = 4
        static let maxRetryableErrorCount = 3
    }
}

fileprivate extension AttachmentStream {

    func needsMediaTierUpload(currentUploadEra: String) -> Bool {
        if let mediaTierInfo = attachment.mediaTierInfo {
            return mediaTierInfo.uploadEra != currentUploadEra
        } else {
            return true
        }
    }

    func needsMediaTierThumbnailUpload(currentUploadEra: String) -> Bool {
        if let thumbnailMediaTierInfo = attachment.thumbnailMediaTierInfo {
            return thumbnailMediaTierInfo.uploadEra != currentUploadEra
        } else {
            return AttachmentBackupThumbnail.canBeThumbnailed(self.attachment)
        }
    }
}

#if TESTABLE_BUILD

open class BackupAttachmentUploadManagerMock: BackupAttachmentUploadManager {

    public init() {}

    public func enqueueIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        currentUploadEra: String,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    public func backUpAllAttachments() async throws {
        // Do nothing
    }

    public func cancelPendingUploads() async throws {
        // Do nothing
    }
}

#endif
