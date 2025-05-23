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
        shouldOptimizeLocalStorage: Bool,
        remoteConfig: RemoteConfig,
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

    /// Cancel any pending attachment downloads, e.g. when backups are disabled.
    /// Removes all enqueued downloads and attempts to cancel in progress ones.
    func cancelPendingDownloads() async throws

    /// Cancel pending attachment downloads for old media, when "optimize media" is enabled.
    /// Removes all necessary enqueued downloads and attempts to cancel in progress ones.
    func cancelOldPendingDownloads() async throws

    /// Schedule a download from media tier for _every_ attachment for which this is
    /// currently possible (has media tier CDN info).
    /// There are only 3 situations where we want to schedule all media tier downloads:
    /// 1. We just restored a backup
    /// 2. Disabling "optimize media"
    /// 3. After downgrading from paid to free backups and triggering downloads
    ///
    /// The first case is handled by backup restore code, which itself schedules all
    /// restored attachments for download as appropriate.
    /// Case 2 (and 2s, which is equivalent) requires we restore all previously-offloaded
    /// attachmnets, and thus should use this method to schedule all those downloads.
    ///
    /// Note: this does a relatively expensive SQL query so use with caution.
    func scheduleAllMediaTierDownloads(tx: DBWriteTransaction) throws
}

public class BackupAttachmentDownloadManagerImpl: BackupAttachmentDownloadManager {

    private let appContext: AppContext
    private let appReadiness: AppReadiness
    private let attachmentStore: AttachmentStore
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let dateProvider: DateProvider
    private let db: any DB
    private let listMediaManager: BackupListMediaManager
    private let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
    private let progress: BackupAttachmentDownloadProgress
    private let remoteConfigProvider: RemoteConfigProvider
    private let statusManager: BackupAttachmentQueueStatusUpdates
    private let taskQueue: TaskQueueLoader<TaskRunner>
    private let tsAccountManager: TSAccountManager

    public init(
        appContext: AppContext,
        appReadiness: AppReadiness,
        attachmentStore: AttachmentStore,
        attachmentDownloadManager: AttachmentDownloadManager,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupListMediaManager: BackupListMediaManager,
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        dateProvider: @escaping DateProvider,
        db: any DB,
        mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
        progress: BackupAttachmentDownloadProgress,
        remoteConfigProvider: RemoteConfigProvider,
        statusManager: BackupAttachmentQueueStatusUpdates,
        tsAccountManager: TSAccountManager
    ) {
        self.appContext = appContext
        self.appReadiness = appReadiness
        self.attachmentStore = attachmentStore
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.listMediaManager = backupListMediaManager
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionManager = backupSubscriptionManager
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
            backupRequestManager: backupRequestManager,
            backupSettingsStore: backupSettingsStore,
            dateProvider: dateProvider,
            db: db,
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
        shouldOptimizeLocalStorage: Bool,
        remoteConfig: RemoteConfig,
        tx: DBWriteTransaction
    ) throws {
        let eligibility = BackupAttachmentDownloadEligibility.forAttachment(
            referencedAttachment.attachment,
            reference: referencedAttachment.reference,
            currentTimestamp: restoreStartTimestampMs,
            shouldOptimizeLocalStorage: shouldOptimizeLocalStorage,
            remoteConfig: remoteConfig
        )

        guard eligibility.canBeDownloadedAtAll else {
            return
        }

        let wasPreviouslyEnqueued = try backupAttachmentDownloadStore.enqueue(
            referencedAttachment.reference,
            tx: tx
        )

        // As we go enqueuing attachments, increment the total byte count we
        // need to download.
        if
            !wasPreviouslyEnqueued,
            let byteCount = referencedAttachment.attachment.anyPointerFullsizeUnencryptedByteCount
        {
            let totalPendingByteCount = backupAttachmentDownloadStore.getTotalPendingDownloadByteCount(tx: tx) ?? 0
            backupAttachmentDownloadStore.setTotalPendingDownloadByteCount(
                totalPendingByteCount + UInt64(Cryptography.paddedSize(unpaddedSize: UInt(byteCount))),
                tx: tx
            )
        }
    }

