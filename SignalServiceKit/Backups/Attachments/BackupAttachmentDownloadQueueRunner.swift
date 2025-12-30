//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public protocol BackupAttachmentDownloadQueueRunner {

    /// Restores all pending attachments in the BackupAttachmentDownloadQueue.
    ///
    /// Will keep restoring attachments until there are none left, then returns.
    /// Is cooperatively cancellable; will check and early terminate if the task is cancelled
    /// in between individual attachments.
    ///
    /// Returns immediately if there's no attachments left to restore.
    ///
    /// Throws an error IFF something would prevent all attachments from restoring (e.g. network issue).
    func restoreAttachmentsIfNeeded(mode: BackupAttachmentDownloadQueueMode) async throws
}

public class BackupAttachmentDownloadQueueRunnerImpl: BackupAttachmentDownloadQueueRunner {

    private let appContext: AppContext
    private let attachmentStore: AttachmentStore
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupSettingsStore: BackupSettingsStore
    private let dateProvider: DateProvider
    private let db: any DB
    private let logger: PrefixedLogger
    private let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
    private let progress: BackupAttachmentDownloadProgress
    private let remoteConfigProvider: RemoteConfigProvider
    private let statusManager: BackupAttachmentDownloadQueueStatusManager
    private let tsAccountManager: TSAccountManager

    private let fullsizeTaskQueue: TaskQueueLoader<TaskRunner>
    private let thumbnailTaskQueue: TaskQueueLoader<TaskRunner>

    public init(
        appContext: AppContext,
        attachmentStore: AttachmentStore,
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentUploadStore: AttachmentUploadStore,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        backupListMediaManager: BackupListMediaManager,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
        mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
        progress: BackupAttachmentDownloadProgress,
        remoteConfigProvider: RemoteConfigProvider,
        statusManager: BackupAttachmentDownloadQueueStatusManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.appContext = appContext
        self.attachmentStore = attachmentStore
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        let logger = PrefixedLogger(prefix: "[Backups]")
        self.logger = logger
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.db = db
        self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
        self.progress = progress
        self.remoteConfigProvider = remoteConfigProvider
        self.statusManager = statusManager
        self.tsAccountManager = tsAccountManager

        func taskQueue(mode: BackupAttachmentDownloadQueueMode) -> TaskQueueLoader<TaskRunner> {
            let taskRunner = TaskRunner(
                mode: mode,
                attachmentStore: attachmentStore,
                attachmentDownloadManager: attachmentDownloadManager,
                attachmentUploadStore: attachmentUploadStore,
                backupAttachmentDownloadStore: backupAttachmentDownloadStore,
                backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                backupSettingsStore: backupSettingsStore,
                dateProvider: dateProvider,
                db: db,
                listMediaManager: backupListMediaManager,
                logger: logger,
                mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
                progress: progress,
                remoteConfigProvider: remoteConfigProvider,
                statusManager: statusManager,
                tsAccountManager: tsAccountManager,
            )
            return TaskQueueLoader(
                maxConcurrentTasks: {
                    switch mode {
                    case .thumbnail: Constants.numParallelDownloadsThumbnail
                    case .fullsize: Constants.numParallelDownloadsFullsize
                    }
                }(),
                dateProvider: dateProvider,
                db: db,
                runner: taskRunner,
            )
        }

        self.fullsizeTaskQueue = taskQueue(mode: .fullsize)
        self.thumbnailTaskQueue = taskQueue(mode: .thumbnail)
    }

