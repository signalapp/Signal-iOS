//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol BackupAttachmentDownloadManager {

    /// "Enqueue" an attachment from a backup for download, if needed and eligible, otherwise do nothing.
    ///
    /// If the same attachment pointed to by the reference is already enqueued, updates it to the greater
    /// of the existing and new reference's timestamp.
    ///
    /// Doesn't actually trigger a download; callers must later call `restoreAttachmentsIfNeeded`
    /// to insert rows into the normal AttachmentDownloadQueue and download.
    func enqueueIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        tx: DBWriteTransaction
    ) throws

    /// Restores all pending attachments in the BackupAttachmentUDownloadQueue.
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
}

public class BackupAttachmentDownloadManagerImpl: BackupAttachmentDownloadManager {

    private let appReadiness: AppReadiness
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let dateProvider: DateProvider
    private let db: DB
    private let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
    private let reachabilityManager: SSKReachabilityManager
    private let taskQueue: TaskQueueLoader<TaskRunner>
    private let tsAccountManager: TSAccountManager

    public init(
        appReadiness: AppReadiness,
        attachmentStore: AttachmentStore,
        attachmentDownloadManager: AttachmentDownloadManager,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        dateProvider: @escaping DateProvider,
        db: DB,
        mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
        messageBackupRequestManager: MessageBackupRequestManager,
        reachabilityManager: SSKReachabilityManager,
        tsAccountManager: TSAccountManager
    ) {
        self.appReadiness = appReadiness
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.dateProvider = dateProvider
        self.db = db
        self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
        self.reachabilityManager = reachabilityManager
        self.tsAccountManager = tsAccountManager
        let taskRunner = TaskRunner(
            attachmentStore: attachmentStore,
            attachmentDownloadManager: attachmentDownloadManager,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            dateProvider: dateProvider,
            db: db,
            mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
            messageBackupRequestManager: messageBackupRequestManager,
            tsAccountManager: tsAccountManager
        )
        self.taskQueue = TaskQueueLoader(
            maxConcurrentTasks: Constants.numParallelDownloads,
            db: db,
            runner: taskRunner
        )
        taskRunner.taskQueueLoader = taskQueue

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            Task { [weak self] in
                try await self?.restoreAttachmentsIfNeeded()
            }
            self?.startObserving()
        }
    }

    public func enqueueIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
        tx: DBWriteTransaction
    ) throws {
        let timestamp: UInt64?
        switch referencedAttachment.reference.owner {
        case .message(let messageSource):
            switch messageSource {
            case .bodyAttachment(let metadata):
                timestamp = metadata.receivedAtTimestamp
            case .oversizeText(let metadata):
                timestamp = metadata.receivedAtTimestamp
            case .linkPreview(let metadata):
                timestamp = metadata.receivedAtTimestamp
            case .quotedReply(let metadata):
                timestamp = metadata.receivedAtTimestamp
            case .sticker(let metadata):
                timestamp = metadata.receivedAtTimestamp
            case .contactAvatar(let metadata):
                timestamp = metadata.receivedAtTimestamp
            }
        case .thread:
            timestamp = nil
        case .storyMessage:
            owsFailDebug("Story messages shouldn't have been backed up")
            timestamp = nil
        }

        let eligibility = Eligibility.forAttachment(
            referencedAttachment.attachment,
            attachmentTimestamp: timestamp,
            dateProvider: dateProvider,
            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
            tx: tx
        )

        guard eligibility.canBeDownloadedAtAll else {
            return
        }

        try backupAttachmentDownloadStore.enqueue(
            referencedAttachment.reference,
            tx: tx
        )
    }

    public func restoreAttachmentsIfNeeded() async throws {
        guard appReadiness.isAppReady else {
            return
        }
        guard tsAccountManager.localIdentifiersWithMaybeSneakyTransaction != nil else {
            return
        }

        let downlodableSources = mediaBandwidthPreferenceStore.downloadableSources()
        guard
            downlodableSources.contains(.mediaTierFullsize)
            || downlodableSources.contains(.mediaTierThumbnail)
        else {
            Logger.info("Skipping backup attachment downloads while not on wifi")
            return
        }
        try await taskQueue.loadAndRunTasks()
    }

    public func cancelPendingDownloads() async throws {
        try await taskQueue.stop()
        try await db.awaitableWrite { tx in
            try self.backupAttachmentDownloadStore.removeAll(tx: tx)
        }
    }

    // MARK: - Reachability

    private func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reachabililityDidChange),
            name: SSKReachability.owsReachabilityDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didUpdateRegistrationState),
            name: .registrationStateDidChange,
            object: nil
        )
    }

    @objc
    private func reachabililityDidChange() {
        if reachabilityManager.isReachable(via: .wifi) {
            Task {
                try await self.restoreAttachmentsIfNeeded()
            }
        }
    }

    @objc
        private func didUpdateRegistrationState() {
            Task {
                try await restoreAttachmentsIfNeeded()
            }
        }

    // MARK: - TaskRecordRunner

    private final class TaskRunner: TaskRecordRunner {

        private let attachmentStore: AttachmentStore
        private let attachmentDownloadManager: AttachmentDownloadManager
        private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
        private let dateProvider: DateProvider
        private let db: DB
        private let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
        private let messageBackupRequestManager: MessageBackupRequestManager
        private let tsAccountManager: TSAccountManager

        let store: TaskStore

        weak var taskQueueLoader: TaskQueueLoader<TaskRunner>?

        init(
            attachmentStore: AttachmentStore,
            attachmentDownloadManager: AttachmentDownloadManager,
            backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
            dateProvider: @escaping DateProvider,
            db: DB,
            mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
            messageBackupRequestManager: MessageBackupRequestManager,
            tsAccountManager: TSAccountManager
        ) {
            self.attachmentStore = attachmentStore
            self.attachmentDownloadManager = attachmentDownloadManager
            self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
            self.dateProvider = dateProvider
            self.db = db
            self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
            self.messageBackupRequestManager = messageBackupRequestManager
            self.tsAccountManager = tsAccountManager

            self.store = TaskStore(backupAttachmentDownloadStore: backupAttachmentDownloadStore)
        }

        func runTask(record: Store.Record, loader: TaskQueueLoader<TaskRunner>) async -> TaskRecordResult {
            let eligibility = db.read { tx in
                return attachmentStore
                    .fetch(id: record.record.attachmentRowId, tx: tx)
                    .map { attachment in
                        return Eligibility.forAttachment(
                            attachment,
                            attachmentTimestamp: record.record.timestamp,
                            dateProvider: dateProvider,
                            backupAttachmentDownloadStore: backupAttachmentDownloadStore,
                            tx: tx
                        )
                    }
            }
            guard let eligibility, eligibility.canBeDownloadedAtAll else {
                return .cancelled
            }

            // Separately from "eligibility" on a per-download basis, we check
            // network state level eligibility (require wifi). If not capable,
            // return a retryable error but stop running now. We will resume
            // when reconnected.
            let downlodableSources = mediaBandwidthPreferenceStore.downloadableSources()
            guard
                downlodableSources.contains(.mediaTierFullsize)
                || downlodableSources.contains(.mediaTierThumbnail)
            else {
                struct NeedsWifiError: Error {}
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
                    try await self.attachmentDownloadManager.downloadAttachment(
                        id: record.record.attachmentRowId,
                        priority: eligibility.downloadPriority,
                        source: .mediaTierFullsize
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
                    try await self.attachmentDownloadManager.downloadAttachment(
                        id: record.record.attachmentRowId,
                        priority: eligibility.downloadPriority,
                        source: .transitTier
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
                return .unretryableError(downloadError)
            }

            return .success
        }

        func didSucceed(record: Store.Record, tx: any DBWriteTransaction) throws {
            Logger.info("Finished restoring attachment \(record.id)")
        }

        func didFail(record: Store.Record, error: any Error, isRetryable: Bool, tx: any DBWriteTransaction) throws {
            Logger.warn("Failed restoring attachment \(record.id), isRetryable: \(isRetryable), error: \(error)")
        }

        func didCancel(record: Store.Record, tx: any DBWriteTransaction) throws {
            Logger.warn("Cancelled restoring attachment \(record.id)")
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

        func removeRecord(_ record: Record, tx: DBWriteTransaction) throws {
            try backupAttachmentDownloadStore.removeQueuedDownload(record.record, tx: tx)
        }
    }

    // MARK: - Eligibility

    private struct Eligibility {
        let canDownloadTransitTierFullsize: Bool
        let canDownloadMediaTierFullsize: Bool
        let canDownloadThumbnail: Bool
        let downloadPriority: AttachmentDownloadPriority

        var canBeDownloadedAtAll: Bool {
            canDownloadTransitTierFullsize || canDownloadMediaTierFullsize || canDownloadThumbnail
        }

        static func forAttachment(
            _ attachment: Attachment,
            attachmentTimestamp: UInt64?,
            dateProvider: DateProvider,
            backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
            tx: DBReadTransaction
        ) -> Eligibility {
            if attachment.asStream() != nil {
                // If we have a stream already, no need to download anything.
                return Eligibility(
                    canDownloadTransitTierFullsize: false,
                    canDownloadMediaTierFullsize: false,
                    canDownloadThumbnail: false,
                    downloadPriority: .default /* irrelevant */
                )
            }

            let shouldStoreAllMediaLocally = backupAttachmentDownloadStore
                .getShouldStoreAllMediaLocally(tx: tx)

            let isRecent: Bool
            if let attachmentTimestamp {
                // We're "recent" if our newest owning message is from the last month.
                isRecent = Date(millisecondsSince1970: attachmentTimestamp)
                    .addingTimeInterval(kMonthInterval)
                    .isAfter(dateProvider())
            } else {
                // If we don't have a timestamp, its a wallpaper and we should always pass
                // the recency check.
                isRecent = true
            }

            let canDownloadMediaTierFullsize =
                attachment.mediaTierInfo != nil
                && (isRecent || shouldStoreAllMediaLocally)

            let canDownloadTransitTierFullsize: Bool
            if let transitTierInfo = attachment.transitTierInfo {
                // Download if the upload was < 30 days old,
                // otherwise don't bother trying automatically.
                // (The user could still try a manual download later).
                canDownloadTransitTierFullsize = Date(millisecondsSince1970: transitTierInfo.uploadTimestamp)
                    .addingTimeInterval(kMonthInterval)
                    .isAfter(dateProvider())
            } else {
                canDownloadTransitTierFullsize = false
            }

            let canDownloadThumbnail =
                AttachmentBackupThumbnail.canBeThumbnailed(attachment)
                && attachment.thumbnailMediaTierInfo != nil

            let downloadPriority: AttachmentDownloadPriority =
                isRecent ? .backupRestoreHigh : .backupRestoreLow

            return Eligibility(
                canDownloadTransitTierFullsize: canDownloadTransitTierFullsize,
                canDownloadMediaTierFullsize: canDownloadMediaTierFullsize,
                canDownloadThumbnail: canDownloadThumbnail,
                downloadPriority: downloadPriority
            )
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

    public func enqueueIfNeeded(
        _ referencedAttachment: ReferencedAttachment,
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
}

#endif
