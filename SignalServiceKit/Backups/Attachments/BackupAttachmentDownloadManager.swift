//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public protocol BackupAttachmentDownloadManager {

    /// "Enqueue" an attachment from a backup for download, if needed and eligible, otherwise do nothing.
    ///
    /// If the same attachment pointed to by the reference is already enqueued, updates it to the greater
    /// of the existing and new reference's timestamp.
    ///
    /// Doesn't actually trigger a download; callers must later call `restoreAttachmentsIfNeeded`
    /// to insert rows into the normal AttachmentDownloadQueue and download.
    func enqueueFromBackupIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        restoreStartTimestampMs: UInt64,
        backupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        isPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) throws

    /// Restores all pending attachments in the BackupAttachmentDownloadQueue.
    ///
    /// Will keep restoring attachments until there are none left, then returns.
    /// Is cooperatively cancellable; will check and early terminate if the task is cancelled
    /// in between individual attachments.
    ///
    /// Returns immediately if there's no attachments left to restore.
    ///
    /// Each individual attachments has its thumbnail and fullsize data downloaded as appropriate.
    ///
    /// Throws an error IFF something would prevent all attachments from restoring (e.g. network issue).
    func restoreAttachmentsIfNeeded() async throws
}

public class BackupAttachmentDownloadManagerImpl: BackupAttachmentDownloadManager {

    private let appContext: AppContext
    private let appReadiness: AppReadiness
    private let attachmentStore: AttachmentStore
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
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

    private let fullsizeTaskQueue: TaskQueueLoader<TaskRunner>
    private let thumbnailTaskQueue: TaskQueueLoader<TaskRunner>