    public func restoreAttachmentsIfNeeded(mode: BackupAttachmentDownloadQueueMode) async throws {
        guard appContext.isMainApp else { return }

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

        switch await statusManager.beginObservingIfNecessary(for: mode) {
        case .running:
            logger.info("Starting \(logString) backup attachment downloads")
        case .suspended:
            // The queue will stop on its own if suspended
            logger.info("Skipping \(logString) backup attachment downloads while suspended")
            return
        case .empty:
            // The queue will stop on its own if empty.
            logger.info("\(logString) backup attachment download queue empty!")
            return
        case .notRegisteredAndReady:
            try await taskQueue.stop()
            return
        case .noWifiReachability:
            logger.info("Skipping \(logString) backup attachment downloads while not reachable by wifi")
            try await taskQueue.stop()
            return
        case .noReachability:
            logger.info("Skipping \(logString) backup attachment downloads while not reachable at all")
            try await taskQueue.stop()
            return
        case .lowBattery:
            logger.info("Skipping \(logString) backup attachment downloads while low battery")
            try await taskQueue.stop()
            return
        case .lowPowerMode:
            logger.info("Skipping \(logString) backup attachment downloads while low power mode")
            try await taskQueue.stop()
            return
        case .lowDiskSpace:
            logger.info("Skipping \(logString) backup attachment downloads while low on disk space")
            try await taskQueue.stop()
            return
        case .appBackgrounded:
            logger.info("Skipping \(logString) backup attachment downloads while backgrounded")
            try await taskQueue.stop()
            return
        }

        do {
            try await progress.beginObserving()
        } catch {
            owsFailDebug("Unable to observe \(logString) download progres \(error.grdbErrorForLogging)")
        }

        let backgroundTask = OWSBackgroundTask(
            label: #function + logString,
        ) { [weak taskQueue] status in
            switch status {
            case .expired:
                Task {
                    try? await taskQueue?.stop()
                }
            case .couldNotStart, .success:
                break
            }
        }
        defer { backgroundTask.end() }

        try await taskQueue.loadAndRunTasks()

        logger.info("Finished \(logString) backup attachment downloads")
    }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let attachmentStore: AttachmentStore
        private let attachmentDownloadManager: AttachmentDownloadManager
        private let attachmentUploadStore: AttachmentUploadStore
        private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
        private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
        private let backupSettingsStore: BackupSettingsStore
        private let dateProvider: DateProvider
        private let db: any DB
        private let listMediaManager: BackupListMediaManager
        private let logger: PrefixedLogger
        private let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
        private let progress: BackupAttachmentDownloadProgress
        private let remoteConfigProvider: RemoteConfigProvider
        private let statusManager: BackupAttachmentDownloadQueueStatusManager
        private let tsAccountManager: TSAccountManager

        let store: TaskStore

        private let mode: BackupAttachmentDownloadQueueMode

        init(
            mode: BackupAttachmentDownloadQueueMode,
            attachmentStore: AttachmentStore,
            attachmentDownloadManager: AttachmentDownloadManager,
            attachmentUploadStore: AttachmentUploadStore,
            backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
            backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
            backupSettingsStore: BackupSettingsStore,
            dateProvider: @escaping DateProvider,
            db: any DB,
            listMediaManager: BackupListMediaManager,
            logger: PrefixedLogger,
            mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
            progress: BackupAttachmentDownloadProgress,
            remoteConfigProvider: RemoteConfigProvider,
            statusManager: BackupAttachmentDownloadQueueStatusManager,
            tsAccountManager: TSAccountManager,
        ) {
            self.mode = mode
            self.attachmentStore = attachmentStore
            self.attachmentDownloadManager = attachmentDownloadManager
            self.attachmentUploadStore = attachmentUploadStore
            self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
            self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
            self.backupSettingsStore = backupSettingsStore
            self.dateProvider = dateProvider
            self.db = db
            self.listMediaManager = listMediaManager
            self.logger = logger
            self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
            self.progress = progress
            self.remoteConfigProvider = remoteConfigProvider
            self.statusManager = statusManager
            self.tsAccountManager = tsAccountManager

            self.store = TaskStore(
                mode: mode,
                backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            )
        }

        func runTask(record: Store.Record, loader: TaskQueueLoader<TaskRunner>) async -> TaskRecordResult {
            struct SuspendedError: Error {}
            struct NeedsDiskSpaceError: Error {}
            struct NeedsBatteryError: Error {}
            struct AppBackgroundedError: Error {}
            struct NeedsInternetError: Error {}
            struct NeedsToBeRegisteredError: Error {}

            await statusManager.quickCheckDiskSpaceForDownloads()

            let (status, statusToken) = await statusManager.currentStatusAndToken(for: mode)

            switch status {
            case .running:
                break
            case .empty:
                // The queue will stop on its own, finish this task.
                break
            case .suspended:
                try? await loader.stop()
                return .retryableError(SuspendedError())
            case .lowDiskSpace:
                try? await loader.stop()
                return .retryableError(NeedsDiskSpaceError())
            case .lowBattery, .lowPowerMode:
                try? await loader.stop()
                return .retryableError(NeedsBatteryError())
            case .appBackgrounded:
                try? await loader.stop()
                return .retryableError(AppBackgroundedError())
            case .noWifiReachability, .noReachability:
                try? await loader.stop()
                return .retryableError(NeedsInternetError())
            case .notRegisteredAndReady:
                try? await loader.stop()
                return .retryableError(NeedsToBeRegisteredError())
            }

            let (
                attachment,
                backupPlan,
                registrationState,
                needsListMedia,
            ) = db.read { tx -> (Attachment?, BackupPlan, TSRegistrationState, Bool) in
                return (
                    attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx),
                    backupSettingsStore.backupPlan(tx: tx),
                    tsAccountManager.registrationState(tx: tx),
                    self.listMediaManager.getNeedsQueryListMedia(tx: tx),
                )
            }

