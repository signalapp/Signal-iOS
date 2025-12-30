//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol BackupAttachmentUploadQueueRunner {

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
    func backUpAllAttachments(mode: BackupAttachmentUploadQueueMode) async throws
}

class BackupAttachmentUploadQueueRunnerImpl: BackupAttachmentUploadQueueRunner {

    private let accountKeyStore: AccountKeyStore
    private let attachmentStore: AttachmentStore
    private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
    private let backupAttachmentUploadStore: BackupAttachmentUploadStore
    private let backupRequestManager: BackupRequestManager
    private let backupSettingsStore: BackupSettingsStore
    private let db: any DB
    private let logger: PrefixedLogger
    private let progress: BackupAttachmentUploadProgress
    private let statusManager: BackupAttachmentUploadQueueStatusManager
    private let tsAccountManager: TSAccountManager

    /// We keep these two separate because we allow more thumbnails in parallel
    /// than fullsize, so we just run them as separate queues configured at init time
    /// but sharing the same runner class.
    private let fullsizeTaskQueue: TaskQueueLoader<TaskRunner>
    private let thumbnailTaskQueue: TaskQueueLoader<TaskRunner>

    init(
        accountKeyStore: AccountKeyStore,
        attachmentStore: AttachmentStore,
        attachmentUploadManager: AttachmentUploadManager,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        backupAttachmentUploadStore: BackupAttachmentUploadStore,
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        backupListMediaManager: BackupListMediaManager,
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
        notificationPresenter: NotificationPresenter,
        orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
        progress: BackupAttachmentUploadProgress,
        statusManager: BackupAttachmentUploadQueueStatusManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.accountKeyStore = accountKeyStore
        self.attachmentStore = attachmentStore
        self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
        self.backupAttachmentUploadStore = backupAttachmentUploadStore
        self.backupRequestManager = backupRequestManager
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        let logger = PrefixedLogger(prefix: "[Backups]")
        self.logger = logger
        self.progress = progress
        self.statusManager = statusManager
        self.tsAccountManager = tsAccountManager

        func makeTaskQueue(mode: BackupAttachmentUploadQueueMode) -> TaskQueueLoader<TaskRunner> {
            let taskRunner = TaskRunner(
                mode: mode,
                accountKeyStore: accountKeyStore,
                attachmentStore: attachmentStore,
                attachmentUploadManager: attachmentUploadManager,
                backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                backupAttachmentUploadStore: backupAttachmentUploadStore,
                backupAttachmentUploadEraStore: backupAttachmentUploadEraStore,
                backupRequestManager: backupRequestManager,
                backupSettingsStore: backupSettingsStore,
                dateProvider: dateProvider,
                db: db,
                listMediaManager: backupListMediaManager,
                logger: logger,
                notificationPresenter: notificationPresenter,
                orphanedBackupAttachmentStore: orphanedBackupAttachmentStore,
                progress: progress,
                statusManager: statusManager,
                tsAccountManager: tsAccountManager,
            )
            return TaskQueueLoader(
                maxConcurrentTasks: {
                    switch mode {
                    case .fullsize: Constants.numParallelUploadsFullsize
                    case .thumbnail: Constants.numParallelUploadsThumbnail
                    }
                }(),
                dateProvider: dateProvider,
                db: db,
                runner: taskRunner,
            )
        }

        self.fullsizeTaskQueue = makeTaskQueue(mode: .fullsize)
        self.thumbnailTaskQueue = makeTaskQueue(mode: .thumbnail)
    }

    // MARK: -

    func backUpAllAttachments(mode: BackupAttachmentUploadQueueMode) async throws {
        let taskQueue: TaskQueueLoader<TaskRunner>
        let logString: String
        switch mode {
        case .fullsize:
            taskQueue = fullsizeTaskQueue
            logString = "fullsize"
        case .thumbnail:
            taskQueue = thumbnailTaskQueue
            logString = "thumbnail"
        }

        let (isRegisteredPrimary, localAci, backupPlan, backupKey) = db.read { tx in
            (
                self.tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
                self.tsAccountManager.localIdentifiers(tx: tx)?.aci,
                backupSettingsStore.backupPlan(tx: tx),
                accountKeyStore.getMediaRootBackupKey(tx: tx),
            )
        }

        guard isRegisteredPrimary, let localAci else {
            return
        }

        guard let backupKey else {
            Logger.info("Skipping \(logString) attachment backups while media backup key is missing")
            return
        }

        switch backupPlan {
        case .disabled, .disabling, .free:
            return
        case .paid, .paidExpiringSoon, .paidAsTester:
            break
        }

        let backupAuth: BackupServiceAuth
        do {
            // If we have no credentials, or a free credential, we want to fetch new
            // credentials, as we think we're paid tier according to local state.
            // We'll need the paid credential to upload in each task; we load and cache
            // it now so its available (and so we can bail early if its somehow free tier).
            backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                for: backupKey,
                localAci: localAci,
                auth: .implicit(),
                forceRefreshUnlessCachedPaidCredential: true,
            )
        } catch let error as BackupAuthCredentialFetchError {
            switch error {
            case .noExistingBackupId:
                // If we have no backup, we sure won't be uploading.
                logger.info("Bailing on \(logString) attachment backups when backup id not registered")
                return
            }
        } catch let error {
            throw error
        }