    public func restoreAttachmentsIfNeeded() async throws {
        guard appContext.isMainApp else { return }

        if
            FeatureFlags.Backups.remoteExportAlpha,
            db.read(block: tsAccountManager.registrationState(tx:))
                .isRegistered
        {
            try await listMediaManager.queryListMediaIfNeeded()
        }

        switch await statusManager.beginObservingIfNeeded(type: .download) {
        case .running:
            break
        case .empty:
            // The queue will stop on its own if empty.
            return
        case .notRegisteredAndReady:
            try await taskQueue.stop()
            return
        case .noWifiReachability:
            Logger.info("Skipping backup attachment downloads while not reachable by wifi")
            try await taskQueue.stop()
            return
        case .lowBattery:
            Logger.info("Skipping backup attachment downloads while low battery")
            try await taskQueue.stop()
            return
        case .lowDiskSpace:
            Logger.info("Skipping backup attachment downloads while low on disk space")
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

    public func cancelPendingDownloads() async throws {
        try await taskQueue.stop()
        try await db.awaitableWrite { tx in
            try self.backupAttachmentDownloadStore.removeAll(tx: tx)
            backupAttachmentDownloadStore.setTotalPendingDownloadByteCount(nil, tx: tx)
            backupAttachmentDownloadStore.setCachedRemainingPendingDownloadByteCount(nil, tx: tx)
        }
        // Reset progress calculation
        try? await progress.beginObserving()
        // Kill status observation
        await statusManager.didEmptyQueue(type: .download)
    }

    public func cancelOldPendingDownloads() async throws {
        // Stop current downloads
        try await taskQueue.stop()
        try await db.awaitableWrite { tx in
            // Downloads are already tagged with the latest timestamp of
            // owning message(s); just dequeue any with timestamps older
            // than the offloading threshold.
            // Anything older than that threshold should be offloaded.
            // unless viewed recently, but you can't view undownloaded
            // attachments so that't moot.
            try self.backupAttachmentDownloadStore.removeAll(
                olderThan: dateProvider().ows_millisecondsSince1970 - Attachment.offloadingThresholdMs,
                tx: tx
            )

            // Count the total bytes to download from scratch for the
            // remaining enqueued downloads.
            var totalRemainingByteCount: UInt64 = 0
            let cursor = try QueuedBackupAttachmentDownload
                .fetchCursor(tx.database)
            while let download = try cursor.next() {
                guard
                    let attachment = attachmentStore.fetch(id: download.attachmentRowId, tx: tx),
                    let unencryptedByteCount = attachment.mediaTierInfo?.unencryptedByteCount
                        ?? attachment.transitTierInfo?.unencryptedByteCount
                else {
                    continue
                }
                totalRemainingByteCount += UInt64(Cryptography.paddedSize(
                    unpaddedSize: UInt(unencryptedByteCount))
                )
            }

            backupAttachmentDownloadStore.setTotalPendingDownloadByteCount(totalRemainingByteCount, tx: tx)
            backupAttachmentDownloadStore.setCachedRemainingPendingDownloadByteCount(totalRemainingByteCount, tx: tx)
        }
        // Kick the tires again to resume downloads.
        try await restoreAttachmentsIfNeeded()
    }

    public func scheduleAllMediaTierDownloads(tx: DBWriteTransaction) throws {
        // Kick off downloads once the transaction commits.
        tx.addSyncCompletion { [weak self] in
            Task {
                try await self?.restoreAttachmentsIfNeeded()
            }
        }

        let currentDate = dateProvider()
        let currentUploadEra = backupSubscriptionManager.getUploadEra(tx: tx)
        let shouldOptimizeLocalStorage = backupSettingsStore
            .getShouldOptimizeLocalStorage(tx: tx)
        let backupPlan = backupSettingsStore.backupPlan(tx: tx)
        let remoteConfig = remoteConfigProvider.currentConfig()

        owsAssertDebug(
            !shouldOptimizeLocalStorage || backupPlan != .paid,
            "Why are we scheduling all downloads when media shouldn't be stored locally?"
        )

        let cursor = try Attachment.Record
            // Ignore stuff already downloaded, duh
            .filter(Column(Attachment.Record.CodingKeys.localRelativeFilePath) == nil)
            // We need a mediaName to download
            .filter(Column(Attachment.Record.CodingKeys.mediaName) != nil)
            // Only download stuff in the current upload era; other stuff we don't expect
            // to be available for download.
            .filter(Column(Attachment.Record.CodingKeys.mediaTierUploadEra) == currentUploadEra)
            .fetchCursor(tx.database)

        var totalPendingByteCount = backupAttachmentDownloadStore.getTotalPendingDownloadByteCount(tx: tx) ?? 0

        while let attachment = try cursor.next() {
            let attachment = try Attachment(record: attachment)

            var cachedReferenceWithMostRecentTimestamp: AttachmentReference?
            let getReferenceWithMostRecentTimestamp = {
                if let cachedReferenceWithMostRecentTimestamp {
                    return cachedReferenceWithMostRecentTimestamp
                }
                let reference = try self.attachmentStore.fetchMostRecentReference(
                    toAttachmentId: attachment.id,
                    tx: tx
                )
                cachedReferenceWithMostRecentTimestamp = reference
                return reference
            }

            let eligibility = try BackupAttachmentDownloadEligibility.forAttachment(
                attachment,
                reference: getReferenceWithMostRecentTimestamp(),
                currentTimestamp: currentDate.ows_millisecondsSince1970,
                shouldOptimizeLocalStorage: shouldOptimizeLocalStorage,
                remoteConfig: remoteConfig
            )

            guard eligibility.canBeDownloadedAtAll else {
                continue
            }

            let wasPreviouslyEnqueued = try backupAttachmentDownloadStore.enqueue(
                try getReferenceWithMostRecentTimestamp(),
                tx: tx
            )

            // As we go enqueuing attachments, increment the total byte count we
            // need to download.
            if
                !wasPreviouslyEnqueued,
                let byteCount = attachment.anyPointerFullsizeUnencryptedByteCount
            {
                totalPendingByteCount += UInt64(Cryptography.paddedSize(unpaddedSize: UInt(byteCount)))
            }
        }

        backupAttachmentDownloadStore.setTotalPendingDownloadByteCount(
            totalPendingByteCount,
            tx: tx
        )

        // We want to list media before we go doing any downloads, to ensure we have the latest
        // CDN information. To that end, wipe the most recent list media upload era so that
        // we will query again.
        listMediaManager.setNeedsQueryListMedia(tx: tx)
    }

    // MARK: - Queue status observation

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
        guard type as? BackupAttachmentQueueType == .download else { return }
        Task {
            try await self.restoreAttachmentsIfNeeded()
        }
    }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let attachmentStore: AttachmentStore
        private let attachmentDownloadManager: AttachmentDownloadManager
        private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
        private let backupRequestManager: BackupRequestManager
        private let backupSettingsStore: BackupSettingsStore
        private let dateProvider: DateProvider
        private let db: any DB
        private let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
        private let progress: BackupAttachmentDownloadProgress
        private let remoteConfigProvider: RemoteConfigProvider
        private let statusManager: BackupAttachmentQueueStatusUpdates
        private let tsAccountManager: TSAccountManager

        let store: TaskStore

        weak var taskQueueLoader: TaskQueueLoader<TaskRunner>?

        init(
            attachmentStore: AttachmentStore,
            attachmentDownloadManager: AttachmentDownloadManager,
            backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
            backupRequestManager: BackupRequestManager,
            backupSettingsStore: BackupSettingsStore,
            dateProvider: @escaping DateProvider,
            db: any DB,
            mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
            progress: BackupAttachmentDownloadProgress,
            remoteConfigProvider: RemoteConfigProvider,
            statusManager: BackupAttachmentQueueStatusUpdates,
            tsAccountManager: TSAccountManager
        ) {
            self.attachmentStore = attachmentStore
            self.attachmentDownloadManager = attachmentDownloadManager
            self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
            self.backupRequestManager = backupRequestManager
            self.backupSettingsStore = backupSettingsStore
            self.dateProvider = dateProvider
            self.db = db
            self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
            self.progress = progress
            self.remoteConfigProvider = remoteConfigProvider
            self.statusManager = statusManager
            self.tsAccountManager = tsAccountManager

            self.store = TaskStore(backupAttachmentDownloadStore: backupAttachmentDownloadStore)
        }

        func runTask(record: Store.Record, loader: TaskQueueLoader<TaskRunner>) async -> TaskRecordResult {
            struct NeedsDiskSpaceError: Error {}
            struct NeedsBatteryError: Error {}
            struct NeedsWifiError: Error {}
            struct NeedsToBeRegisteredError: Error {}

            switch await statusManager.quickCheckDiskSpaceForDownloads() {
            case nil:
                // No state change, keep going.
                break
            case .running:
                break
            case .empty:
                // The queue will stop on its own, finish this task.
                break
            case .lowDiskSpace:
                try? await taskQueueLoader?.stop()
                return .retryableError(NeedsDiskSpaceError())
            case .lowBattery:
                try? await taskQueueLoader?.stop()
                return .retryableError(NeedsBatteryError())
            case .noWifiReachability:
                try? await taskQueueLoader?.stop()
                return .retryableError(NeedsWifiError())
            case .notRegisteredAndReady:
                try? await taskQueueLoader?.stop()
                return .retryableError(NeedsToBeRegisteredError())
            }

            let (attachment, eligibility) = db.read { (tx) -> (Attachment?, BackupAttachmentDownloadEligibility?) in
                let nowMs = dateProvider().ows_millisecondsSince1970
                let shouldOptimizeLocalStorage = backupSettingsStore.getShouldOptimizeLocalStorage(tx: tx)
                let remoteConfig = remoteConfigProvider.currentConfig()

                return attachmentStore
                    .fetch(id: record.record.attachmentRowId, tx: tx)
                    .map { attachment in
                        let eligibility = BackupAttachmentDownloadEligibility.forAttachment(
                            attachment,
                            downloadRecord: record.record,
                            currentTimestamp: nowMs,
                            shouldOptimizeLocalStorage: shouldOptimizeLocalStorage,
                            remoteConfig: remoteConfig
                        )
                        return (attachment, eligibility)
                    } ?? (nil, nil)
            }
            guard let attachment, let eligibility, eligibility.canBeDownloadedAtAll else {
                return .cancelled
            }

            /// Media and transit tier byte counts should be interchangeable.
            /// Still, we shouldn't rely on this for anything other that progress tracking,
            /// where its just a UI glitch if it turns out they are not.
            let fullsizeByteCountForProgress = UInt64(
                Cryptography.paddedSize(
                    unpaddedSize: UInt(attachment.anyPointerFullsizeUnencryptedByteCount ?? 0)
                )
            )

            // Separately from "eligibility" on a per-download basis, we check
            // network state level eligibility (require wifi). If not capable,
            // return a retryable error but stop running now. We will resume
            // when reconnected.
            let downlodableSources = mediaBandwidthPreferenceStore.downloadableSources()
            guard
                downlodableSources.contains(.mediaTierFullsize)
                || downlodableSources.contains(.mediaTierThumbnail)
            else {
                let error = NeedsWifiError()
                try? await loader.stop(reason: error)
                // Retryable because we don't want to delete the enqueued record,
                // just stop for now.
                return .retryableError(error)
            }

            var didDownloadFullsize = false
            // Set to the earliest error we encounter. If anything succeeds
            // we'll suppress the error; if everything fails we'll throw it.
            var downloadError: Error?

            // Try media tier fullsize first.
            if eligibility.canDownloadMediaTierFullsize {
                do {
                    let progressSink = await progress.willBeginDownloadingAttachment(withId: record.record.attachmentRowId)
                    try await self.attachmentDownloadManager.downloadAttachment(
                        id: record.record.attachmentRowId,
                        priority: eligibility.downloadPriority,
                        source: .mediaTierFullsize,
                        progress: progressSink
                    )
                    await progress.didFinishDownloadOfAttachment(
                        withId: record.record.attachmentRowId,
                        byteCount: fullsizeByteCountForProgress
                    )
                    didDownloadFullsize = true
                } catch let error {
                    downloadError = downloadError ?? error
                }
            }

            // If we didn't download media tier (either because we weren't eligible
            // or because the download failed), try transit tier fullsize next.
            if !didDownloadFullsize, eligibility.canDownloadTransitTierFullsize {
                do {
                    let progressSink = await progress.willBeginDownloadingAttachment(withId: record.record.attachmentRowId)
                    try await self.attachmentDownloadManager.downloadAttachment(
                        id: record.record.attachmentRowId,
                        priority: eligibility.downloadPriority,
                        source: .transitTier,
                        progress: progressSink
                    )
                    await progress.didFinishDownloadOfAttachment(
                        withId: record.record.attachmentRowId,
                        byteCount: fullsizeByteCountForProgress
                    )
                    didDownloadFullsize = true
                } catch let error {
                    downloadError = downloadError ?? error
                }
            }

            // If we didn't download fullsize (either because we weren't eligible
            // or because the download(s) failed), try thumbnail.
            if !didDownloadFullsize, eligibility.canDownloadThumbnail {
                do {
                    try await self.attachmentDownloadManager.downloadAttachment(
                        id: record.record.attachmentRowId,
                        priority: eligibility.downloadPriority,
                        source: .mediaTierThumbnail
                    )
                } catch let error {
                    downloadError = downloadError ?? error
                }
            }

            if let downloadError {
                switch await statusManager.jobDidExperienceError(type: .download, downloadError) {
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
                    try? await taskQueueLoader?.stop()
                }
                return .unretryableError(downloadError)
            }

            return .success
        }

        func didSucceed(record: Store.Record, tx: DBWriteTransaction) throws {
            Logger.info("Finished restoring attachment \(record.id)")
        }

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            Logger.warn("Failed restoring attachment \(record.id), isRetryable: \(isRetryable), error: \(error)")
        }