            if needsListMedia {
                // If we need to list media, quit out early so we can do that.
                try? await loader.stop(reason: NeedsListMediaError())
                return .retryableError(NeedsListMediaError())
            }

            guard let attachment else {
                return .cancelled
            }

            let progressSink: OWSProgressSink?
            if record.record.isThumbnail {
                progressSink = nil
            } else {
                progressSink = await progress.willBeginDownloadingFullsizeAttachment(
                    withId: record.record.attachmentRowId,
                )
            }

            let nowMs = dateProvider().ows_millisecondsSince1970
            let remoteConfig = remoteConfigProvider.currentConfig()
            let eligibility = BackupAttachmentDownloadEligibility.forAttachment(
                attachment,
                downloadRecord: record.record,
                currentTimestamp: nowMs,
                backupPlan: backupPlan,
                remoteConfig: remoteConfig,
                isPrimaryDevice: registrationState.isRegisteredPrimaryDevice,
            )

            struct NoLongerEligibleError: Error {}
            let relevantEligibilityState: QueuedBackupAttachmentDownload.State? = {
                if record.record.isThumbnail {
                    return eligibility.thumbnailMediaTierState
                } else {
                    return eligibility.fullsizeState
                }
            }()
            switch relevantEligibilityState {
            case .ready:
                break
            case nil:
                // No longer at all eligible to download from this source.
                // count this as having completed the download for progress tracking purposes.
                if !record.record.isThumbnail {
                    await progress.didFinishDownloadOfFullsizeAttachment(
                        withId: record.record.attachmentRowId,
                        byteCount: UInt64(record.record.estimatedByteCount),
                    )
                }
                return .cancelled
            case .ineligible:
                // Current state prevents running this row; unclear how we
                // got here but mark it ineligible in the queue now and return
                // a a "retryable" error so we don't wipe this row from the queue.
                // Since its now ineligible it will be skipped going forward.
                Logger.info("Marking \(attachment.id) ineligible and skipping download")
                await db.awaitableWrite { tx in
                    backupAttachmentDownloadStore.markIneligible(
                        attachmentId: attachment.id,
                        thumbnail: record.record.isThumbnail,
                        tx: tx,
                    )
                }
                return .retryableError(NoLongerEligibleError())
            case .done:
                // All done! Mark done and treat it as a "retryable" error
                // so we don't wipe this row from the queue. Since its now
                // done it will be skipped going forward.
                await db.awaitableWrite { tx in
                    backupAttachmentDownloadStore.markDone(
                        attachmentId: attachment.id,
                        thumbnail: record.record.isThumbnail,
                        tx: tx,
                    )
                }
                // count this as having completed the download.
                if !record.record.isThumbnail {
                    await progress.didFinishDownloadOfFullsizeAttachment(
                        withId: record.record.attachmentRowId,
                        byteCount: UInt64(record.record.estimatedByteCount),
                    )
                }
                return .retryableError(NoLongerEligibleError())
            }

            let source: DownloadSource = {
                if record.record.isThumbnail {
                    return .mediaTierThumbnail
                }
                if
                    eligibility.fullsizeMediaTierState == .ready,
                    // Try media tier once first if available
                    record.record.numRetries == 0
                {
                    return .mediaTierFullsize
                } else if
                    let transitTierInfo = attachment.latestTransitTierInfo,
                    eligibility.fullsizeMediaTierState != .ready
                    || record.record.numRetries == 1,
                    eligibility.fullsizeTransitTierState == .ready
                {
                    // Otherwise try transit tier if media tier has failed once before.
                    return .transitTier(transitTierInfo)
                } else {
                    // And then fall back to media tier.
                    return .mediaTierFullsize
                }
            }()