        switch backupAuth.backupLevel {
        case .free:
            Logger.warn("Local backupPlan is paid but credential is free")
            // If our force refreshed credential is free tier, we definitely
            // aren't uploading anything, so may as well stop the queues.
            try? await taskQueue.stop()
            return
        case .paid:
            break
        }

        switch await statusManager.beginObservingIfNecessary(for: mode) {
        case .running:
            logger.info("Running \(logString) Backup uploads.")
            let backgroundTask = OWSBackgroundTask(
                label: #function + logString,
            ) { [weak taskQueue] status in
                switch status {
                case .expired:
                    Task {
                        try await taskQueue?.stop()
                    }
                case .couldNotStart, .success:
                    break
                }
            }
            defer { backgroundTask.end() }
            try await taskQueue.loadAndRunTasks()
            logger.info("Finished \(logString) Backup uploads.")
        case .suspended:
            logger.info("Skipping \(logString) Backup uploads: suspende by user.")
            try await taskQueue.stop()
        case .empty:
            logger.info("Skipping \(logString) Backup uploads: queue is empty.")
            return
        case .notRegisteredAndReady:
            logger.warn("Skipping \(logString) Backup uploads: not registered and ready.")
            try await taskQueue.stop()
        case .noWifiReachability:
            logger.warn("Skipping \(logString) Backup uploads: need wifi.")
            try await taskQueue.stop()
        case .noReachability:
            logger.warn("Skipping \(logString) Backup uploads: need internet.")
            try await taskQueue.stop()
        case .lowBattery:
            logger.warn("Skipping \(logString) Backup uploads: low battery.")
            try await taskQueue.stop()
        case .lowPowerMode:
            logger.warn("Skipping \(logString) Backup uploads: low power mode.")
            try await taskQueue.stop()
        case .appBackgrounded:
            logger.warn("Skipping \(logString) Backup uploads: app backgrounded")
            try await taskQueue.stop()
        case .hasConsumedMediaTierCapacity:
            logger.warn("Skipping \(logString) Backup uploads: out of capacity")
            try await taskQueue.stop()
        }
    }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let accountKeyStore: AccountKeyStore
        private let attachmentStore: AttachmentStore
        private let attachmentUploadManager: AttachmentUploadManager
        private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
        private let backupAttachmentUploadStore: BackupAttachmentUploadStore
        private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
        private let backupRequestManager: BackupRequestManager
        private let backupSettingsStore: BackupSettingsStore
        private let dateProvider: DateProvider
        private let db: any DB
        private let listMediaManager: BackupListMediaManager
        private let logger: PrefixedLogger
        private let notificationPresenter: NotificationPresenter
        private let orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore
        private let progress: BackupAttachmentUploadProgress
        private let statusManager: BackupAttachmentUploadQueueStatusManager
        private let tsAccountManager: TSAccountManager

        let mode: BackupAttachmentUploadQueueMode
        let store: TaskStore

        init(
            mode: BackupAttachmentUploadQueueMode,
            accountKeyStore: AccountKeyStore,
            attachmentStore: AttachmentStore,
            attachmentUploadManager: AttachmentUploadManager,
            backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
            backupAttachmentUploadStore: BackupAttachmentUploadStore,
            backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
            backupRequestManager: BackupRequestManager,
            backupSettingsStore: BackupSettingsStore,
            dateProvider: @escaping DateProvider,
            db: any DB,
            listMediaManager: BackupListMediaManager,
            logger: PrefixedLogger,
            notificationPresenter: NotificationPresenter,
            orphanedBackupAttachmentStore: OrphanedBackupAttachmentStore,
            progress: BackupAttachmentUploadProgress,
            statusManager: BackupAttachmentUploadQueueStatusManager,
            tsAccountManager: TSAccountManager,
        ) {
            self.accountKeyStore = accountKeyStore
            self.attachmentStore = attachmentStore
            self.attachmentUploadManager = attachmentUploadManager
            self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
            self.backupAttachmentUploadStore = backupAttachmentUploadStore
            self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
            self.backupRequestManager = backupRequestManager
            self.backupSettingsStore = backupSettingsStore
            self.dateProvider = dateProvider
            self.db = db
            self.listMediaManager = listMediaManager
            self.logger = logger
            self.notificationPresenter = notificationPresenter
            self.orphanedBackupAttachmentStore = orphanedBackupAttachmentStore
            self.progress = progress
            self.statusManager = statusManager
            self.tsAccountManager = tsAccountManager

            self.mode = mode
            self.store = TaskStore(
                mode: mode,
                backupAttachmentUploadStore: backupAttachmentUploadStore,
            )
        }

        func runTask(record: Store.Record, loader: TaskQueueLoader<TaskRunner>) async -> TaskRecordResult {
            struct ExplicitlySuspendedError: Error {}
            struct NeedsBatteryError: Error {}
            struct NeedsInternetError: Error {}
            struct NeedsToBeRegisteredError: Error {}
            struct AppBackgroundedError: Error {}

            switch await statusManager.currentStatus(for: mode) {
            case .running:
                break
            case .empty:
                // The queue will stop on its own, finish this task.
                break
            case .suspended:
                try? await loader.stop()
                return .retryableError(ExplicitlySuspendedError())
            case .lowBattery, .lowPowerMode:
                try? await loader.stop()
                return .retryableError(NeedsBatteryError())
            case .noWifiReachability, .noReachability:
                try? await loader.stop()
                return .retryableError(NeedsInternetError())
            case .notRegisteredAndReady:
                try? await loader.stop()
                return .retryableError(NeedsToBeRegisteredError())
            case .appBackgrounded:
                try? await loader.stop()
                return .retryableError(AppBackgroundedError())
            case .hasConsumedMediaTierCapacity:
                try? await loader.stop()
                return .retryableError(OutOfCapacityError())
            }

            let (
                attachment,
                backupPlan,
                currentUploadEra,
                backupKey,
                needsListMedia,
            ) = db.read { tx in
                return (
                    self.attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx),
                    self.backupSettingsStore.backupPlan(tx: tx),
                    self.backupAttachmentUploadEraStore.currentUploadEra(tx: tx),
                    self.accountKeyStore.getMediaRootBackupKey(tx: tx),
                    self.listMediaManager.getNeedsQueryListMedia(tx: tx),
                )
            }

            if needsListMedia {
                // If we need to list media, quit out early so we can do that.
                try? await loader.stop(reason: NeedsListMediaError())
                return .retryableError(NeedsListMediaError())
            }

            guard let attachment else {
                // Attachment got deleted; early exit.
                return .cancelled
            }

            guard attachment.asStream() != nil, let mediaName = attachment.mediaName else {
                // We only back up attachments we've downloaded (streams)
                return .cancelled
            }

            guard let backupKey else {
                owsFailDebug("Missing media backup key.  Unable to upload attachments.")
                return .cancelled
            }

            // We're about to upload; ensure we aren't also enqueuing a media tier delete.
            // This is only defensive as we should be cancelling any deletes any time we
            // create an attachmenr stream and enqueue an upload to begin with.
            do {
                try await db.awaitableWrite { tx in
                    if record.record.isFullsize {
                        let mediaId = try backupKey.mediaEncryptionMetadata(
                            mediaName: mediaName,
                            // Doesn't matter what we use, we just want the mediaId
                            type: .outerLayerFullsizeOrThumbnail,
                        ).mediaId
                        try orphanedBackupAttachmentStore.removeFullsize(
                            mediaName: mediaName,
                            fullsizeMediaId: mediaId,
                            tx: tx,
                        )
                    } else {
                        let mediaId = try backupKey.mediaEncryptionMetadata(
                            mediaName: AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName),
                            // Doesn't matter what we use, we just want the mediaId
                            type: .outerLayerFullsizeOrThumbnail,
                        ).mediaId
                        try orphanedBackupAttachmentStore.removeThumbnail(
                            fullsizeMediaName: mediaName,
                            thumbnailMediaId: mediaId,
                            tx: tx,
                        )
                    }
                }
            } catch {
                owsFailDebug("Unable to delete orphan row. Proceeding anyway.")
            }

            struct IsFreeTierError: Error {}
            switch backupPlan {
            case .disabled, .disabling, .free:
                try? await loader.stop()
                return .retryableError(IsFreeTierError())
            case .paid, .paidExpiringSoon, .paidAsTester:
                break
            }

            let localAci: Aci
            let isPrimary: Bool
            do throws(NotRegisteredError) {
                let registeredState = try self.tsAccountManager.registeredStateWithMaybeSneakyTransaction()
                localAci = registeredState.localIdentifiers.aci
                isPrimary = registeredState.isPrimary
            } catch {
                try? await loader.stop(reason: error)
                return .retryableError(error)
            }
            guard isPrimary else {
                let error = OWSAssertionError("not primary")
                try? await loader.stop(reason: error)
                return .retryableError(error)
            }

            let backupAuth: BackupServiceAuth
            do {
                backupAuth = try await backupRequestManager.fetchBackupServiceAuth(
                    for: backupKey,
                    localAci: localAci,
                    auth: .implicit(),
                    // No need to force it here; when we start up the queue we force
                    // a fetch, and should've bailed and never gotten this far if it
                    // was a free tier credential. (Though the paid state and credential
                    // can change _after_ this queue has already started running, so we
                    // do need to handle that case).
                    forceRefreshUnlessCachedPaidCredential: false,
                )
            } catch let error {
                try? await loader.stop(reason: error)
                return .retryableError(error)
            }

            switch backupAuth.backupLevel {
            case .paid:
                break
            case .free:
                // If we find ourselves with a free tier credential,
                // all uploads will fail. Just quit.
                try? await loader.stop()
                return .retryableError(IsFreeTierError())
            }

            let progressSink: OWSProgressSink?
            if record.record.isFullsize {
                progressSink = await progress.willBeginUploadingFullsizeAttachment(
                    uploadRecord: record.record,
                )
            } else {
                progressSink = nil
            }

            guard
                db.read(block: { tx in
                    backupAttachmentUploadScheduler.isEligibleToUpload(
                        attachment,
                        fullsize: record.record.isFullsize,
                        currentUploadEra: currentUploadEra,
                        tx: tx,
                    )
                })
            else {
                if record.record.isFullsize {
                    await progress.didFinishUploadOfFullsizeAttachment(
                        uploadRecord: record.record,
                    )
                }
                // Not eligible anymore, count as success.
                return .success
            }

            do {
                if record.record.isFullsize {
                    try await attachmentUploadManager.uploadMediaTierAttachment(
                        attachmentId: attachment.id,
                        uploadEra: currentUploadEra,
                        localAci: localAci,
                        backupKey: backupKey,
                        auth: backupAuth,
                        progress: progressSink,
                    )
                } else {
                    try await attachmentUploadManager.uploadMediaTierThumbnailAttachment(
                        attachmentId: attachment.id,
                        uploadEra: currentUploadEra,
                        localAci: localAci,
                        backupKey: backupKey,
                        auth: backupAuth,
                    )
                }
            } catch let error {
                if Task.isCancelled {
                    logger.info("Cancelled; stopping the queue")
                    try? await loader.stop(reason: CancellationError())
                    return .retryableError(CancellationError())
                }

                switch error as? BackupArchive.Response.CopyToMediaTierError {
                case .sourceObjectNotFound:
                    // Any time we find this error, retry. It means the upload
                    // expired, and so the copy failed. This is always transient
                    // and can always be fixed by reuploading, don't even increment
                    // the retry count.
                    return .retryableError(error)
                case .forbidden:
                    // This only happens if we've lost write access to the media tier.
                    // As a final check, force refresh our crednetial and check if its
                    // paid. If its not (we just got a 403 so that's what we expect),
                    // all uploads will fail so dequeue them and quit.
                    let credential = try? await backupRequestManager.fetchBackupServiceAuth(
                        for: backupKey,
                        localAci: localAci,
                        auth: .implicit(),
                        forceRefreshUnlessCachedPaidCredential: true,
                    )
                    switch credential?.backupLevel {
                    case .free, nil:
                        try? await loader.stop()
                        return .retryableError(IsFreeTierError())
                    case .paid:
                        break
                    }
                    fallthrough
                case .outOfCapacity:
                    let didSetConsumeMediaTierCapacity = await db.awaitableWrite { tx in
                        if !backupSettingsStore.hasConsumedMediaTierCapacity(tx: tx) {
                            backupSettingsStore.setHasConsumedMediaTierCapacity(true, tx: tx)
                            return true
                        } else {
                            return false
                        }
                    }
                    if didSetConsumeMediaTierCapacity {
                        await MainActor.run { [notificationPresenter] in
                            notificationPresenter.notifyUserOfMediaTierQuotaConsumed()
                        }
                    }
                    let error = OutOfCapacityError()
                    try? await loader.stop(reason: error)
                    return .retryableError(error)
                default:
                    // All other errors should be treated as per normal.
                    if error.httpStatusCode == 429 {
                        if let retryAfter = error.httpResponseHeaders?.retryAfterTimeInterval {
                            return .retryableError(RateLimitedRetryError(retryAfter: retryAfter))
                        }

                        // If for whatever reason we don't have a retry-after,
                        // treat this like a network error that retries with
                        // backoff.
                        return .retryableError(NetworkRetryError())
                    } else if
                        error.isNetworkFailureOrTimeout
                        // Retry 500s per-item with the same backoff as network errors
                        || error.is5xxServiceResponse
                        || (error as? Upload.Error) == .networkTimeout
                        || (error as? Upload.Error) == .networkError
                    {
                        switch await statusManager.currentStatus(for: mode) {
                        case .running:
                            // If we _think_ we are connected and should be running,
                            // use a more crude retry time mechanism to retry later.
                            // Note that we update the individual row but really this
                            // will end up holding up the entire queue because we don't
                            // reorder when popping off the queue based on retry time,
                            // so this row will remain first in line (unless something else
                            // changes, in which case we retry and either succeed or fall back
                            // into here) and block the rest of the queue from trying,
                            // which is what we want because the error is a general network
                            // issue.
                            return .retryableError(NetworkRetryError())
                        case .noWifiReachability, .notRegisteredAndReady, .hasConsumedMediaTierCapacity,
                             .lowBattery, .lowPowerMode, .appBackgrounded, .empty, .suspended:
                            // These other states may be overriding reachability;
                            // just allow the queue itself to retry and once the
                            // other states are resolved reachability will kick in,
                            // or won't.
                            fallthrough
                        case .noReachability:
                            // If reachability thinks we are not connected, queue status
                            // will cover us. Don't touch the record itself; the queue will stop
                            // running and start again once reconnected, and we want to try
                            // the record again immediately then.
                            return .retryableError(error)
                        }
                    } else if let uploadError = error as? Upload.Error {
                        switch uploadError {
                        case .missingFile:
                            // The file is missing! We can never retry this upload;
                            // call it a "success" so we don't mess with progress
                            // state and so we wipe the upload task row, and move on.
                            logger.error("Missing attachment file; skipping and proceeding")
                            if record.record.isFullsize {
                                await progress.didFinishUploadOfFullsizeAttachment(
                                    uploadRecord: record.record,
                                )
                            }
                            return .success
                        case .uploadFailure(let recovery):
                            switch recovery {
                            case .resume(let retryMode), .restart(let retryMode):
                                switch retryMode {
                                case .afterBackoff:
                                    return .retryableError(RateLimitedRetryError(retryAfter: nil))
                                case .afterServerRequestedDelay(let retryAfter):
                                    return .retryableError(RateLimitedRetryError(retryAfter: retryAfter))
                                case .immediately:
                                    return .retryableError(RateLimitedRetryError(retryAfter: 0))
                                }
                            case .noMoreRetries:
                                logger.error("No more upload retries; stopping the queue")
                                try? await loader.stop()
                                return .retryableError(error)
                            }
                        default:
                            // For other errors stop the queue to prevent thundering herd;
                            // when it starts up again (e.g. on app launch) we will retry.
                            logger.error("Unknown error occurred; stopping the queue. \(error)")
                            try? await loader.stop()
                            return .retryableError(error)
                        }
                    } else if record.record.isFullsize {
                        // For other errors stop the queue to prevent thundering herd;
                        // when it starts up again (e.g. on app launch) we will retry.
                        logger.error("Unknown error occurred; stopping the queue")
                        try? await loader.stop()
                        return .retryableError(error)
                    } else {
                        // Ignore the error if we e.g. fail to generate a thumbnail;
                        // just upload the fullsize.
                        logger.error("Failed to upload thumbnail; proceeding")
                        if record.record.isFullsize {
                            await progress.didFinishUploadOfFullsizeAttachment(
                                uploadRecord: record.record,
                            )
                        }
                        return .success
                    }
                }
            }

            if record.record.isFullsize {
                await progress.didFinishUploadOfFullsizeAttachment(
                    uploadRecord: record.record,
                )
            }

            return .success
        }

        func didSucceed(record: Store.Record, tx: DBWriteTransaction) throws {
            logger.info("Finished backing up attachment \(record.record.attachmentRowId), upload \(record.id), fullsize? \(record.record.isFullsize)")
        }

        private struct RateLimitedRetryError: Error {
            let retryAfter: TimeInterval?
        }

        private struct NetworkRetryError: Error {}
        private struct OutOfCapacityError: Error {}

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            logger.warn("Failed backing up attachment \(record.record.attachmentRowId), upload \(record.id), fullsize? \(record.record.isFullsize), isRetryable: \(isRetryable), error: \(error)")

            guard isRetryable else {
                return
            }

            var record = record.record
            let retryDelay: TimeInterval

            if error is NetworkRetryError {
                record.numRetries += 1
                retryDelay = OWSOperation.retryIntervalForExponentialBackoff(failureCount: record.numRetries)
            } else if let rateLimitedError = error as? RateLimitedRetryError {
                if let retryAfter = rateLimitedError.retryAfter {
                    retryDelay = retryAfter
                } else {
                    // If no delay provided, use standard backoff and increment retry count.
                    record.numRetries += 1
                    retryDelay = OWSOperation.retryIntervalForExponentialBackoff(failureCount: record.numRetries)
                }
            } else {
                return
            }

            record.minRetryTimestamp = dateProvider().addingTimeInterval(retryDelay).ows_millisecondsSince1970
            try record.update(tx.database)
        }

        func didCancel(record: Store.Record, tx: DBWriteTransaction) throws {
            logger.warn("Cancelled backing up attachment \(record.record.attachmentRowId), upload \(record.id), fullsize? \(record.record.isFullsize)")
        }

        func didDrainQueue() async {
            switch mode {
            case .fullsize:
                Logger.info("Did drain fullsize upload queue")
                await progress.didEmptyFullsizeUploadQueue()
            case .thumbnail:
                Logger.info("Did drain thumbnail upload queue")
            }
            await statusManager.didEmptyQueue(for: mode)
        }
    }

    // MARK: - TaskRecordStore

    struct TaskRecord: SignalServiceKit.TaskRecord {
        let id: Int64
        let record: QueuedBackupAttachmentUpload

        var nextRetryTimestamp: UInt64? {
            return record.minRetryTimestamp
        }
    }

    class TaskStore: TaskRecordStore {

        private let mode: BackupAttachmentUploadQueueMode
        private let backupAttachmentUploadStore: BackupAttachmentUploadStore

        init(
            mode: BackupAttachmentUploadQueueMode,
            backupAttachmentUploadStore: BackupAttachmentUploadStore,
        ) {
            self.mode = mode
            self.backupAttachmentUploadStore = backupAttachmentUploadStore
        }

        func peek(count: UInt, tx: DBReadTransaction) throws -> [TaskRecord] {
            let forFullsizeUploads = switch mode {
            case .fullsize:
                true
            case .thumbnail:
                false
            }
            return try backupAttachmentUploadStore.fetchNextUploads(count: count, isFullsize: forFullsizeUploads, tx: tx).map {
                return .init(id: $0.id!, record: $0)
            }
        }

        func removeRecord(_ record: TaskRecord, tx: DBWriteTransaction) throws {
            // We don't actually delete records when finishing; we just mark
            // them done so we can still keep track of their byte count.
            try backupAttachmentUploadStore.markUploadDone(
                for: record.record.attachmentRowId,
                fullsize: record.record.isFullsize,
                tx: tx,
            )
        }
    }

    // MARK: -

    private enum Constants {
        static let numParallelUploadsFullsize: UInt = 12
        static let numParallelUploadsThumbnail: UInt = 8
    }
}

#if TESTABLE_BUILD

open class BackupAttachmentUploadQueueRunnerMock: BackupAttachmentUploadQueueRunner {

    public init() {}

    public func backUpAllAttachments(mode: BackupAttachmentUploadQueueMode) async throws {
        // Do nothing
    }
}

#endif
