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
        currentBackupPlan: BackupPlan?,
        tx: DBWriteTransaction
    ) throws

    /// Same as full `enqueueIfNeeded` variant but fetches any necessary state from the database
    /// instead of having it passed in.
    func enqueueIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        tx: DBWriteTransaction
    ) throws

    /// Same as `enqueueIfNeeded` variant but fetches all owners of the attachment and enqueues using
    /// the owner that would result in the highest priority upload (if any, and if eligible).
    func enqueueUsingHighestPriorityOwnerIfNeeded(
        _ attachment: Attachment,
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

    private let attachmentStore: AttachmentStore
    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let db: any DB
    private let statusManager: BackupAttachmentQueueStatusUpdates
    private let taskQueue: TaskQueueLoader<TaskRunner>

    public init(
        appReadiness: AppReadiness,
        attachmentStore: AttachmentStore,
        attachmentUploadManager: AttachmentUploadManager,
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        dateProvider: @escaping DateProvider,
        db: any DB,
        messageBackupRequestManager: MessageBackupRequestManager,
        statusManager: BackupAttachmentQueueStatusUpdates,
        tsAccountManager: TSAccountManager
    ) {
        self.attachmentStore = attachmentStore
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.db = db
        self.statusManager = statusManager
        let taskRunner = TaskRunner(
            attachmentStore: attachmentStore,
            attachmentUploadManager: attachmentUploadManager,
            backupAttachmentUploadStore: backupAttachmentUploadStore,
            backupSettingsStore: backupSettingsStore,
            backupSubscriptionManager: backupSubscriptionManager,
            dateProvider: dateProvider,
            db: db,
            messageBackupRequestManager: messageBackupRequestManager,
            statusManager: statusManager,
            tsAccountManager: tsAccountManager
        )
        self.taskQueue = TaskQueueLoader(
            maxConcurrentTasks: Constants.numParallelUploads,
            dateProvider: dateProvider,
            db: db,
            runner: taskRunner
        )

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            self?.startObservingQueueStatus()
        }
    }

    public func enqueueUsingHighestPriorityOwnerIfNeeded(
        _ attachment: Attachment,
        tx: DBWriteTransaction
    ) throws {
        // Backup uploads are prioritized by attachment owner. Find the highest
        // priority owner to use.
        var referenceToUse: AttachmentReference?
        try attachmentStore.enumerateAllReferences(
            toAttachmentId: attachment.id,
            tx: tx
        ) { reference in
            guard let sourceType = reference.owner.asUploadSourceType() else {
                return
            }
            if referenceToUse?.owner.asUploadSourceType()?.isHigherPriority(than: sourceType) != true {
                referenceToUse = reference
            }
        }
        if let referenceToUse {
            try self.enqueueIfNeeded(
                ReferencedAttachment(reference: referenceToUse, attachment: attachment),
                tx: tx
            )
        }
    }

    public func enqueueIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        tx: DBWriteTransaction
    ) throws {
        let currentUploadEra = backupSubscriptionManager.getUploadEra(tx: tx)

        // Its okay if our local subscription state is outdated.
        // If we think we're free but we're paid, we'll recover by scheduling any unuploaded
        // attachments when we next back up.
        // If we think we're paid but we're free, the upload will fail gracefully.
        let currentBackupPlan = backupSettingsStore.backupPlan(tx: tx)

        try enqueueIfNeeded(
            referencedAttachment,
            currentUploadEra: currentUploadEra,
            currentBackupPlan: currentBackupPlan,
            tx: tx
        )
    }

    public func enqueueIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        currentUploadEra: String,
        currentBackupPlan: BackupPlan?,
        tx: DBWriteTransaction
    ) throws {
        guard FeatureFlags.MessageBackup.fileAlpha else {
            return
        }
        guard currentBackupPlan == .paid else {
            return
        }
        guard let referencedStream = referencedAttachment.asReferencedStream else {
            // We only upload streams
            return
        }

        switch referencedAttachment.reference.owner {
        case .message, .thread:
            // We back these up (if other conditions are met)
            break
        case .storyMessage:
            // Story messages are not backed up
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
        guard FeatureFlags.MessageBackup.remoteExportAlpha else {
            return
        }
        let backupPlan = db.read { tx in
            backupSettingsStore.backupPlan(tx: tx)
        }
        switch backupPlan {
        case nil, .free:
            return
        case .paid:
            break
        }
        switch await statusManager.beginObservingIfNeeded(type: .upload) {
        case .running:
            break
        case .empty:
            // The queue will stop on its own if empty.
            return
        case .notRegisteredAndReady:
            try await taskQueue.stop()
            return
        case .noWifiReachability:
            Logger.info("Skipping backup attachment uploads while not reachable by wifi")
            try await taskQueue.stop()
            return
        case .lowBattery:
            Logger.info("Skipping backup attachment uploads while low battery")
            try await taskQueue.stop()
            return
        case .lowDiskSpace:
            owsFailDebug("Disk space should not affect uploads")
        }
        try await taskQueue.loadAndRunTasks()
    }

    public func cancelPendingUploads() async throws {
        try await taskQueue.stop()
        try await self.db.awaitableWrite { tx in
            try self.backupAttachmentUploadStore.removeAll(tx: tx)
        }
        // Kill status observation
        await statusManager.didEmptyQueue(type: .upload)
    }

    // MARK: - Observation

    private func startObservingQueueStatus() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queueStatusDidChange(_:)),
            name: BackupAttachmentQueueStatus.didChangeNotification,
            object: nil
        )
    }

    @objc
    private func queueStatusDidChange(_ notification: Notification) {
        let type = notification.userInfo?[BackupAttachmentQueueStatus.notificationQueueTypeKey]
        guard type as? BackupAttachmentQueueType == .upload else { return }
        Task {
            try await self.backUpAllAttachments()
        }
    }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let attachmentStore: AttachmentStore
        private let attachmentUploadManager: AttachmentUploadManager
        private let backupAttachmentUploadStore: BackupAttachmentUploadStore
        private let backupSettingsStore: BackupSettingsStore
        private let backupSubscriptionManager: BackupSubscriptionManager
        private let dateProvider: DateProvider
        private let db: any DB
        private let messageBackupRequestManager: MessageBackupRequestManager
        private let statusManager: BackupAttachmentQueueStatusUpdates
        private let tsAccountManager: TSAccountManager

        let store: TaskStore

        init(
            attachmentStore: AttachmentStore,
            attachmentUploadManager: AttachmentUploadManager,
            backupAttachmentUploadStore: BackupAttachmentUploadStore,
            backupSettingsStore: BackupSettingsStore,
            backupSubscriptionManager: BackupSubscriptionManager,
            dateProvider: @escaping DateProvider,
            db: any DB,
            messageBackupRequestManager: MessageBackupRequestManager,
            statusManager: BackupAttachmentQueueStatusUpdates,
            tsAccountManager: TSAccountManager
        ) {
            self.attachmentStore = attachmentStore
            self.attachmentUploadManager = attachmentUploadManager
            self.backupAttachmentUploadStore = backupAttachmentUploadStore
            self.backupSettingsStore = backupSettingsStore
            self.backupSubscriptionManager = backupSubscriptionManager
            self.dateProvider = dateProvider
            self.db = db
            self.messageBackupRequestManager = messageBackupRequestManager
            self.statusManager = statusManager
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
            guard FeatureFlags.MessageBackup.fileAlpha else {
                return .cancelled
            }
            let (attachment, backupPlan, currentUploadEra) = db.read { tx in
                return (
                    self.attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx),
                    self.backupSettingsStore.backupPlan(tx: tx),
                    self.backupSubscriptionManager.getUploadEra(tx: tx)
                )
            }
            guard let attachment else {
                // Attachment got deleted; early exit.
                return .cancelled
            }

            guard let stream = attachment.asStream() else {
                // We only back up attachments we've downloaded (streams)
                return .cancelled
            }

            switch backupPlan {
            case nil, .free:
                try? await loader.stop()
                return .cancelled
            case .paid:
                break
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
                    switch await statusManager.jobDidExperienceError(type: .upload, error) {
                    case nil:
                        // No state change, keep going.
                        break
                    case .running:
                        break
                    case .empty:
                        // The queue will stop on its own, finish this task.
                        break
                    case .lowDiskSpace, .lowBattery, .noWifiReachability, .notRegisteredAndReady:
                        // Stop the queue now proactively.
                        try? await loader.stop()
                    }

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

        func didSucceed(record: Store.Record, tx: DBWriteTransaction) throws {
            Logger.info("Finished backing up attachment \(record.id)")
        }

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            Logger.warn("Failed backing up attachment \(record.id), isRetryable: \(isRetryable), error: \(error)")
        }

        func didCancel(record: Store.Record, tx: DBWriteTransaction) throws {
            Logger.warn("Cancelled backing up attachment \(record.id)")
        }

        func didDrainQueue() async {
            await statusManager.didEmptyQueue(type: .upload)
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
        currentBackupPlan: BackupPlan?,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    public func enqueueIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    public func enqueueUsingHighestPriorityOwnerIfNeeded(
        _ attachment: Attachment,
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