            do {
                try await self.attachmentDownloadManager.downloadAttachment(
                    id: record.record.attachmentRowId,
                    priority: .backupRestore,
                    source: source.asSourceType,
                    progress: progressSink,
                )
            } catch let error {
                if Task.isCancelled {
                    logger.info("Cancelled; stopping the queue")
                    try? await loader.stop(reason: CancellationError())
                    return .retryableError(CancellationError())
                }

                switch await statusManager.jobDidExperienceError(error, token: statusToken, mode: mode) {
                case nil:
                    // No state change, keep going.
                    break
                case .running:
                    break
                case .empty:
                    // The queue will stop on its own, finish this task.
                    break
                case .suspended, .lowDiskSpace, .lowBattery, .lowPowerMode, .noWifiReachability, .noReachability, .appBackgrounded, .notRegisteredAndReady:
                    // Stop the queue now proactively.
                    try? await loader.stop()
                }

                switch error as? AttachmentDownloads.Error {
                case nil, .expiredCredentials:
                    break
                case .blockedByAutoDownloadSettings:
                    owsFailDebug("Backup downloads should never by blocked by auto download settings!")
                    // This should be impossible. Stop the queue, it can start up again later
                    // on whatever the next trigger is.
                    try? await loader.stop()
                    return .retryableError(error)
                case .blockedByActiveCall:
                    // TODO: [Backups] suspend downloads during calls and resume after
                    owsFailDebug("Backup downloads are currently not blocked by active calls!")
                    try? await loader.stop()
                    return .retryableError(error)
                case .blockedByPendingMessageRequest:
                    switch source {
                    case .transitTier:
                        // Don't do transit tier downloads of message request state chats.
                        // When we restore transit tier download info from a backup, we don't
                        // know if the attachment had been previously downloaded (we'd back up
                        // the transit tier info even if it hadn't been) and, if it hadn't, we
                        // should not auto-download stuff in message request state.
                        return .unretryableError(error)
                    case .mediaTierFullsize, .mediaTierThumbnail:
                        owsFailDebug("Media tier downloads should never by blocked by message request state!")
                        // This should be impossible. Stop the queue, it can start up again later
                        // on whatever the next trigger is.
                        try? await loader.stop()
                        return .retryableError(error)
                    }
                case .blockedByNetworkState:
                    // The attachment download is the thing that discovered incompatible reachability state
                    // (e.g. we need wifi and aren't connected). Stop the queue; the status should
                    // catch up momentarily and notify when reachability state changes.
                    Logger.warn("Download failed due to reachability; proactively stopping the queue")
                    try? await loader.stop()
                    return .retryableError(error)
                }

                // We only retry fullsize media tier 404s.
                // Retries work one of two ways: we first fall back to transit tier
                // if possible with no backoff, then only if we're on a linked device
                // we retry media tier with some delay. The latter retry is because the
                // primary might still be working on uploading the attachment to media tier.
                func canRetryMediaTier404() -> Bool {
                    db.read { tx in
                        guard tsAccountManager.registrationState(tx: tx).isPrimaryDevice == false else {
                            return false
                        }
                        switch backupSettingsStore.backupPlan(tx: tx) {
                        case .disabling, .disabled, .free:
                            // The primary would only be uploading if were paid tier.
                            // (this is inexact but the user can always tap to download)
                            return false
                        case .paid, .paidExpiringSoon, .paidAsTester:
                            break
                        }
                        guard let attachment = attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx) else {
                            return false
                        }
                        return attachment.mediaTierInfo != nil
                            // If we had a cdn number, that came from the primary, and the
                            // primary therefore _thinks_ its uploaded, and won't upload again.
                            // That or we discovered this via list media and its gone now.
                            && attachment.mediaTierInfo?.cdnNumber == nil
                    }
                }