        func didCancel(record: Store.Record, tx: DBWriteTransaction) throws {
            Logger.warn("Cancelled restoring attachment \(record.id)")
        }

        func didDrainQueue() async {
            await progress.didEmptyDownloadQueue()
            await statusManager.didEmptyQueue(type: .download)
        }
    }

    // MARK: - TaskRecordStore

    struct TaskRecord: SignalServiceKit.TaskRecord {
        let id: QueuedBackupAttachmentDownload.IDType
        let record: QueuedBackupAttachmentDownload
    }

    class TaskStore: TaskRecordStore {

        private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore

        init(backupAttachmentDownloadStore: BackupAttachmentDownloadStore) {
            self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        }

        func peek(count: UInt, tx: DBReadTransaction) throws -> [TaskRecord] {
            return try backupAttachmentDownloadStore.peek(count: count, tx: tx).map { record in
                return TaskRecord(id: record.id!, record: record)
            }
        }

        func removeRecord(_ record: TaskRecord, tx: DBWriteTransaction) throws {
            try backupAttachmentDownloadStore.removeQueuedDownload(attachmentId: record.id, tx: tx)
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
        shouldOptimizeLocalStorage: Bool,
        remoteConfig: RemoteConfig,
        tx: DBWriteTransaction
    ) throws {
        // Do nothing
    }

    public func restoreAttachmentsIfNeeded() async throws {
        // Do nothing
    }

    public func cancelPendingDownloads() async throws {
        // Do nothing
    }

    public  func cancelOldPendingDownloads() async throws {
        // Do nothing
    }

    public func scheduleAllMediaTierDownloads(tx: DBWriteTransaction) throws {
        // Do nothing
    }
}

#endif
