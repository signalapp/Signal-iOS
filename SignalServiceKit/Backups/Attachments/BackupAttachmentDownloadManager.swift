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

    /// Respond to a change in backup plan by modifying the download queue as appropriate.
    /// Depending on the state change, may wipe the queue, add things to it, remove only some
    /// things, etc.
    func backupPlanDidChange(
        from oldPlan: BackupPlan,
        to newPlan: BackupPlan,
        tx: DBWriteTransaction
    ) throws
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
    private let taskQueue: TaskQueueLoader<TaskRunner>
    private let tsAccountManager: TSAccountManager

    public init(
        appContext: AppContext,
        appReadiness: AppReadiness,
        attachmentStore: AttachmentStore,
        attachmentDownloadManager: AttachmentDownloadManager,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        backupListMediaManager: BackupListMediaManager,
        backupRequestManager: BackupRequestManager,
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
        self.logger = PrefixedLogger(prefix: "[Backups]")
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.db = db
        self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
        self.progress = progress
        self.remoteConfigProvider = remoteConfigProvider
        self.statusManager = statusManager
        self.tsAccountManager = tsAccountManager

        let taskRunner = TaskRunner(
            attachmentStore: attachmentStore,
            attachmentDownloadManager: attachmentDownloadManager,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            backupRequestManager: backupRequestManager,
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
        self.taskQueue = TaskQueueLoader(
            maxConcurrentTasks: Constants.numParallelDownloads,
            dateProvider: dateProvider,
            db: db,
            runner: taskRunner
        )
        taskRunner.taskQueueLoader = taskQueue

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            self?.startObservingQueueStatus()
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
            try await taskQueue.stop()
            return
        case .noWifiReachability:
            logger.info("Skipping backup attachment downloads while not reachable by wifi")
            try await taskQueue.stop()
            return
        case .noReachability:
            logger.info("Skipping backup attachment downloads while not reachable at all")
            try await taskQueue.stop()
            return
        case .lowBattery:
            logger.info("Skipping backup attachment downloads while low battery")
            try await taskQueue.stop()
            return
        case .lowDiskSpace:
            logger.info("Skipping backup attachment downloads while low on disk space")
            try await taskQueue.stop()
            return
        }

        do {
            try await progress.beginObserving()
        } catch {
            owsFailDebug("Unable to observe download progres \(error.grdbErrorForLogging)")
        }

        try await taskQueue.loadAndRunTasks()
    }

    public func backupPlanDidChange(
        from oldPlan: BackupPlan,
        to newPlan: BackupPlan,
        tx: DBWriteTransaction
    ) throws {
        // Linked devices don't care about state changes; they keep downloading
        // whatever got enqueued at link'n'sync time.
        // (They also don't support storage optimization so that's moot.)
        guard tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice else {
            return
        }

        // Stop the queue; we dont _have_ to do this, but we're about to
        // make changes so may as well stop in progress stuff.
        let stopQueueTask = Task {
            try await taskQueue.stop()
        }
        tx.addSyncCompletion {
            // Restart the queue when we're done
            Task {
                try? await stopQueueTask.value
                try await self.restoreAttachmentsIfNeeded()
            }
        }

        switch (oldPlan, newPlan) {
        case
                (.disabling, .disabling),
                (.disabled, .disabled),
                (.free, .free):
            // No change.
            return
        case
                (.disabling, .free),
                (.disabling, .paid),
                (.disabling, .paidExpiringSoon),
                (.disabling, .paidAsTester),
                (.disabled, .disabling):
            throw OWSAssertionError("Unexpected BackupPlan transition: \(oldPlan) -> \(newPlan)")
        case (.free, .disabling):
            // While in free tier, we may have been continuing downloads
            // from when you were previously paid tier. But that was nice
            // to have; now that we're disabling backups cancel them all.
            try backupAttachmentDownloadStore.markAllReadyIneligible(tx: tx)
            try backupAttachmentDownloadStore.deleteAllDone(tx: tx)
        case
                let (.paid(optimizeLocalStorage), .disabling),
                let (.paidExpiringSoon(optimizeLocalStorage), .disabling),
                let (.paidAsTester(optimizeLocalStorage), .disabling):
            try backupAttachmentDownloadStore.deleteAllDone(tx: tx)
            // Unsuspend; this is the user opt-in to trigger downloads.
            backupSettingsStore.setIsBackupDownloadQueueSuspended(false, tx: tx)
            if optimizeLocalStorage {
                // If we had optimize enabled, make anything ineligible (offloaded
                // attachments) now eligible.
                try backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
            }
        case (_, .disabled):
            // When we disable, we mark everything ineligible and delete all
            // done rows. If we ever re-enable, we will mark those rows
            // ready again.
            try backupAttachmentDownloadStore.deleteAllDone(tx: tx)
            try backupAttachmentDownloadStore.markAllReadyIneligible(tx: tx)
            // This doesn't _really_ do anything, since we don't run the queue
            // when disabled anyway, but may as well suspend.
            backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)

        case (.disabled, .free):
            try backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
            // Suspend the queue so the user has to explicitly opt-in to download.
            backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)

        case
                let (.disabled, .paid(optimizeStorage)),
                let (.disabled, .paidExpiringSoon(optimizeStorage)),
                let (.disabled, .paidAsTester(optimizeStorage)):
            try backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
            // Suspend the queue so the user has to explicitly opt-in to download.
            backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
            if optimizeStorage {
                // Unclear how you would go straight from disabled to optimize
                // enabled, but just go through the motions of both state changes
                // as if they'd happened independently.
                try didEnableOptimizeStorage(tx: tx)
            }

        case
                let (.paid(wasOptimizeLocalStorageEnabled), .free),
                let (.paidExpiringSoon(wasOptimizeLocalStorageEnabled), .free),
                let (.paidAsTester(wasOptimizeLocalStorageEnabled), .free):
            // We explicitly do nothing going from paid to free; we want to continue
            // any downloads that were already running (so we take advantage of the
            // media tier cdn TTL being longer than paid subscription lifetime) but
            // also not schedule (or un-suspend) if we weren't already downloading.
            // But if optimization was on, its now implicitly off, so handle that.
            if wasOptimizeLocalStorageEnabled {
                try didDisableOptimizeStorage(backupPlan: newPlan, tx: tx)
            }

        case
                let (.free, .paid(optimizeStorage)),
                let (.free, .paidExpiringSoon(optimizeStorage)),
                let (.free, .paidAsTester(optimizeStorage)):
            // We explicitly do nothing when going from free to paid; any state
            // changes that will happen will be triggered by list media request
            // handling which will always run at the start of a new upload era.
            // But if we somehow went straight from free to optimize enabled,
            // handle that state transition.
            if optimizeStorage {
                owsFailDebug("Going from free or disabled directly to optimize enabled shouldn't be allowed?")
                try didEnableOptimizeStorage(tx: tx)
            }

        case
                // Downloads don't care if expiring soon or not
                let (.paid(oldOptimize), .paid(newOptimize)),
                let (.paid(oldOptimize), .paidExpiringSoon(newOptimize)),
                let (.paid(oldOptimize), .paidAsTester(newOptimize)),
                let (.paidExpiringSoon(oldOptimize), .paid(newOptimize)),
                let (.paidExpiringSoon(oldOptimize), .paidExpiringSoon(newOptimize)),
                let (.paidExpiringSoon(oldOptimize), .paidAsTester(newOptimize)),
                let (.paidAsTester(oldOptimize), .paid(newOptimize)),
                let (.paidAsTester(oldOptimize), .paidExpiringSoon(newOptimize)),
                let (.paidAsTester(oldOptimize), .paidAsTester(newOptimize)):
            if oldOptimize == newOptimize {
                // Nothing changed.
                break
            } else if newOptimize {
                try didEnableOptimizeStorage(tx: tx)
            } else {
                try didDisableOptimizeStorage(backupPlan: newPlan, tx: tx)
            }
        }
    }

    private func didEnableOptimizeStorage(tx: DBWriteTransaction) throws {
        // When we turn on optimization, make all media tier fullsize downloads
        // from the queue that are past the optimization threshold ineligible.
        // If we downloaded them we'd offload them immediately anyway.
        // This isn't 100% necessary; after all something 29 days old today will be
        // 30 days old tomorrow, so the queue runner will gracefully handle old
        // downloads at run-time anyway. But its more efficient to do in bulk.
        let threshold = dateProvider().ows_millisecondsSince1970 - Attachment.offloadingThresholdMs
        try backupAttachmentDownloadStore.markAllMediaTierFullsizeDownloadsIneligible(
            olderThan: threshold,
            tx: tx
        )
        // Un-suspend; when optimization is enabled we always auto-download
        // the stuff that is eligible (newer attachments).
        backupSettingsStore.setIsBackupDownloadQueueSuspended(false, tx: tx)
        // Reset the progress counter.
        try backupAttachmentDownloadStore.deleteAllDone(tx: tx)
    }

    private func didDisableOptimizeStorage(backupPlan: BackupPlan, tx: DBWriteTransaction) throws {
        // When we turn _off_ optimization, we want to make ready all the media tier downloads,
        // but suspend the queue so we don't immediately start downloading.
        try backupAttachmentDownloadStore.markAllIneligibleReady(tx: tx)
        // Suspend the queue; the user has to explicitly opt in to downloads
        // after optimization is disabled.
        backupSettingsStore.setIsBackupDownloadQueueSuspended(true, tx: tx)
    }

    // MARK: - Queue status observation

    private func startObservingQueueStatus() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queueStatusDidChange),
            name: .backupAttachmentDownloadQueueStatusDidChange,
            object: nil
        )
    }

    @objc
    private func queueStatusDidChange() {
        Task {
            try await self.restoreAttachmentsIfNeeded()
        }
    }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let attachmentStore: AttachmentStore
        private let attachmentDownloadManager: AttachmentDownloadManager
        private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
        private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
        private let backupRequestManager: BackupRequestManager
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

        weak var taskQueueLoader: TaskQueueLoader<TaskRunner>?

        init(
            attachmentStore: AttachmentStore,
            attachmentDownloadManager: AttachmentDownloadManager,
            backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
            backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
            backupRequestManager: BackupRequestManager,
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
            self.attachmentStore = attachmentStore
            self.attachmentDownloadManager = attachmentDownloadManager
            self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
            self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
            self.backupRequestManager = backupRequestManager
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
                backupAttachmentDownloadStore: backupAttachmentDownloadStore,
                dateProvider: dateProvider
            )
        }

        func runTask(record: Store.Record, loader: TaskQueueLoader<TaskRunner>) async -> TaskRecordResult {
            struct SuspendedError: Error {}
            struct NeedsDiskSpaceError: Error {}
            struct NeedsBatteryError: Error {}
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
                try? await taskQueueLoader?.stop()
                return .retryableError(NeedsDiskSpaceError())
            case .lowBattery:
                try? await taskQueueLoader?.stop()
                return .retryableError(NeedsBatteryError())
            case .noWifiReachability, .noReachability:
                try? await taskQueueLoader?.stop()
                return .retryableError(NeedsInternetError())
            case .notRegisteredAndReady:
                try? await taskQueueLoader?.stop()
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

            let source: QueuedAttachmentDownloadRecord.SourceType = {
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
                    eligibility.fullsizeMediaTierState != .ready
                        || record.record.numRetries == 1,
                    eligibility.fullsizeTransitTierState == .ready
                {
                    // Otherwise try transit tier if media tier has failed once before.
                    return .transitTier
                } else {
                    // And then fall back to media tier.
                    return .mediaTierFullsize
                }
            }()

            do {
                try await self.attachmentDownloadManager.downloadAttachment(
                    id: record.record.attachmentRowId,
                    priority: .backupRestore,
                    source: source,
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
                case .suspended, .lowDiskSpace, .lowBattery, .noWifiReachability, .noReachability, .notRegisteredAndReady:
                    // Stop the queue now proactively.
                    try? await taskQueueLoader?.stop()
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
                            owsFailDebug("risk of integer overflow")
                            return nil
                        }
                        // Exponential backoff, starting at 1 day for the first two retries.
                        let initialDelay = UInt64.dayInMs
                        let delay = UInt64(pow(2.0, max(0, Double(record.record.numRetries) - 1))) * initialDelay
                        if delay > UInt64.dayInMs * 30 {
                            // Don't go more than 30 days; stop retrying.
                            logger.info("Giving up retrying attachment download")
                            return nil
                        }
                        return delay
                    }()
                {
                    return .retryableError(RetryMediaTierError(nextRetryTimestamp: nextRetryTimestamp))
                } else if error.httpStatusCode == 404 {
                    return .unretryableError(Unretryable404Error(source: source))
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
            logger.info("Finished restoring attachment \(record.record.attachmentRowId), download \(record.id)")
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

        private struct RetryAsTransitTierError: Error {
            let shouldWipeMediaTierInfo: Bool
        }

        private struct Unretryable404Error: Error {
            let source: QueuedAttachmentDownloadRecord.SourceType
        }

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            logger.warn("Failed restoring attachment \(record.id), isRetryable: \(isRetryable), error: \(error)")

            if
                isRetryable,
                let error = error as? RetryMediaTierError
            {
                var downloadRecord = record.record
                downloadRecord.minRetryTimestamp = error.nextRetryTimestamp
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
                    case .transitTier:
                        try attachmentStore.removeTransitTierInfo(
                            forAttachmentId: record.record.attachmentRowId,
                            tx: tx
                        )
                    }
                }
            } else {
                // Do nothing for other retryable errors.
            }
        }

        func didCancel(record: Store.Record, tx: DBWriteTransaction) throws {
            logger.warn("Cancelled restoring attachment \(record.record.attachmentRowId), download \(record.id)")
            try backupAttachmentDownloadStore.remove(
                attachmentId: record.record.attachmentRowId,
                thumbnail: record.record.isThumbnail,
                tx: tx
            )
        }

        func didDrainQueue() async {
            await progress.didEmptyDownloadQueue()
            await statusManager.didEmptyQueue()
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
        private let dateProvider: DateProvider

        init(
            backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
            dateProvider: @escaping DateProvider,
        ) {
            self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
            self.dateProvider = dateProvider
        }

        func peek(count: UInt, tx: DBReadTransaction) throws -> [TaskRecord] {
            return try backupAttachmentDownloadStore.peek(
                count: count,
                currentTimestamp: dateProvider().ows_millisecondsSince1970,
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
        static let numParallelDownloads: UInt = 4
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