                if
                    !record.record.isThumbnail,
                    record.record.numRetries == 0,
                    eligibility.fullsizeTransitTierState == .ready,
                    source == .mediaTierFullsize
                {
                    // Retry as transit tier. If we wouldn't have retried as media tier anyway,
                    // wipe the media tier info so that we reupload in the future.
                    return .retryableError(RetryAsTransitTierError(
                        shouldWipeMediaTierInfo: error.httpStatusCode == 404 && !canRetryMediaTier404(),
                    ))
                } else if
                    error.httpStatusCode == 404,
                    !record.record.isThumbnail,
                    record.record.canDownloadFromMediaTier,
                    canRetryMediaTier404(),
                    let nextRetryTimestamp = { () -> UInt64? in
                        guard record.record.numRetries < 32 else {
                            owsFailDebug("Too many retries!")
                            return nil
                        }
                        // Exponential backoff, starting at 1 day.
                        let delay = OWSOperation.retryIntervalForExponentialBackoff(
                            failureCount: record.record.numRetries,
                            minAverageBackoff: .day,
                            maxAverageBackoff: .day * 30,
                        )
                        return dateProvider().addingTimeInterval(delay).ows_millisecondsSince1970
                    }()
                {
                    return .retryableError(RetryMediaTierError(nextRetryTimestamp: nextRetryTimestamp))
                } else if error.httpStatusCode == 404 {
                    return .unretryableError(Unretryable404Error(source: source))
                } else if error.is5xxServiceResponse || error.isNetworkFailureOrTimeout {
                    // These suspend the queue status so just treat the row as retryable
                    return .retryableError(error)
                } else {
                    return .unretryableError(error)
                }
            }

            await statusManager.jobDidSucceed(token: statusToken, mode: mode)

            if !record.record.isThumbnail {
                await progress.didFinishDownloadOfFullsizeAttachment(
                    withId: record.record.attachmentRowId,
                    byteCount: UInt64(record.record.estimatedByteCount),
                )
            }

            return .success
        }

        func didSucceed(record: Store.Record, tx: DBWriteTransaction) {
            logger.info("Finished restoring attachment \(record.record.attachmentRowId), download \(record.id), isThumbnail: \(record.record.isThumbnail)")
            // Mark the record done when we succeed; this will filter it out
            // from future queue pop/peek operations.
            backupAttachmentDownloadStore.markDone(
                attachmentId: record.record.attachmentRowId,
                thumbnail: record.record.isThumbnail,
                tx: tx,
            )
        }

        private struct RetryMediaTierError: Error {
            let nextRetryTimestamp: UInt64
        }

        private struct Retry5xxError: Error {
            let nextRetryTimestamp: UInt64
        }

        private struct RetryAsTransitTierError: Error {
            let shouldWipeMediaTierInfo: Bool
        }

        private enum DownloadSource: Equatable {
            case transitTier(Attachment.TransitTierInfo)
            case mediaTierFullsize
            case mediaTierThumbnail

            var asSourceType: QueuedAttachmentDownloadRecord.SourceType {
                return switch self {
                case .transitTier: .transitTier
                case .mediaTierFullsize: .mediaTierFullsize
                case .mediaTierThumbnail: .mediaTierThumbnail
                }
            }
        }

        private struct Unretryable404Error: Error {
            let source: DownloadSource
        }

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            logger.warn("Failed restoring attachment \(record.id), isRetryable: \(isRetryable), isThumbnail: \(record.record.isThumbnail), error: \(error)")

            if
                isRetryable,
                let nextRetryTimestamp =
                (error as? RetryMediaTierError)?.nextRetryTimestamp
                    ?? (error as? Retry5xxError)?.nextRetryTimestamp
            {
                var downloadRecord = record.record
                downloadRecord.minRetryTimestamp = nextRetryTimestamp
                downloadRecord.numRetries += 1
                try downloadRecord.update(tx.database)
            } else if
                isRetryable,
                let error = error as? RetryAsTransitTierError
            {
                // Just increment the retry count by 1 but don't update
                // the retry timestamp so we retry immediately as transit tier.
                var downloadRecord = record.record
                downloadRecord.numRetries += 1
                try downloadRecord.update(tx.database)

                if error.shouldWipeMediaTierInfo {
                    try attachmentStore.removeMediaTierInfo(
                        forAttachmentId: record.record.attachmentRowId,
                        tx: tx,
                    )
                    if
                        let stream = attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx)?.asStream()
                    {
                        try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                            stream.attachment,
                            mode: .fullsizeOnly,
                            tx: tx,
                        )
                    }
                }
            } else if !isRetryable {
                backupAttachmentDownloadStore.remove(
                    attachmentId: record.record.attachmentRowId,
                    thumbnail: record.record.isThumbnail,
                    tx: tx,
                )
                // For non-retryable 404 errors, go ahead and wipe the relevant cdn
                // info from the attachment, as download failed.
                if let error = error as? Unretryable404Error {
                    switch error.source {
                    case .mediaTierThumbnail:
                        try attachmentStore.removeThumbnailMediaTierInfo(
                            forAttachmentId: record.record.attachmentRowId,
                            tx: tx,
                        )
                        if
                            let stream = attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx)?.asStream()
                        {
                            try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                                stream.attachment,
                                mode: .thumbnailOnly,
                                tx: tx,
                            )
                        }
                    case .mediaTierFullsize:
                        try attachmentStore.removeMediaTierInfo(
                            forAttachmentId: record.record.attachmentRowId,
                            tx: tx,
                        )
                        if
                            let stream = attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx)?.asStream()
                        {
                            try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                                stream.attachment,
                                mode: .fullsizeOnly,
                                tx: tx,
                            )
                        }
                    case .transitTier(let transitTierInfo):
                        if let attachment = attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx) {
                            try attachmentUploadStore.markTransitTierUploadExpired(
                                attachment: attachment,
                                info: transitTierInfo,
                                tx: tx,
                            )
                        }
                    }
                }
            } else {
                // Do nothing for other retryable errors.
            }
        }

        func didCancel(record: Store.Record, tx: DBWriteTransaction) {
            logger.warn("Cancelled restoring attachment \(record.record.attachmentRowId), download \(record.id), isThumbnail: \(record.record.isThumbnail)")
            backupAttachmentDownloadStore.remove(
                attachmentId: record.record.attachmentRowId,
                thumbnail: record.record.isThumbnail,
                tx: tx,
            )
        }

        func didDrainQueue() async {
            switch mode {
            case .thumbnail:
                Logger.info("Did drain thumbnail queue")
            case .fullsize:
                Logger.info("Did drain fullsize queue")
                await progress.didEmptyFullsizeDownloadQueue()
            }
            await statusManager.didEmptyQueue(for: mode)
            switch mode {
            case .thumbnail:
                break
            case .fullsize:
                await db.awaitableWrite { tx in
                    // Go ahead and delete all done rows to reset the byte count.
                    // This isn't load-bearing, but its nice to do just in case
                    // some new download gets added it can just count up to its own
                    // total.
                    backupAttachmentDownloadStore.deleteAllDone(tx: tx)
                }
            }
        }
    }

    // MARK: - TaskRecordStore

    struct TaskRecord: SignalServiceKit.TaskRecord {
        let id: QueuedBackupAttachmentDownload.IDType
        let record: QueuedBackupAttachmentDownload
        let nextRetryTimestamp: UInt64?
    }

    class TaskStore: TaskRecordStore {

        private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore

        private let mode: BackupAttachmentDownloadQueueMode

        init(
            mode: BackupAttachmentDownloadQueueMode,
            backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        ) {
            self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
            self.mode = mode
        }

        func peek(count: UInt, tx: DBReadTransaction) throws -> [TaskRecord] {
            let forThumbnailDownloads = switch mode {
            case .thumbnail: true
            case .fullsize: false
            }
            return try backupAttachmentDownloadStore.peek(
                count: count,
                isThumbnail: forThumbnailDownloads,
                tx: tx,
            ).map { record in
                return TaskRecord(
                    id: record.id!,
                    record: record,
                    nextRetryTimestamp: record.minRetryTimestamp,
                )
            }
        }

        func removeRecord(_ record: TaskRecord, tx: DBWriteTransaction) throws {
            // Rather than remove when we finish running a record, we mark it done
            // instead in the success callback, and delete it in failure callbacks.
            // So we do nothing here on purpose.
        }
    }

    // MARK: -

    private enum Constants {
        static let numParallelDownloadsFullsize: UInt = 12
        static let numParallelDownloadsThumbnail: UInt = 8
    }
}

#if TESTABLE_BUILD

open class BackupAttachmentDownloadQueueRunnerMock: BackupAttachmentDownloadQueueRunner {

    public init() {}

    public func restoreAttachmentsIfNeeded(mode: BackupAttachmentDownloadQueueMode) async throws {
        // Do nothing
    }

    public func backupPlanDidChange(
        from oldPlan: BackupPlan,
        to newPlan: BackupPlan,
        tx: DBWriteTransaction,
    ) throws {
        // Do nothing
    }

    public func prepareToDisableBackups(currentBackupPlan: BackupPlan, tx: DBWriteTransaction) throws {
        // Do nothing
    }
}

#endif