    public init(
        appContext: AppContext,
        appReadiness: AppReadiness,
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
        tsAccountManager: TSAccountManager
    ) {
        self.appContext = appContext
        self.appReadiness = appReadiness
        self.attachmentStore = attachmentStore
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.listMediaManager = backupListMediaManager
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

        func taskQueue(forThumbnailDownloads: Bool) -> TaskQueueLoader<TaskRunner> {
            let taskRunner = TaskRunner(
                forThumbnailDownloads: forThumbnailDownloads,
                attachmentStore: attachmentStore,
                attachmentDownloadManager: attachmentDownloadManager,
                attachmentUploadStore: attachmentUploadStore,
                backupAttachmentDownloadStore: backupAttachmentDownloadStore,
                backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                backupSettingsStore: backupSettingsStore,
                dateProvider: dateProvider,
                db: db,
                logger: logger,
                mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
                progress: progress,
                remoteConfigProvider: remoteConfigProvider,
                statusManager: statusManager,
                tsAccountManager: tsAccountManager
            )
            return TaskQueueLoader(
                maxConcurrentTasks: forThumbnailDownloads
                    ? Constants.numParallelDownloadsThumbnail
                    : Constants.numParallelDownloadsFullsize,
                dateProvider: dateProvider,
                db: db,
                runner: taskRunner
            )
        }

        self.fullsizeTaskQueue = taskQueue(forThumbnailDownloads: false)
        self.thumbnailTaskQueue = taskQueue(forThumbnailDownloads: true)

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            self?.startObservingExternalEvents()
            Task { [weak self] in
                try await self?.restoreAttachmentsIfNeeded()
            }
        }
    }

    public func enqueueFromBackupIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        restoreStartTimestampMs: UInt64,
        backupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        isPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) throws {
        let eligibility = BackupAttachmentDownloadEligibility.forAttachment(
            referencedAttachment.attachment,
            reference: referencedAttachment.reference,
            currentTimestamp: restoreStartTimestampMs,
            backupPlan: backupPlan,
            remoteConfig: remoteConfig,
            isPrimaryDevice: isPrimaryDevice
        )

        if
            let state = eligibility.thumbnailMediaTierState,
            state != .done
        {
            try backupAttachmentDownloadStore.enqueue(
                referencedAttachment,
                thumbnail: true,
                // Thumbnails are always media tier
                canDownloadFromMediaTier: true,
                state: state,
                currentTimestamp: restoreStartTimestampMs,
                tx: tx
            )
        }
        if
            let state = eligibility.fullsizeState,
            state != .done
        {
            try backupAttachmentDownloadStore.enqueue(
                referencedAttachment,
                thumbnail: false,
                canDownloadFromMediaTier: eligibility.canDownloadMediaTierFullsize,
                state: state,
                currentTimestamp: restoreStartTimestampMs,
                tx: tx
            )
        }
    }

    public func restoreAttachmentsIfNeeded() async throws {
        guard appContext.isMainApp else { return }

        if
            FeatureFlags.Backups.supported,
            db.read(block: tsAccountManager.registrationState(tx:))
                .isRegistered
        {
            try await listMediaManager.queryListMediaIfNeeded()
        }

        switch await statusManager.beginObservingIfNecessary() {
        case .running:
            break
        case .suspended:
            // The queue will stop on its own if suspended
            return
        case .empty:
            // The queue will stop on its own if empty.
            return
        case .notRegisteredAndReady:
            try await fullsizeTaskQueue.stop()
            try await thumbnailTaskQueue.stop()
            return
        case .noWifiReachability:
            logger.info("Skipping backup attachment downloads while not reachable by wifi")
            try await fullsizeTaskQueue.stop()
            try await thumbnailTaskQueue.stop()
            return
        case .noReachability:
            logger.info("Skipping backup attachment downloads while not reachable at all")
            try await fullsizeTaskQueue.stop()
            try await thumbnailTaskQueue.stop()
            return
        case .lowBattery:
            logger.info("Skipping backup attachment downloads while low battery")
            try await fullsizeTaskQueue.stop()
            try await thumbnailTaskQueue.stop()
            return
        case .lowDiskSpace:
            logger.info("Skipping backup attachment downloads while low on disk space")
            try await fullsizeTaskQueue.stop()
            try await thumbnailTaskQueue.stop()
            return
        case .appBackgrounded:
            logger.info("Skipping backup attachment downloads while backgrounded")
            try await fullsizeTaskQueue.stop()
            try await thumbnailTaskQueue.stop()
            return
        }

        do {
            try await progress.beginObserving()
        } catch {
            owsFailDebug("Unable to observe download progres \(error.grdbErrorForLogging)")
        }

        let backgroundTask = OWSBackgroundTask(
            label: #function
        ) { [weak fullsizeTaskQueue, weak thumbnailTaskQueue] status in
            switch status {
            case .expired:
                Task {
                    try? await fullsizeTaskQueue?.stop()
                    try? await thumbnailTaskQueue?.stop()
                }
            case .couldNotStart, .success:
                break
            }
        }
        defer { backgroundTask.end() }

        let fullsizeTask = Task { [fullsizeTaskQueue] in
            try await fullsizeTaskQueue.loadAndRunTasks()
        }
        let thumbnailTask = Task { [thumbnailTaskQueue] in
            try await thumbnailTaskQueue.loadAndRunTasks()
        }
        try await fullsizeTask.value
        try await thumbnailTask.value
    }

    // MARK: - Queue status observation

    private func startObservingExternalEvents() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queueStatusDidChange),
            name: .backupAttachmentDownloadQueueStatusDidChange,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(backupPlanDidChange),
            name: .backupPlanChanged,
            object: nil
        )
    }

    @objc
    private func queueStatusDidChange() {
        Task {
            try await self.restoreAttachmentsIfNeeded()
        }
    }

    @objc
    private func backupPlanDidChange() {
        Task {
            try await self.restoreAttachmentsIfNeeded()
        }
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
        private let logger: PrefixedLogger
        private let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
        private let progress: BackupAttachmentDownloadProgress
        private let remoteConfigProvider: RemoteConfigProvider
        private let statusManager: BackupAttachmentDownloadQueueStatusManager
        private let tsAccountManager: TSAccountManager

        let store: TaskStore

        private let forThumbnailDownloads: Bool

        init(
            forThumbnailDownloads: Bool,
            attachmentStore: AttachmentStore,
            attachmentDownloadManager: AttachmentDownloadManager,
            attachmentUploadStore: AttachmentUploadStore,
            backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
            backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
            backupSettingsStore: BackupSettingsStore,
            dateProvider: @escaping DateProvider,
            db: any DB,
            logger: PrefixedLogger,
            mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
            progress: BackupAttachmentDownloadProgress,
            remoteConfigProvider: RemoteConfigProvider,
            statusManager: BackupAttachmentDownloadQueueStatusManager,
            tsAccountManager: TSAccountManager
        ) {
            self.forThumbnailDownloads = forThumbnailDownloads
            self.attachmentStore = attachmentStore
            self.attachmentDownloadManager = attachmentDownloadManager
            self.attachmentUploadStore = attachmentUploadStore
            self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
            self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
            self.backupSettingsStore = backupSettingsStore
            self.dateProvider = dateProvider
            self.db = db
            self.logger = logger
            self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
            self.progress = progress
            self.remoteConfigProvider = remoteConfigProvider
            self.statusManager = statusManager
            self.tsAccountManager = tsAccountManager

            self.store = TaskStore(
                forThumbnailDownloads: forThumbnailDownloads,
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

            switch await statusManager.currentStatus() {
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
            case .lowBattery:
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
                registrationState
            ) = db.read { (tx) -> (Attachment?, BackupPlan, TSRegistrationState) in
                return (
                    attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx),
                    backupSettingsStore.backupPlan(tx: tx),
                    tsAccountManager.registrationState(tx: tx)
                )
            }

            guard let attachment else {
                return .cancelled
            }

            let progressSink = await progress.willBeginDownloadingAttachment(
                withId: record.record.attachmentRowId,
                isThumbnail: record.record.isThumbnail
            )

            let nowMs = dateProvider().ows_millisecondsSince1970
            let remoteConfig = remoteConfigProvider.currentConfig()
            let eligibility = BackupAttachmentDownloadEligibility.forAttachment(
                attachment,
                downloadRecord: record.record,
                currentTimestamp: nowMs,
                backupPlan: backupPlan,
                remoteConfig: remoteConfig,
                isPrimaryDevice: registrationState.isRegisteredPrimaryDevice
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
                await progress.didFinishDownloadOfAttachment(
                    withId: record.record.attachmentRowId,
                    isThumbnail: record.record.isThumbnail,
                    byteCount: UInt64(record.record.estimatedByteCount)
                )
                return .cancelled
            case .ineligible:
                // Current state prevents running this row; unclear how we
                // got here but mark it ineligible in the queue now and return
                // a a "retryable" error so we don't wipe this row from the queue.
                // Since its now ineligible it will be skipped going forward.
                try? await db.awaitableWrite { tx in
                    try backupAttachmentDownloadStore.markIneligible(
                        attachmentId: attachment.id,
                        thumbnail: record.record.isThumbnail,
                        tx: tx
                    )
                }
                return .retryableError(NoLongerEligibleError())
            case .done:
                // All done! Mark done and treat it as a "retryable" error
                // so we don't wipe this row from the queue. Since its now
                // done it will be skipped going forward.
                try? await db.awaitableWrite { tx in
                    try backupAttachmentDownloadStore.markDone(
                        attachmentId: attachment.id,
                        thumbnail: record.record.isThumbnail,
                        tx: tx
                    )
                }
                // count this as having completed the download.
                await progress.didFinishDownloadOfAttachment(
                    withId: record.record.attachmentRowId,
                    isThumbnail: record.record.isThumbnail,
                    byteCount: UInt64(record.record.estimatedByteCount)
                )
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
                    progress: progressSink
                )
            } catch let error {
                switch await statusManager.jobDidExperienceError(error) {
                case nil:
                    // No state change, keep going.
                    break
                case .running:
                    break
                case .empty:
                    // The queue will stop on its own, finish this task.
                    break
                case .suspended, .lowDiskSpace, .lowBattery, .noWifiReachability, .noReachability, .appBackgrounded, .notRegisteredAndReady:
                    // Stop the queue now proactively.
                    try? await loader.stop()
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
                        shouldWipeMediaTierInfo: error.httpStatusCode == 404 && !canRetryMediaTier404()
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
                } else if
                    error.is5xxServiceResponse,
                    let nextRetryTimestamp = { () -> UInt64? in
                        guard record.record.numRetries < 5 else {
                            owsFailDebug("Too many retries!")
                            return nil
                        }
                        let delay = OWSOperation.retryIntervalForExponentialBackoff(
                            failureCount: record.record.numRetries,
                            minAverageBackoff: 2,
                            maxAverageBackoff: 60 * 60,
                        )
                        return dateProvider().addingTimeInterval(delay).ows_millisecondsSince1970
                    }()
                {
                    // Retry 500s per-item.
                    return .retryableError(Retry5xxError(nextRetryTimestamp: nextRetryTimestamp))
                } else {
                    return .unretryableError(error)
                }
            }

            await progress.didFinishDownloadOfAttachment(
                withId: record.record.attachmentRowId,
                isThumbnail: record.record.isThumbnail,
                byteCount: UInt64(record.record.estimatedByteCount)
            )

            return .success
        }

        func didSucceed(record: Store.Record, tx: DBWriteTransaction) throws {
            logger.info("Finished restoring attachment \(record.record.attachmentRowId), download \(record.id), isThumbnail: \(record.record.isThumbnail)")
            // Mark the record done when we succeed; this will filter it out
            // from future queue pop/peek operations.
            try backupAttachmentDownloadStore.markDone(
                attachmentId: record.record.attachmentRowId,
                thumbnail: record.record.isThumbnail,
                tx: tx
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
                        tx: tx
                    )
                    if
                        let stream = attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx)?.asStream()
                    {
                        try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                            stream.attachment,
                            mode: .fullsizeOnly,
                            tx: tx
                        )
                    }
                }
            } else if !isRetryable {
                try backupAttachmentDownloadStore.remove(
                    attachmentId: record.record.attachmentRowId,
                    thumbnail: record.record.isThumbnail,
                    tx: tx
                )
                // For non-retryable 404 errors, go ahead and wipe the relevant cdn
                // info from the attachment, as download failed.
                if let error = error as? Unretryable404Error {
                    switch error.source {
                    case .mediaTierThumbnail:
                        try attachmentStore.removeThumbnailMediaTierInfo(
                            forAttachmentId: record.record.attachmentRowId,
                            tx: tx
                        )
                        if
                            let stream = attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx)?.asStream()
                        {
                            try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                                stream.attachment,
                                mode: .thumbnailOnly,
                                tx: tx
                            )
                        }
                    case .mediaTierFullsize:
                        try attachmentStore.removeMediaTierInfo(
                            forAttachmentId: record.record.attachmentRowId,
                            tx: tx
                        )
                        if
                            let stream = attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx)?.asStream()
                        {
                            try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                                stream.attachment,
                                mode: .fullsizeOnly,
                                tx: tx
                            )
                        }
                    case .transitTier(let transitTierInfo):
                        if let attachment = attachmentStore.fetch(id: record.record.attachmentRowId, tx: tx) {
                            try attachmentUploadStore.markTransitTierUploadExpired(
                                attachment: attachment,
                                info: transitTierInfo,
                                tx: tx
                            )
                        }
                    }
                }
            } else {
                // Do nothing for other retryable errors.
            }
        }

        func didCancel(record: Store.Record, tx: DBWriteTransaction) throws {
            logger.warn("Cancelled restoring attachment \(record.record.attachmentRowId), download \(record.id), isThumbnail: \(record.record.isThumbnail)")
            try backupAttachmentDownloadStore.remove(
                attachmentId: record.record.attachmentRowId,
                thumbnail: record.record.isThumbnail,
                tx: tx
            )
        }

        func didDrainQueue() async {
            await progress.didEmptyDownloadQueue(isThumbnail: forThumbnailDownloads)
            await statusManager.didEmptyQueue(isThumbnail: forThumbnailDownloads)
            await db.awaitableWrite { tx in
                // Go ahead and delete all done rows to reset the byte count.
                // This isn't load-bearing, but its nice to do just in case
                // some new download gets added it can just count up to its own
                    // total.
                try? backupAttachmentDownloadStore.deleteAllDone(tx: tx)
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

        private let forThumbnailDownloads: Bool

        init(
            forThumbnailDownloads: Bool,
            backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        ) {
            self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
            self.forThumbnailDownloads = forThumbnailDownloads
        }

        func peek(count: UInt, tx: DBReadTransaction) throws -> [TaskRecord] {
            return try backupAttachmentDownloadStore.peek(
                count: count,
                isThumbnail: forThumbnailDownloads,
                tx: tx
            ).map { record in
                return TaskRecord(
                    id: record.id!,
                    record: record,
                    nextRetryTimestamp: record.minRetryTimestamp
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
        static let numParallelDownloadsFullsize: UInt = 4
        static let numParallelDownloadsThumbnail: UInt = 4
    }
}

#if TESTABLE_BUILD

open class BackupAttachmentDownloadManagerMock: BackupAttachmentDownloadManager {

    public init() {}

    public func enqueueFromBackupIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        restoreStartTimestampMs: UInt64,
        backupPlan: BackupPlan,
        remoteConfig: RemoteConfig,
        isPrimaryDevice: Bool,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    public func restoreAttachmentsIfNeeded() async throws {
        // Do nothing
    }

    public func backupPlanDidChange(
        from oldPlan: BackupPlan,
        to newPlan: BackupPlan,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    public func prepareToDisableBackups(currentBackupPlan: BackupPlan, tx: DBWriteTransaction) throws {
        // Do nothing
    }
}

#endif
