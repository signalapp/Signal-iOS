//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentDownloadManagerImpl: AttachmentDownloadManager {

    private enum DownloadResult {
        case stream(AttachmentStream)
        case thumbnail(AttachmentBackupThumbnail)
    }

    private let appReadiness: AppReadiness
    private let attachmentDownloadStore: AttachmentDownloadStore
    private let attachmentStore: AttachmentStore
    private let attachmentUpdater: AttachmentUpdater
    private let backupSettingsStore: BackupSettingsStore
    private let db: any DB
    private let decrypter: Decrypter
    private let downloadQueue: DownloadQueue
    private let downloadabilityChecker: DownloadabilityChecker
    private let progressStates: ProgressStates
    private let queueLoader: TaskQueueLoader<DownloadTaskRunner>
    private let remoteConfigProvider: any RemoteConfigProvider
    private let tsAccountManager: TSAccountManager

    public init(
        accountKeyStore: AccountKeyStore,
        appReadiness: AppReadiness,
        attachmentDownloadStore: AttachmentDownloadStore,
        attachmentStore: AttachmentStore,
        attachmentUploadStore: AttachmentUploadStore,
        attachmentValidator: AttachmentContentValidator,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        backupRequestManager: BackupRequestManager,
        backupSettingsStore: BackupSettingsStore,
        currentCallProvider: CurrentCallProvider,
        dateProvider: @escaping DateProvider,
        db: any DB,
        interactionStore: InteractionStore,
        mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
        orphanedBackupAttachmentScheduler: OrphanedBackupAttachmentScheduler,
        profileManager: ProfileManager,
        reachabilityManager: SSKReachabilityManager,
        remoteConfigProvider: any RemoteConfigProvider,
        signalService: OWSSignalServiceProtocol,
        stickerManager: Shims.StickerManager,
        storyStore: any StoryStore,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager,
    ) {
        self.attachmentDownloadStore = attachmentDownloadStore
        self.attachmentStore = attachmentStore
        self.appReadiness = appReadiness
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.decrypter = Decrypter(
            attachmentValidator: attachmentValidator,
            stickerManager: stickerManager,
        )
        self.progressStates = ProgressStates()
        self.downloadQueue = DownloadQueue(
            progressStates: progressStates,
            signalService: signalService,
        )
        self.attachmentUpdater = AttachmentUpdater(
            attachmentStore: attachmentStore,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            dateProvider: dateProvider,
            db: db,
            decrypter: decrypter,
            interactionStore: interactionStore,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
            orphanedBackupAttachmentScheduler: orphanedBackupAttachmentScheduler,
            storyStore: storyStore,
            threadStore: threadStore,
        )
        self.downloadabilityChecker = DownloadabilityChecker(
            attachmentStore: attachmentStore,
            backupSettingsStore: backupSettingsStore,
            currentCallProvider: currentCallProvider,
            db: db,
            mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
            profileManager: profileManager,
            reachabilityManager: reachabilityManager,
            storyStore: storyStore,
            threadStore: threadStore,
        )
        let taskRunner = DownloadTaskRunner(
            accountKeyStore: accountKeyStore,
            attachmentDownloadStore: attachmentDownloadStore,
            attachmentStore: attachmentStore,
            attachmentUpdater: attachmentUpdater,
            attachmentUploadStore: attachmentUploadStore,
            backupRequestManager: backupRequestManager,
            dateProvider: dateProvider,
            db: db,
            decrypter: decrypter,
            downloadQueue: downloadQueue,
            downloadabilityChecker: downloadabilityChecker,
            remoteConfigProvider: remoteConfigProvider,
            stickerManager: stickerManager,
            tsAccountManager: tsAccountManager,
        )
        self.queueLoader = TaskQueueLoader(
            maxConcurrentTasks: 12,
            dateProvider: dateProvider,
            db: db,
            runner: taskRunner,
        )
        self.remoteConfigProvider = remoteConfigProvider
        self.tsAccountManager = tsAccountManager

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            guard let self else { return }
            self.beginDownloadingIfNecessary()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(registrationStateDidChange),
                name: .registrationStateDidChange,
                object: nil,
            )
        }
    }

    @objc
    private func registrationStateDidChange() {
        AssertIsOnMainThread()
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else { return }
        self.beginDownloadingIfNecessary()
    }

    private func maxEncryptedBackupDownloadSize() -> UInt64 {
        return 1_000_000_000
    }

    public func downloadBackup(
        metadata: BackupReadCredential,
        progress: OWSProgressSink?,
    ) async throws -> URL {
        let uuid = UUID()
        let downloadState = DownloadState(type: .backup(metadata: metadata, uuid: uuid))
        return try await self.downloadQueue.enqueueDownload(
            downloadState: downloadState,
            maxDownloadSizeBytes: maxEncryptedBackupDownloadSize(),
            expectedDownloadSize: .useHeadRequest,
            progress: progress,
        )
    }

    public func backupCdnInfo(
        metadata: BackupReadCredential,
    ) async throws -> BackupCdnInfo {
        let uuid = UUID()
        let downloadState = DownloadState(type: .backup(metadata: metadata, uuid: uuid))
        var prefixLength = BackupNonce.metadataHeaderByteLengthUpperBound
        while true {
            let (cdnInfo, prefix) = try await self.downloadQueue.performPrefixRequest(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxEncryptedBackupDownloadSize(),
                length: prefixLength,
            )
            do throws(BackupNonce.MetadataHeader.ParsingError) {
                let metadataHeader = try BackupNonce.MetadataHeader.from(prefixBytes: prefix)
                return BackupCdnInfo(
                    fileInfo: cdnInfo,
                    metadataHeader: metadataHeader,
                )
            } catch {
                switch error {
                case .unrecognizedFileSignature:
                    throw OWSAssertionError("Unrecognized backup file signature")
                case .dataMissingOrEmpty:
                    throw OWSAssertionError("Missing backup file prefix data")
                case .headerTooLarge:
                    throw OWSAssertionError("Backup header too large")
                case .moreDataNeeded(let length):
                    if length <= prefixLength {
                        // We got fewer bytes than we requested
                        throw OWSAssertionError("Backup file too small!")
                    }
                    prefixLength = length
                }
            }
        }
    }

    public func downloadEncryptedTransientAttachment(
        downloadMetadata: DownloadMetadata,
        expectedDownloadSize: UInt64?,
        progress: OWSProgressSink?,
    ) async throws -> URL {
        // We want to avoid large downloads from a compromised or buggy service.
        let maxDownloadSize = self.remoteConfigProvider.currentConfig().attachmentMaxEncryptedReceiveBytes
        let downloadState = DownloadState(type: .transientAttachment(downloadMetadata, uuid: UUID()))
        return try await self.downloadQueue.enqueueDownload(
            downloadState: downloadState,
            maxDownloadSizeBytes: maxDownloadSize,
            expectedDownloadSize: expectedDownloadSize.map({ .estimatedSizeBytes($0) }) ?? .useHeadRequest,
            progress: progress,
        )
    }

    public func downloadTransientAttachment(
        downloadMetadata: DownloadMetadata,
        decryptionMetadata: DecryptionMetadata,
        expectedDownloadSize: UInt64?,
        progress: OWSProgressSink?,
    ) async throws -> URL {
        let encryptedFileUrl = try await downloadEncryptedTransientAttachment(
            downloadMetadata: downloadMetadata,
            expectedDownloadSize: expectedDownloadSize,
            progress: progress,
        )
        return try await self.decrypter.decryptTransientAttachment(
            encryptedFileUrl: encryptedFileUrl,
            metadata: decryptionMetadata,
        )
    }

    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    ) {
        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Downloading attachments for uninserted message!")
            return
        }

        var referencedAttachments = attachmentStore.fetchReferencedAttachmentsOwnedByMessage(
            messageRowId: messageRowId,
            tx: tx,
        )

        // Do not enqueue download of the thumbnail for quotes for which
        // we have the target message locally; the thumbnail will be filled in
        // IFF we download the original attachment.
        if
            let quotedMessage = message.quotedMessage,
            quotedMessage.bodySource == .local
        {
            referencedAttachments.removeAll {
                switch $0.reference.owner {
                case .message(.quotedReply): true
                default: false
                }
            }
        }

        enqueueDownloadOfReferencedAttachments(referencedAttachments, priority: priority, tx: tx)
    }

    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    ) {
        guard let storyMessageRowId = message.id else {
            owsFailDebug("Downloading attachments for uninserted message!")
            return
        }
        let referencedAttachments = attachmentStore.fetchReferencedAttachmentsOwnedByStory(
            storyMessageRowId: storyMessageRowId,
            tx: tx,
        )
        enqueueDownloadOfReferencedAttachments(referencedAttachments, priority: priority, tx: tx)
    }

    public func downloadReferencedAttachment(
        referencedAttachment: ReferencedAttachment,
        priority: AttachmentDownloadPriority,
        progress: OWSProgressSink?,
    ) async throws {
        if CurrentAppContext().isRunningTests {
            // No need to enqueue downloads if we're running tests.
            return
        }

        let source = try await db.awaitableWrite { tx in
            try _enqueueDownloadOfReferencedAttachment(
                referencedAttachment: referencedAttachment,
                priority: priority,
                tx: tx,
            )
        }

        try await _waitForDownloadOfAttachment(
            id: referencedAttachment.attachment.id,
            source: source,
            progress: progress,
        )
    }

    public func enqueueDownloadOfReferencedAttachment(
        referencedAttachment: ReferencedAttachment,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    ) throws(AttachmentDownloads.Error) {
        _ = try _enqueueDownloadOfReferencedAttachment(
            referencedAttachment: referencedAttachment,
            priority: priority,
            tx: tx,
        )
    }

    private func _enqueueDownloadOfReferencedAttachment(
        referencedAttachment: ReferencedAttachment,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    ) throws(AttachmentDownloads.Error) -> QueuedAttachmentDownloadRecord.SourceType {
        let backupPlan = backupSettingsStore.backupPlan(tx: tx)
        let isEligibleToDownloadFromMediaTier: Bool
        switch backupPlan {
        case .disabled, .disabling:
            isEligibleToDownloadFromMediaTier = false
        case .free:
            // We still might attempt media tier downloads
            // while currently free tier.
            isEligibleToDownloadFromMediaTier = true
        case .paid, .paidExpiringSoon, .paidAsTester:
            isEligibleToDownloadFromMediaTier = true
        }

        let sourceToUse: QueuedAttachmentDownloadRecord.SourceType = {
            // We only download from the latest transit tier info.
            let transitTierInfo = referencedAttachment.attachment.latestTransitTierInfo
            let mediaTierInfo = referencedAttachment.attachment.mediaTierInfo
            guard
                let transitTierInfo,
                let mediaTierInfo
            else {
                // If we don't have both there's nothing to decide
                return mediaTierInfo == nil ? .transitTier : .mediaTierFullsize
            }
            if
                isEligibleToDownloadFromMediaTier,
                mediaTierInfo.lastDownloadAttemptTimestamp == nil
            {
                // If we've never tried media tier, always try that first.
                return .mediaTierFullsize
            } else
            if transitTierInfo.lastDownloadAttemptTimestamp == nil {
                // If we tried media tier and failed, try transit tier
                // next time.
                return .transitTier
            } else {
                // If both have failed fall back to default.
                return isEligibleToDownloadFromMediaTier
                    ? .mediaTierFullsize
                    : .transitTier
            }
        }()

        let downloadability = downloadabilityChecker.downloadability(
            of: referencedAttachment.reference,
            priority: priority,
            source: sourceToUse,
            mimeType: referencedAttachment.attachment.mimeType,
            tx: tx,
        )
        do throws(AttachmentDownloads.Error) {
            switch downloadability {
            case .downloadable:
                attachmentDownloadStore.enqueueDownloadOfAttachment(
                    withId: referencedAttachment.reference.attachmentRowId,
                    source: sourceToUse,
                    priority: priority,
                    tx: tx,
                )
                return sourceToUse
            case .blockedByActiveCall:
                throw .blockedByActiveCall
            case .blockedByPendingMessageRequest:
                throw .blockedByPendingMessageRequest
            case .blockedByAutoDownloadSettings:
                throw .blockedByAutoDownloadSettings
            case .blockedByNetworkState:
                throw .blockedByNetworkState
            }
        } catch {
            NotificationCenter.default.postOnMainThread(
                name: AttachmentDownloads.attachmentDownloadStoppedNotification,
                object: nil,
                userInfo: [
                    AttachmentDownloads.attachmentDownloadAttachmentIDKey: referencedAttachment.reference.attachmentRowId,
                ],
            )
            throw error
        }
    }

    private func enqueueDownloadOfReferencedAttachments(
        _ referencedAttachments: [ReferencedAttachment],
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    ) {
        var didEnqueueAnyDownloads = false
        referencedAttachments.forEach { referencedAttachment in
            do throws(AttachmentDownloads.Error) {
                try enqueueDownloadOfReferencedAttachment(
                    referencedAttachment: referencedAttachment,
                    priority: priority,
                    tx: tx,
                )
                didEnqueueAnyDownloads = true
            } catch {
                switch error {
                case .blockedByActiveCall:
                    Logger.info("Skipping enqueue of download during active call")
                case .blockedByPendingMessageRequest:
                    Logger.info("Skipping enqueue of download due to pending message request")
                case .blockedByAutoDownloadSettings:
                    Logger.info("Skipping enqueue of download due to auto download settings")
                case .blockedByNetworkState:
                    Logger.info("Skipping enqueue of download due to network state")
                case .expiredCredentials:
                    Logger.info("Skipping enqueue of download due to unexpected error")
                }
            }
        }
        if didEnqueueAnyDownloads {
            tx.addSyncCompletion { [weak self] in
                self?.db.asyncWrite { tx in
                    referencedAttachments.forEach { referencedAttachment in
                        self?.attachmentUpdater.touchOwner(referencedAttachment.reference.owner, tx: tx)
                    }
                }
                self?.beginDownloadingIfNecessary()
            }
        }
    }

    public func enqueueCopyOfLocalAttachment(
        id: Attachment.IDType,
        tx: DBWriteTransaction,
    ) {
        if CurrentAppContext().isRunningTests {
            // No need to enqueue downloads if we're running tests.
            return
        }

        attachmentDownloadStore.enqueueDownloadOfAttachment(
            withId: id,
            source: .transitTier,
            priority: .localClone,
            tx: tx,
        )
        tx.addSyncCompletion { [weak self] in
            self?.beginDownloadingIfNecessary()
        }
    }

    public func downloadAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
        progress: OWSProgressSink?,
    ) async throws {
        if CurrentAppContext().isRunningTests {
            // No need to enqueue downloads if we're running tests.
            return
        }

        await db.awaitableWrite { tx in
            self.attachmentDownloadStore.enqueueDownloadOfAttachment(
                withId: id,
                source: source,
                priority: priority,
                tx: tx,
            )
        }

        try await _waitForDownloadOfAttachment(id: id, source: source, progress: progress)
    }

    private func _waitForDownloadOfAttachment(
        id: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        progress: OWSProgressSink?,
    ) async throws {

        let downloadKey = DownloadQueue.DownloadKey(id: id, source: source)
        await downloadQueue.clearOldDownloadsAndIncrementProgressID(key: downloadKey)

        let downloadWaitingTask = Task {
            try await self.downloadQueue.waitForDownloadOfAttachment(
                id: id,
                source: source,
                progress: progress,
            )
        }

        do {
            self.beginDownloadingIfNecessary()
            try await downloadWaitingTask.value
        } catch {
            Logger.error("Error downloading attachment id \(id) from \(source): \(error)")
            await downloadQueue.clearDownloadProgressAndMarkFinished(key: downloadKey)
            throw error
        }

        await downloadQueue.clearDownloadProgressAndMarkFinished(key: downloadKey)
    }

    public func beginDownloadingIfNecessary() {
        guard CurrentAppContext().isMainApp else {
            return
        }
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else {
            return
        }

        Task { [weak self] in
            try await self?.queueLoader.loadAndRunTasks()
        }
    }

    public func cancelDownload(for attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        progressStates.markDownloadCancelled(for: attachmentId)
        QueuedAttachmentDownloadRecord.SourceType.allCases.forEach { source in
            attachmentDownloadStore.removeAttachmentFromQueue(
                withId: attachmentId,
                source: source,
                tx: tx,
            )
        }
        self.attachmentUpdater.touchAllOwners(
            attachmentId: attachmentId,
            tx: tx,
        )
    }

    // MARK: - Persisted Queue

    private struct DownloadTaskRecord: TaskRecord {
        let id: Int64
        let record: QueuedAttachmentDownloadRecord
    }

    private class DownloadTaskRecordStore: TaskRecordStore {
        typealias Record = DownloadTaskRecord

        private let store: AttachmentDownloadStore

        init(store: AttachmentDownloadStore) {
            self.store = store
        }

        func peek(count: UInt, tx: DBReadTransaction) -> [DownloadTaskRecord] {
            return store.peek(count: count, tx: tx).map {
                return .init(id: $0.id!, record: $0)
            }
        }

        func removeRecord(_ record: DownloadTaskRecord, tx: DBWriteTransaction) {
            store.removeAttachmentFromQueue(
                withId: record.record.attachmentId,
                source: record.record.sourceType,
                tx: tx,
            )
        }
    }

    private final class DownloadTaskRunner: TaskRecordRunner {
        typealias Store = DownloadTaskRecordStore

        private let accountKeyStore: AccountKeyStore
        private let attachmentDownloadStore: AttachmentDownloadStore
        private let attachmentStore: AttachmentStore
        private let attachmentUpdater: AttachmentUpdater
        private let attachmentUploadStore: AttachmentUploadStore
        private let backupRequestManager: BackupRequestManager
        private let dateProvider: DateProvider
        private let db: any DB
        private let decrypter: Decrypter
        private let downloadabilityChecker: DownloadabilityChecker
        private let downloadQueue: DownloadQueue
        private let remoteConfigProvider: any RemoteConfigProvider
        private let stickerManager: Shims.StickerManager
        let store: Store
        private let tsAccountManager: TSAccountManager

        init(
            accountKeyStore: AccountKeyStore,
            attachmentDownloadStore: AttachmentDownloadStore,
            attachmentStore: AttachmentStore,
            attachmentUpdater: AttachmentUpdater,
            attachmentUploadStore: AttachmentUploadStore,
            backupRequestManager: BackupRequestManager,
            dateProvider: @escaping DateProvider,
            db: any DB,
            decrypter: Decrypter,
            downloadQueue: DownloadQueue,
            downloadabilityChecker: DownloadabilityChecker,
            remoteConfigProvider: any RemoteConfigProvider,
            stickerManager: Shims.StickerManager,
            tsAccountManager: TSAccountManager,
        ) {
            self.accountKeyStore = accountKeyStore
            self.attachmentDownloadStore = attachmentDownloadStore
            self.attachmentStore = attachmentStore
            self.attachmentUpdater = attachmentUpdater
            self.attachmentUploadStore = attachmentUploadStore
            self.backupRequestManager = backupRequestManager
            self.dateProvider = dateProvider
            self.db = db
            self.decrypter = decrypter
            self.downloadQueue = downloadQueue
            self.downloadabilityChecker = downloadabilityChecker
            self.remoteConfigProvider = remoteConfigProvider
            self.stickerManager = stickerManager
            self.store = DownloadTaskRecordStore(store: attachmentDownloadStore)
            self.tsAccountManager = tsAccountManager
        }

        // MARK: TaskRecordRunner conformance

        func runTask(
            record: DownloadTaskRecord,
            loader: TaskQueueLoader<DownloadTaskRunner>,
        ) async -> TaskRecordResult {
            Logger.info("Starting download of attachment \(record.record.attachmentId) from \(record.record.sourceType)")
            return await self.downloadRecord(record.record)
        }

        func didSucceed(
            record: DownloadTaskRecord,
            tx: DBWriteTransaction,
        ) throws {
            Logger.info("Succeeded download of attachment \(record.record.attachmentId) from \(record.record.sourceType)")
            let downloadKey = DownloadQueue.downloadKey(record: record.record)
            Task {
                await downloadQueue.updateObservers(downloadKey: downloadKey, error: nil)
            }
        }

        func didObsolete(
            record: DownloadTaskRecord,
            tx: DBWriteTransaction,
        ) throws {
            Logger.info("Obsoleted download of attachment \(record.record.attachmentId) from \(record.record.sourceType)")
            let downloadKey = DownloadQueue.downloadKey(record: record.record)
            Task {
                await downloadQueue.updateObservers(downloadKey: downloadKey, error: nil)
            }
        }

        func didFail(record: DownloadTaskRecord, error: Error, isRetryable: Bool, tx: DBWriteTransaction) {
            let record = record.record
            Logger.warn("Failed download of attachment \(record.attachmentId) from \(record.sourceType). \(error)")
            if isRetryable, let retryTime = self.retryTime(for: record) {
                // Don't update observers; they'll be updated when the retry succeeds.
                attachmentDownloadStore.markQueuedDownloadFailed(
                    withId: record.id!,
                    minRetryTimestamp: retryTime,
                    tx: tx,
                )
            } else {
                let attachment = attachmentStore.fetch(id: record.attachmentId, tx: tx)

                let wasCancelled = if case URLError.cancelled = error { true } else { false }

                // If we tried to download as media tier, and failed, and we have
                // a transit tier fallback available, try downloading from that.
                let shouldReEnqueueAsTransitTier =
                    !wasCancelled
                        && record.sourceType == .mediaTierFullsize
                        && attachment?.latestTransitTierInfo != nil
                        // Backup restore download queue does its own fallbacks
                        && record.priority != .backupRestore

                // Not retrying; just delete the enqueued download
                attachmentDownloadStore.removeAttachmentFromQueue(
                    withId: record.attachmentId,
                    source: record.sourceType,
                    tx: tx,
                )
                if
                    let error = error as? TransitTierExpiredError,
                    let attachment = attachmentStore.fetch(id: record.attachmentId, tx: tx)
                {
                    Logger.info("Expiring transit tier due to failed download")
                    attachmentStore.removeTransitTierInfo(
                        error.transitTierInfo,
                        attachment: attachment,
                        tx: tx,
                    )
                } else if
                    record.priority != .backupRestore,
                    let attachment = attachmentStore.fetch(id: record.attachmentId, tx: tx)
                {
                    // Backup restore download queue does its own marking of failed state.
                    attachmentStore.updateAttachmentAsFailedToDownload(
                        attachment: attachment,
                        sourceType: record.sourceType,
                        timestamp: self.dateProvider().ows_millisecondsSince1970,
                        tx: tx,
                    )
                }

                if shouldReEnqueueAsTransitTier {
                    attachmentDownloadStore.enqueueDownloadOfAttachment(
                        withId: record.attachmentId,
                        source: .transitTier,
                        priority: record.priority,
                        tx: tx,
                    )
                } else {
                    // If we aren't re-enqueuing, tell observers its failed.
                    let downloadKey = DownloadQueue.downloadKey(record: record)
                    Task {
                        await downloadQueue.updateObservers(downloadKey: downloadKey, error: error)
                    }
                }

                tx.addSyncCompletion { [weak self] in
                    guard let self else { return }
                    self.db.asyncWrite { tx in
                        self.attachmentUpdater.touchAllOwners(
                            attachmentId: record.attachmentId,
                            tx: tx,
                        )
                    }
                }
            }
        }

        private struct TransitTierExpiredError: Error {
            let transitTierInfo: Attachment.TransitTierInfo
        }

        private func wrapDownloadError(
            error: Error,
            record: QueuedAttachmentDownloadRecord,
            attachmentBeforeDownloadAttempt: Attachment,
        ) -> TaskRecordResult {

            if case URLError.cancelled = error {
                return .unretryableError(error)
            }

            // Check if we should mark the transit tier download as
            // "expired" (meaning we wipe the transit tier info).
            let now = dateProvider().ows_millisecondsSince1970
            if
                // We only expire if we get a 404 from the server
                error.httpStatusCode == 404,

                // We only expire transit tier downloads
                record.sourceType == .transitTier,

                // Check that the transit tier info hasn't changed (cdn key downloads unlikely)
                let refetchedAttachment = db.read(
                    block: { attachmentStore.fetch(id: record.attachmentId, tx: $0) },
                ),
                let transitTierInfoBeforeDownloadAttempt = attachmentBeforeDownloadAttempt.latestTransitTierInfo,
                refetchedAttachment.latestTransitTierInfo?.cdnKey
                == transitTierInfoBeforeDownloadAttempt.cdnKey,

                // Only proactively expire if the upload is old enough
                let uploadTimestamp = refetchedAttachment.latestTransitTierInfo?.uploadTimestamp,
                uploadTimestamp < now,
                now - uploadTimestamp >= remoteConfigProvider.currentConfig().messageQueueTimeMs
            {
                return .unretryableError(TransitTierExpiredError(transitTierInfo: transitTierInfoBeforeDownloadAttempt))
            }

            // We retry all other network-level errors (with an exponential backoff).
            // Even if we get e.g. a 404, the file may not be available _yet_
            // but might be in the future (exception below)
            // The other type of error that can be expected here is if CDN
            // credentials expire between enqueueing the download and the download
            // excuting. The outcome is the same: fail the current download and retry.
            return .retryableError(error)
        }

        /// Returns nil if should not be retried.
        /// Note these are not network-level retries; those happen separately.
        /// These are persisted retries, usually for longer running retry attempts.
        private nonisolated func retryTime(for record: QueuedAttachmentDownloadRecord) -> UInt64? {
            switch record.sourceType {
            case .transitTier:
                // We don't do persistent retries fromt the transit tier.
                return nil
            case .mediaTierFullsize, .mediaTierThumbnail:
                // User initiated downloads aren't retried,
                // and backups-initiated downloads get retried
                // at the backup manager level.
                return nil
            }
        }

        // MARK: Downloading

        private nonisolated func downloadRecord(
            _ record: QueuedAttachmentDownloadRecord,
        ) async -> TaskRecordResult {
            guard
                let attachment = db.read(block: { tx in
                    attachmentStore.fetch(id: record.attachmentId, tx: tx)
                })
            else {
                // Because of the foreign key relationship and cascading deletes, this should
                // only happen if the attachment got deleted between when we fetched the
                // download queue record and now. Regardless, the record should now be deleted.
                owsFailDebug("Attempting to download an attachment that doesn't exist!")
                return .obsolete
            }

            guard attachment.asStream() == nil else {
                // Already a stream! No need to download.
                return .obsolete
            }

            switch self.downloadabilityChecker.downloadability(record, attachment: attachment) {
            case .downloadable:
                break
            case nil:
                // Because of the foreign key relationship and cascading deletes, this should
                // only happen if all the references got deleted between when we fetched the
                // download queue record and now. Regardless, the record should now be deleted.
                owsFailDebug("Attempting to download an attachment with no references \(record.attachmentId)")
                return .obsolete
            case .blockedByActiveCall:
                // This is a temporary setback; retry in a bit if the source allows it.
                Logger.info("Skipping attachment download due to active call \(record.attachmentId)")
                return .retryableError(AttachmentDownloads.Error.blockedByActiveCall)
            case .blockedByPendingMessageRequest:
                Logger.info("Skipping attachment download due to pending message request \(record.attachmentId)")
                // These can only be resolved by user action; cancel the enqueued download.
                return .unretryableError(AttachmentDownloads.Error.blockedByPendingMessageRequest)
            case .blockedByAutoDownloadSettings:
                Logger.info("Skipping attachment download due to auto download settings \(record.attachmentId)")
                // These can only be resolved by user action; cancel the enqueued download.
                return .unretryableError(AttachmentDownloads.Error.blockedByAutoDownloadSettings)
            case .blockedByNetworkState:
                Logger.info("Skipping attachment download due to network state \(record.attachmentId)")
                return .unretryableError(AttachmentDownloads.Error.blockedByNetworkState)
            }

            Logger.info("Downloading attachment \(record.attachmentId) from \(record.sourceType)")

            if
                let originalAttachmentIdForQuotedReply = attachment.originalAttachmentIdForQuotedReply,
                await quoteUnquoteDownloadQuotedReplyFromOriginalStream(
                    originalAttachmentIdForQuotedReply: originalAttachmentIdForQuotedReply,
                    record: record,
                )
            {
                // Done!
                Logger.info("Sourced quote attachment from original \(record.attachmentId)")
                return .success
            }

            if await quoteUnquoteDownloadStickerFromInstalledPackIfPossible(record: record) {
                // Done!
                Logger.info("Sourced sticker attachment from installed sticker \(record.attachmentId)")
                return .success
            }

            if record.priority == .localClone {
                // Local clone happens in two ways:
                // 1. Original's local stream for a quoted reply
                // 2. Local installed sticker for a sticker message
                // If we were trying for either of these and got this far,
                // we failed to use the local data, so just fail the whole thing.
                return .unretryableError(OWSAssertionError("Failed local clone"))
            }

            let downloadMetadata: DownloadMetadata
            let downloadSizeSource: DownloadQueue.DownloadSizeSource
            let maxDownloadSizeBytes: UInt64
            let validationMetadata: Decrypter.ValidationMetadata
            switch record.sourceType {
            case .transitTier:
                // We only download from the latest transit tier info.
                guard let transitTierInfo = attachment.latestTransitTierInfo else {
                    return .unretryableError(OWSAssertionError("Attempting to download an attachment without cdn info"))
                }
                guard let attachmentKey = try? AttachmentKey(combinedKey: transitTierInfo.encryptionKey) else {
                    return .unretryableError(OWSAssertionError("can't download file with malformed attachment key"))
                }
                downloadMetadata = DownloadMetadata(
                    cdnNumber: transitTierInfo.cdnNumber,
                    source: .transitTier(cdnKey: transitTierInfo.cdnKey),
                )
                validationMetadata = .transitTier(
                    mimeType: attachment.mimeType,
                    attachmentKey: attachmentKey,
                    plaintextLength: transitTierInfo.unencryptedByteCount,
                    integrityCheck: transitTierInfo.integrityCheck,
                )
                downloadSizeSource = .estimatedSizeBytes(Cryptography.estimatedTransitTierCDNSize(
                    unencryptedSize: UInt64(safeCast: transitTierInfo.unencryptedByteCount),
                ) ?? { owsFail("can always produce estimate for 32-bit byte count") }())
                let attachmentLimits = IncomingAttachmentLimits.currentLimits(remoteConfig: remoteConfigProvider.currentConfig())
                switch attachment.contentType {
                case .image:
                    maxDownloadSizeBytes = attachmentLimits.maxEncryptedImageBytes
                case .audio, .video, .file:
                    maxDownloadSizeBytes = attachmentLimits.maxEncryptedBytes
                }
            case .mediaTierFullsize:
                let cdnNumber = attachment.mediaTierInfo?.cdnNumber ?? remoteConfigProvider.currentConfig().mediaTierFallbackCdnNumber
                guard
                    let mediaTierInfo = attachment.mediaTierInfo,
                    let mediaName = attachment.mediaName,
                    let backupKey = db.read(block: { accountKeyStore.getMediaRootBackupKey(tx: $0) }),
                    let outerEncryptionMetadata = buildCdnEncryptionMetadata(mediaName: mediaName, backupKey: backupKey, type: .outerLayerFullsizeOrThumbnail),
                    let cdnCredential = await fetchBackupCdnReadCredential(
                        for: cdnNumber,
                        backupKey: backupKey,
                        logger: PrefixedLogger(prefix: "[Backups]"),
                    )
                else {
                    return .unretryableError(OWSAssertionError("Attempting to download an attachment without cdn info"))
                }
                guard let outerAttachmentKey = try? outerEncryptionMetadata.attachmentKey() else {
                    return .unretryableError(OWSAssertionError("can't download media file with malformed media key"))
                }
                guard let attachmentKey = try? AttachmentKey(combinedKey: attachment.encryptionKey) else {
                    return .unretryableError(OWSAssertionError("can't download media file with malformed attachment key"))
                }
                downloadMetadata = .init(
                    cdnNumber: cdnNumber,
                    source: .mediaTier(
                        type: .fullsize,
                        cdnReadCredential: cdnCredential,
                        mediaId: outerEncryptionMetadata.mediaId,
                    ),
                )
                validationMetadata = .mediaTier(
                    mimeType: attachment.mimeType,
                    outerAttachmentKey: outerAttachmentKey,
                    innerDecryptionMetadata: DecryptionMetadata(
                        key: attachmentKey,
                        integrityCheck: .plaintextHash(mediaTierInfo.plaintextHash),
                        plaintextLength: UInt64(safeCast: mediaTierInfo.unencryptedByteCount),
                    ),
                    localAttachmentKey: attachmentKey,
                )
                downloadSizeSource = .estimatedSizeBytes(Cryptography.estimatedMediaTierCDNSize(
                    unencryptedSize: UInt64(safeCast: mediaTierInfo.unencryptedByteCount),
                ) ?? { owsFail("can always produce estimate for 32-bit byte count") }())
                maxDownloadSizeBytes = remoteConfigProvider.currentConfig().attachmentMaxEncryptedReceiveBytes
            case .mediaTierThumbnail:
                let cdnNumber = attachment.thumbnailMediaTierInfo?.cdnNumber ?? remoteConfigProvider.currentConfig().mediaTierFallbackCdnNumber
                guard
                    attachment.thumbnailMediaTierInfo != nil || MimeTypeUtil.isSupportedVisualMediaMimeType(attachment.mimeType),
                    let mediaName = attachment.mediaName,
                    let backupKey = db.read(block: { accountKeyStore.getMediaRootBackupKey(tx: $0) }),
                    // This is the outer encryption
                    let outerEncryptionMetadata = buildCdnEncryptionMetadata(
                        mediaName: AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName),
                        backupKey: backupKey,
                        type: .outerLayerFullsizeOrThumbnail,
                    ),
                    // inner encryption
                    let innerEncryptionMetadata = buildCdnEncryptionMetadata(
                        mediaName: AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName),
                        backupKey: backupKey,
                        type: .transitTierThumbnail,
                    ),
                    let cdnReadCredential = await fetchBackupCdnReadCredential(
                        for: cdnNumber,
                        backupKey: backupKey,
                        logger: PrefixedLogger(prefix: "[Backups]"),
                    )
                else {
                    return .unretryableError(OWSAssertionError("Attempting to download an attachment without cdn info"))
                }
                guard let outerAttachmentKey = try? outerEncryptionMetadata.attachmentKey() else {
                    return .unretryableError(OWSAssertionError("can't download thumbnail with malformed outer media key"))
                }
                guard let innerAttachmentKey = try? innerEncryptionMetadata.attachmentKey() else {
                    return .unretryableError(OWSAssertionError("can't download thumbnail with malformed inner media key"))
                }
                guard let attachmentKey = try? AttachmentKey(combinedKey: attachment.encryptionKey) else {
                    return .unretryableError(OWSAssertionError("can't download thumbnail with malformed attachment key"))
                }

                downloadMetadata = .init(
                    cdnNumber: cdnNumber,
                    source: .mediaTier(
                        type: .thumbnail,
                        cdnReadCredential: cdnReadCredential,
                        mediaId: outerEncryptionMetadata.mediaId,
                    ),
                )
                validationMetadata = .mediaTier(
                    mimeType: MimeTypeUtil.thumbnailMimetype(fullsizeMimeType: attachment.mimeType, quality: .backupThumbnail),
                    outerAttachmentKey: outerAttachmentKey,
                    innerDecryptionMetadata: DecryptionMetadata(key: innerAttachmentKey),
                    localAttachmentKey: attachmentKey,
                )
                // We don't know thumbnail sizes and don't want to issue a
                // request for each one to check. Just estimate as the max size.
                downloadSizeSource = .estimatedSizeBytes(Cryptography.estimatedMediaTierCDNSize(
                    unencryptedSize: UInt64(safeCast: AttachmentThumbnailQuality.backupThumbnailMaxSizeBytes),
                ) ?? { owsFail("can always produce estimate for 32-bit byte count") }())
                maxDownloadSizeBytes = remoteConfigProvider.currentConfig().attachmentMaxEncryptedReceiveBytes
            }

            let downloadedFileUrl: URL
            do {
                downloadedFileUrl = try await downloadQueue.enqueueDownload(
                    downloadState: .init(type: .attachment(downloadMetadata, id: attachment.id)),
                    maxDownloadSizeBytes: maxDownloadSizeBytes,
                    expectedDownloadSize: downloadSizeSource,
                    progress: nil,
                )
            } catch let error {
                Logger.error("Failed to download: \(error)")
                return wrapDownloadError(
                    error: error,
                    record: record,
                    attachmentBeforeDownloadAttempt: attachment,
                )
            }

            let pendingAttachment: PendingAttachment
            do {
                pendingAttachment = try await decrypter.validateAndPrepare(
                    encryptedFileUrl: downloadedFileUrl,
                    validationMetadata: validationMetadata,
                )
            } catch let error {
                return .unretryableError(OWSAssertionError("Failed to validate: \(error)"))
            }

            let result: DownloadResult
            do {
                result = try await attachmentUpdater.updateAttachmentAsDownloaded(
                    attachmentId: attachment.id,
                    pendingAttachment: pendingAttachment,
                    source: record.sourceType,
                    priority: record.priority,
                    timestamp: dateProvider().ows_millisecondsSince1970,
                )
            } catch let error {
                return .unretryableError(OWSAssertionError("Failed to update attachment: \(error)"))
            }

            if case .stream(let attachmentStream) = result {
                do {
                    try await attachmentUpdater.copyThumbnailForQuotedReplyIfNeeded(
                        attachmentStream,
                    )
                } catch let error {
                    // Log error but don't block finishing; the thumbnails
                    // can update themselves later.
                    Logger.error("Failed to update thumbnails: \(error)")
                }
            }

            return .success
        }

        private nonisolated func quoteUnquoteDownloadQuotedReplyFromOriginalStream(
            originalAttachmentIdForQuotedReply: Attachment.IDType,
            record: QueuedAttachmentDownloadRecord,
        ) async -> Bool {
            let originalAttachmentStream = db.read { tx in
                attachmentStore.fetch(id: originalAttachmentIdForQuotedReply, tx: tx)?.asStream()
            }
            guard let originalAttachmentStream else {
                return false
            }
            do {
                try await attachmentUpdater.copyThumbnailForQuotedReplyIfNeeded(
                    originalAttachmentStream,
                )
                return true
            } catch let error {
                Logger.error("Failed to update thumbnails: \(error)")
                return false
            }
        }

        private nonisolated func quoteUnquoteDownloadStickerFromInstalledPackIfPossible(
            record: QueuedAttachmentDownloadRecord,
        ) async -> Bool {
            let installedSticker: InstalledStickerRecord? = db.read { tx in
                var stickerMetadata: AttachmentReference.Owner.MessageSource.StickerMetadata?
                attachmentStore.enumerateAllReferences(
                    toAttachmentId: record.attachmentId,
                    tx: tx,
                    block: { reference, stop in
                        switch reference.owner {
                        case .message(.sticker(let metadata)):
                            stop = true
                            stickerMetadata = metadata
                        default:
                            break
                        }
                    },
                )
                guard let stickerMetadata else {
                    return nil
                }
                return self.stickerManager.fetchInstalledSticker(
                    packId: stickerMetadata.stickerPackId,
                    stickerId: stickerMetadata.stickerId,
                    tx: tx,
                )
            }

            guard let installedSticker else {
                return false
            }

            // Pretend that is the file we've downloaded.
            let pendingAttachment: PendingAttachment
            do {
                pendingAttachment = try await decrypter.validateAndPrepareInstalledSticker(installedSticker)
            } catch let error {
                Logger.error("Failed to validate sticker: \(error)")
                return false
            }

            let attachmentStream: AttachmentStream
            do {
                attachmentStream = try await attachmentUpdater.updateAttachmentFromInstalledSticker(
                    attachmentId: record.attachmentId,
                    pendingAttachment: pendingAttachment,
                )
            } catch let error {
                Logger.error("Failed to update attachment: \(error)")
                return false
            }

            do {
                try await attachmentUpdater.copyThumbnailForQuotedReplyIfNeeded(
                    attachmentStream,
                )
            } catch let error {
                // Log error but don't block finishing; the thumbnails
                // can update themselves later.
                Logger.error("Failed to update thumbnails: \(error)")
            }

            return true
        }

        private func buildCdnEncryptionMetadata(
            mediaName: String,
            backupKey: MediaRootBackupKey,
            type: MediaTierEncryptionType,
        ) -> MediaTierEncryptionMetadata? {
            do {
                return try backupKey.mediaEncryptionMetadata(
                    mediaName: mediaName,
                    type: type,
                )
            } catch {
                owsFailDebug("Failed to build backup media metadata")
                return nil
            }
        }

        private func fetchBackupCdnReadCredential(
            for cdn: UInt32,
            backupKey: MediaRootBackupKey,
            logger: PrefixedLogger,
        ) async -> MediaTierReadCredential? {
            guard
                let localAci = db.read(block: { tx in
                    self.tsAccountManager.localIdentifiers(tx: tx)?.aci
                })
            else {
                owsFailDebug("Missing local identifier")
                return nil
            }

            guard
                let auth = try? await backupRequestManager.fetchBackupServiceAuth(
                    for: backupKey,
                    localAci: localAci,
                    auth: .implicit(),
                    logger: logger,
                )
            else {
                owsFailDebug("Failed to fetch backup credential")
                return nil
            }

            guard
                let metadata = try? await backupRequestManager.fetchMediaTierCdnRequestMetadata(
                    cdn: Int32(cdn),
                    auth: auth,
                    logger: logger,
                )
            else {
                owsFailDebug("Failed to fetch backup credential")
                return nil
            }

            return metadata
        }
    }

    // MARK: - Downloadability

    private class DownloadabilityChecker {

        private let attachmentStore: AttachmentStore
        private let backupSettingsStore: BackupSettingsStore
        private let currentCallProvider: CurrentCallProvider
        private let db: any DB
        private let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
        private let profileManager: ProfileManager
        private let reachabilityManager: SSKReachabilityManager
        private let storyStore: any StoryStore
        private let threadStore: ThreadStore

        init(
            attachmentStore: AttachmentStore,
            backupSettingsStore: BackupSettingsStore,
            currentCallProvider: CurrentCallProvider,
            db: any DB,
            mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
            profileManager: ProfileManager,
            reachabilityManager: SSKReachabilityManager,
            storyStore: any StoryStore,
            threadStore: ThreadStore,
        ) {
            self.attachmentStore = attachmentStore
            self.backupSettingsStore = backupSettingsStore
            self.currentCallProvider = currentCallProvider
            self.db = db
            self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
            self.profileManager = profileManager
            self.reachabilityManager = reachabilityManager
            self.storyStore = storyStore
            self.threadStore = threadStore
        }

        enum Downloadability {
            case downloadable
            case blockedByActiveCall
            case blockedByPendingMessageRequest
            case blockedByAutoDownloadSettings
            case blockedByNetworkState
        }

        func downloadability(
            _ record: QueuedAttachmentDownloadRecord,
            attachment: Attachment,
        ) -> Downloadability? {
            // Check priority before opening a read.
            switch record.priority {
            case .userInitiated, .localClone:
                // Always download at these priorities.
                return .downloadable
            case .default, .backupRestore:
                break
            }
            return db.read { tx in
                var downloadability: Downloadability?
                self.attachmentStore.enumerateAllReferences(
                    toAttachmentId: record.attachmentId,
                    tx: tx,
                ) { reference, stop in
                    downloadability = self.downloadability(
                        of: reference,
                        priority: record.priority,
                        source: record.sourceType,
                        mimeType: attachment.mimeType,
                        tx: tx,
                    )
                    // If one reference marks it downloadable, don't check further ones.
                    if downloadability == .downloadable {
                        stop = true
                    }
                }
                return downloadability
            }
        }

        func downloadability(
            of reference: AttachmentReference,
            priority: AttachmentDownloadPriority,
            source: QueuedAttachmentDownloadRecord.SourceType,
            mimeType: String,
            tx: DBReadTransaction,
        ) -> Downloadability {

            let blockedByCall = self.isDownloadBlockedByActiveCall(
                priority: priority,
                owner: reference.owner,
                tx: tx,
            )
            if blockedByCall {
                return .blockedByActiveCall
            }

            switch source {
            case .transitTier:
                // Transit tier can download regardless of reachability
                break
            case .mediaTierFullsize, .mediaTierThumbnail:
                if
                    !backupSettingsStore.shouldAllowBackupDownloadsOnCellular(tx: tx),
                    priority == .backupRestore,
                    !reachabilityManager.isReachable(via: .wifi)
                {
                    return .blockedByNetworkState
                }
            }

            let blockedByAutoDownloadSettings = self.isDownloadBlockedByAutoDownloadSettings(
                priority: priority,
                owner: reference.owner,
                renderingFlag: reference.renderingFlag,
                mimeType: mimeType,
                tx: tx,
            )
            if blockedByAutoDownloadSettings {
                return .blockedByAutoDownloadSettings
            }

            let blockedByPendingMessageRequest = self.isDownloadBlockedByPendingMessageRequest(
                priority: priority,
                source: source,
                owner: reference.owner,
                tx: tx,
            )
            if blockedByPendingMessageRequest {
                return .blockedByPendingMessageRequest
            }

            // If we made it this far, its downloadable.
            return .downloadable
        }

        private func isDownloadBlockedByActiveCall(
            priority: AttachmentDownloadPriority,
            owner: AttachmentReference.Owner,
            tx: DBReadTransaction,
        ) -> Bool {
            switch priority {
            case .userInitiated, .localClone:
                // Always download at these priorities.
                return false
            case .backupRestore:
                // Don't suspend during a call until we have mechanisms
                // to resume once the call ends.
                // TODO: [Backups] suspend downloads during calls and resume after
                return false
            case .default:
                break
            }

            switch owner {
            case .message(.bodyAttachment), .storyMessage(.media), .thread(.threadWallpaperImage), .thread(.globalThreadWallpaperImage):
                break
            case .message(.oversizeText):
                return false
            case .message(.sticker):
                break
            case .message(.quotedReply), .message(.linkPreview), .storyMessage(.textStoryLinkPreview), .message(.contactAvatar):
                return false
            }

            return currentCallProvider.hasCurrentCall
        }

        private func isDownloadBlockedByPendingMessageRequest(
            priority: AttachmentDownloadPriority,
            source: QueuedAttachmentDownloadRecord.SourceType,
            owner: AttachmentReference.Owner,
            tx: DBReadTransaction,
        ) -> Bool {
            switch priority {
            case .userInitiated, .localClone:
                // Always download at these priorities.
                return false
            case .default, .backupRestore:
                break
            }
            switch source {
            case .transitTier:
                break
            case .mediaTierFullsize, .mediaTierThumbnail:
                // Even if we are in message request state, the fact
                // that these downloads are on media tier means the
                // client that backed them up had them downloaded
                // before. Therefore, they should be good to redownload.
                return false
            }

            let thread: TSThread?
            switch owner {
            case .message(let source):
                let threadRowId: TSThread.RowId
                switch source {
                case .oversizeText(let metadata):
                    threadRowId = metadata.threadRowId
                case .sticker(let metadata):
                    threadRowId = metadata.threadRowId
                case .bodyAttachment(let metadata):
                    threadRowId = metadata.threadRowId
                case .quotedReply(let metadata):
                    threadRowId = metadata.threadRowId
                case .linkPreview(let metadata):
                    threadRowId = metadata.threadRowId
                case .contactAvatar(let metadata):
                    threadRowId = metadata.threadRowId
                }
                thread = threadStore.fetchThread(rowId: threadRowId, tx: tx)
            case .storyMessage(let source):
                let storyMessage = storyStore.fetchStoryMessage(rowId: source.storyMessageRowId, tx: tx)
                guard let storyMessage else {
                    owsFailDebug("can't check downloadability for non-existent owner")
                    return true
                }
                switch storyMessage.direction {
                case .outgoing:
                    // Ignore outgoing stories for purposes of pending message requests.
                    return false
                case .incoming:
                    break
                }
                if let groupId = storyMessage.groupId {
                    thread = threadStore.fetchGroupThread(groupId: groupId, tx: tx)
                } else {
                    thread = threadStore.fetchContactThreads(serviceId: storyMessage.authorAci, tx: tx).first
                }
            case .thread:
                // Ignore non-message cases for purposes of pending message request.
                return false
            }

            // If there's not a thread, err on the safe side and don't download it.
            guard let thread else {
                return true
            }

            return threadStore.hasPendingMessageRequest(thread: thread, tx: tx)
        }

        private func isDownloadBlockedByAutoDownloadSettings(
            priority: AttachmentDownloadPriority,
            owner: AttachmentReference.Owner,
            renderingFlag: AttachmentReference.RenderingFlag,
            mimeType: String,
            tx: DBReadTransaction,
        ) -> Bool {
            switch priority {
            case .userInitiated, .localClone:
                // Always download at these priorities.
                return false
            case .default:
                break
            case .backupRestore:
                // Despite being lower priority than default,
                // these actually should download despite the setting.
                return false
            }

            let autoDownloadableMediaTypes = mediaBandwidthPreferenceStore.autoDownloadableMediaTypes(tx: tx)

            switch owner {
            case .message(.bodyAttachment), .storyMessage(.media):
                if MimeTypeUtil.isSupportedImageMimeType(mimeType) {
                    return !autoDownloadableMediaTypes.contains(.photo)
                }
                if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
                    return !autoDownloadableMediaTypes.contains(.video)
                }
                if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
                    if renderingFlag == .voiceMessage {
                        return false
                    }
                    return !autoDownloadableMediaTypes.contains(.audio)
                }
                return !autoDownloadableMediaTypes.contains(.document)
            case .message(.oversizeText):
                return false
            case .message(.sticker):
                return !autoDownloadableMediaTypes.contains(.photo)
            case .message(.quotedReply):
                return false
            case .message(.linkPreview):
                return false
            case .message(.contactAvatar):
                return false
            case .storyMessage(.textStoryLinkPreview):
                return false
            case .thread(.threadWallpaperImage), .thread(.globalThreadWallpaperImage):
                return false
            }
        }
    }

    // MARK: - Downloads

    public typealias DownloadMetadata = AttachmentDownloads.DownloadMetadata

    private enum DownloadError: Error {
        case oversize
    }

    private enum DownloadType {
        case backup(metadata: BackupReadCredential, uuid: UUID)
        case transientAttachment(DownloadMetadata, uuid: UUID)
        case attachment(DownloadMetadata, id: Attachment.IDType)

        // MARK: - Helpers

        func urlPath() throws -> String {
            switch self {
            case .backup(let info, _):
                return info.backupLocationUrl()
            case .attachment(let metadata, _), .transientAttachment(let metadata, _):
                switch metadata.source {
                case .transitTier(let cdnKey):
                    guard let encodedKey = cdnKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                        throw OWSAssertionError("Invalid cdnKey.")
                    }
                    return "attachments/\(encodedKey)"
                case .mediaTier(_, let cdnCredential, let mediaId):
                    let prefix = cdnCredential.mediaTierUrlPrefix()
                    return "\(prefix)/\(mediaId.asBase64Url)"
                }
            }
        }

        func cdnNumber() -> UInt32 {
            switch self {
            case .backup(let info, _):
                return UInt32(clamping: info.cdn)
            case .attachment(let metadata, _), .transientAttachment(let metadata, _):
                return metadata.cdnNumber
            }
        }

        func additionalHeaders() -> HttpHeaders {
            switch self {
            case .backup(let metadata, _):
                return metadata.cdnAuthHeaders
            case .attachment(let metadata, _), .transientAttachment(let metadata, _):
                switch metadata.source {
                case .transitTier:
                    return [:]
                case .mediaTier(_, let cdnCredential, _):
                    return cdnCredential.cdnAuthHeaders
                }
            }
        }

        func isExpired() -> Bool {
            switch self {
            case .backup(let metadata, _):
                return metadata.isExpired
            case .attachment(let metadata, _), .transientAttachment(let metadata, _):
                switch metadata.source {
                case .transitTier:
                    return false
                case .mediaTier(_, let cdnCredential, _):
                    return cdnCredential.isExpired
                }
            }
        }
    }

    private struct DownloadState: Equatable, Hashable {
        let startDate = Date()
        let type: DownloadType

        init(type: DownloadType) {
            self.type = type
        }

        func urlPath() throws -> String {
            return try type.urlPath()
        }

        func cdnNumber() -> UInt32 {
            return type.cdnNumber()
        }

        func additionalHeaders() -> HttpHeaders {
            return type.additionalHeaders()
        }

        func isExpired() -> Bool {
            return type.isExpired()
        }

        private var identifier: String {
            switch type {
            case .backup(_, let uuid):
                uuid.uuidString
            case .transientAttachment(_, let uuid):
                uuid.uuidString
            case .attachment(_, let id):
                String(id)
            }
        }

        static func ==(lhs: Self, rhs: Self) -> Bool {
            lhs.identifier == rhs.identifier
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(identifier)
        }

    }

    private final class ProgressStates: Sendable {
        private struct States {
            var states: [Attachment.IDType: Double] = [:]
            var cancelledAttachmentIds: Set<Attachment.IDType> = []
        }

        private let states = TSMutex(initialState: States())

        func markDownloadCancelled(for attachmentId: Attachment.IDType) {
            states.withLock {
                $0.states[attachmentId] = nil
                $0.cancelledAttachmentIds.insert(attachmentId)
            }
        }

        func consumeCancellation(of attachmentId: Attachment.IDType) -> Bool {
            states.withLock { $0.cancelledAttachmentIds.remove(attachmentId) != nil }
        }
    }

    private actor DownloadQueue {
        private let progressStates: ProgressStates
        private nonisolated let signalService: OWSSignalServiceProtocol
        private let resumeDataCache: LRUCache<DownloadState, Data> = LRUCache(maxSize: 5)

        init(
            progressStates: ProgressStates,
            signalService: OWSSignalServiceProtocol,
        ) {
            self.progressStates = progressStates
            self.signalService = signalService
        }

        private let queue = ConcurrentTaskQueue(concurrentLimit: 12)

        /// Non-transient attachments have an in-memory disconnect from the downloadQueue and the actual job runner;
        /// they are enqueued to disk and then read off disk to be downloaded. In order to get an in-memory object
        /// like a Continuation or an OWSProgress across, we need to cache them in memory using this key.
        /// This does not apply to transient downloads since they stay in memory the whole time.
        struct DownloadKey: Hashable {
            let id: Attachment.IDType
            let source: QueuedAttachmentDownloadRecord.SourceType
        }

        private var downloadObservers = [DownloadKey: [CheckedContinuation<Void, Error>]]()
        private var downloadProgresses = [DownloadKey: [OWSProgressSink]]()
        private var finishedOrFailedDownloads = Set<DownloadKey>()
        private var progressIDs = [DownloadKey: UInt64]()

        func latestProgressID(downloadKey: DownloadKey?) -> UInt64 {
            guard let downloadKey else {
                return 0
            }
            return progressIDs[downloadKey] ?? 0
        }

        func clearOldDownloadsAndIncrementProgressID(key: DownloadKey) {
            finishedOrFailedDownloads.remove(key)

            let oldProgressID = progressIDs[key] ?? 0
            progressIDs[key] = oldProgressID + 1
        }

        func clearDownloadProgressAndMarkFinished(key: DownloadKey) {
            downloadProgresses.removeValue(forKey: key)
            finishedOrFailedDownloads.insert(key)
        }

        func waitForDownloadOfAttachment(
            id: Attachment.IDType,
            source: QueuedAttachmentDownloadRecord.SourceType,
            progress: OWSProgressSink?,
        ) async throws {
            return try await withCheckedThrowingContinuation { continuation in
                let key = DownloadKey(id: id, source: source)
                var observers = self.downloadObservers[key] ?? []
                observers.append(continuation)
                self.downloadObservers[key] = observers
                if let progress {
                    var progresses = downloadProgresses[key] ?? []
                    progresses.append(progress)
                    self.downloadProgresses[key] = progresses
                }
            }
        }

        func updateObservers(downloadKey: DownloadKey, error: Error?) {
            let observers = self.downloadObservers.removeValue(forKey: downloadKey) ?? []
            if let error {
                observers.forEach { $0.resume(throwing: error) }
            } else {
                observers.forEach { $0.resume() }
            }
        }

        nonisolated static func downloadKey(record: QueuedAttachmentDownloadRecord) -> DownloadKey {
            return DownloadKey(id: record.attachmentId, source: record.sourceType)
        }

        private nonisolated static func downloadKey(state: DownloadState) -> DownloadKey? {
            switch state.type {
            case .backup, .transientAttachment:
                return nil
            case .attachment(let downloadMetadata, let id):
                return DownloadKey(id: id, source: downloadMetadata.source.asQueuedDownloadSource)
            }
        }

        fileprivate func performHeadRequest(
            downloadState: DownloadState,
            maxDownloadSizeBytes: UInt64,
        ) async throws -> AttachmentDownloads.CdnInfo {
            // We don't need maxDownloadSizeBytes for this request, but we include it
            // to increase the likelihood of a shared URLSession cache hit.
            let urlSession = await self.signalService.sharedUrlSessionForCdn(
                cdnNumber: downloadState.cdnNumber(),
                maxResponseSize: maxDownloadSizeBytes,
            )
            let urlPath = try downloadState.urlPath()
            var headers = downloadState.additionalHeaders()
            headers["Content-Type"] = MimeType.applicationOctetStream.rawValue

            // Perform a HEAD request to get the byte length & last modified date from cdn.
            let request = try urlSession.endpoint.buildRequest(urlPath, method: .head, headers: headers)
            let response = try await urlSession.performRequest(request: request, ignoreAppExpiry: true)
            return try AttachmentDownloads.CdnInfo(response.headers)
        }

        /// Fetch the first `length` bytes of the object from the CDN, returning the fetched bytes,
        /// (or nil if the response was empty) alongside headers from the response (which are the
        /// same headers from a HEAD response).
        ///
        /// Length is limited to UInt16, and really should be even smaller, because this is _not_
        /// a download task, is not resumable, and should therefore only be used to fetch a very
        /// limited number of bytes.
        fileprivate func performPrefixRequest(
            downloadState: DownloadState,
            maxDownloadSizeBytes: UInt64,
            length: UInt16,
        ) async throws -> (AttachmentDownloads.CdnInfo, Data?) {
            let urlSession = await self.signalService.sharedUrlSessionForCdn(
                cdnNumber: downloadState.cdnNumber(),
                maxResponseSize: maxDownloadSizeBytes,
            )
            let urlPath = try downloadState.urlPath()
            var headers = downloadState.additionalHeaders()
            headers["Content-Type"] = MimeType.applicationOctetStream.rawValue
            headers["range"] = "bytes=0-\(length - 1)"

            let request = try urlSession.endpoint.buildRequest(urlPath, method: .get, headers: headers)
            let response = try await urlSession.performRequest(request: request, ignoreAppExpiry: true)
            let cdnInfo = try AttachmentDownloads.CdnInfo(response.headers)

            return (cdnInfo, response.responseBodyData)
        }

        func enqueueDownload(
            downloadState: DownloadState,
            maxDownloadSizeBytes: UInt64,
            expectedDownloadSize: DownloadSizeSource,
            progress: OWSProgressSink?,
        ) async throws -> URL {
            let progresses = (
                [progress]
                    + (
                        Self.downloadKey(state: downloadState)
                            .map({ self.downloadProgresses[$0] ?? [] })
                            ?? []
                    ),
            ).compacted()

            return try await queue.run {
                return try await performDownload(
                    downloadState: downloadState,
                    progresses: progresses,
                    maxDownloadSizeBytes: maxDownloadSizeBytes,
                    expectedDownloadSize: expectedDownloadSize,
                )
            }
        }

        enum DownloadSizeSource {
            case useHeadRequest
            case estimatedSizeBytes(UInt64)
        }

        private nonisolated func performDownload(
            downloadState: DownloadState,
            progresses: [OWSProgressSink],
            maxDownloadSizeBytes: UInt64,
            expectedDownloadSize: DownloadSizeSource,
        ) async throws -> URL {
            let urlPath = try downloadState.urlPath()
            var headers = downloadState.additionalHeaders()
            headers["Content-Type"] = MimeType.applicationOctetStream.rawValue

            let attachmentId: Attachment.IDType?
            switch downloadState.type {
            case .backup, .transientAttachment:
                attachmentId = nil
            case .attachment(_, let id):
                attachmentId = id
            }

            if downloadState.isExpired() {
                throw AttachmentDownloads.Error.expiredCredentials
            }

            let expectedDownloadSizeBytes: UInt64
            switch expectedDownloadSize {
            case .estimatedSizeBytes(let size):
                expectedDownloadSizeBytes = size
            case .useHeadRequest:
                // Perform a HEAD request just to get the byte length from cdn.
                let downloadInfo = try await performHeadRequest(
                    downloadState: downloadState,
                    maxDownloadSizeBytes: maxDownloadSizeBytes,
                )
                expectedDownloadSizeBytes = downloadInfo.contentLength
            }

            var progressSources: [OWSProgressSource] = []
            for progress in progresses {
                progressSources.append(await progress.addSource(
                    withLabel: AttachmentDownloads.downloadProgressLabel,
                    unitCount: expectedDownloadSizeBytes,
                ))
            }

            return try await Retry.performRepeatedly {
                if downloadState.isExpired() {
                    throw AttachmentDownloads.Error.expiredCredentials
                }

                let resumeData = await resumeDataCache.object(forKey: downloadState)
                let urlSession = await self.signalService.sharedUrlSessionForCdn(
                    cdnNumber: downloadState.cdnNumber(),
                    maxResponseSize: maxDownloadSizeBytes,
                )

                var downloadTask: Task<OWSUrlDownloadResponse, Error>?

                let wrappedProgressID = await latestProgressID(downloadKey: DownloadQueue.downloadKey(state: downloadState))
                let wrappedProgress = OWSProgress.createSink { [weak self] progressValue in
                    if let k = DownloadQueue.downloadKey(state: downloadState) {
                        if await self?.latestProgressID(downloadKey: k) != wrappedProgressID {
                            // A new download has started, don't send progress updates or notifications.
                            return
                        }

                        if let self, await finishedOrFailedDownloads.contains(k) {
                            // If we've already finished the download, send the notification so
                            // handlers can get 100% updates but don't update the progress sources,
                            // which may be double counting.
                            handleDownloadProgress(
                                downloadState: downloadState,
                                task: downloadTask,
                                progress: progressValue,
                                expectedDownloadSizeBytes: expectedDownloadSizeBytes,
                                attachmentId: attachmentId,
                            )
                            return
                        }
                    }

                    for progressSource in progressSources {
                        if progressSource.completedUnitCount < progressValue.completedUnitCount {
                            progressSource.incrementCompletedUnitCount(by: progressValue.completedUnitCount - progressSource.completedUnitCount)
                        }
                    }
                    self?.handleDownloadProgress(
                        downloadState: downloadState,
                        task: downloadTask,
                        progress: progressValue,
                        expectedDownloadSizeBytes: expectedDownloadSizeBytes,
                        attachmentId: attachmentId,
                    )
                }
                let wrappedProgressSource = await wrappedProgress.addSource(
                    withLabel: "source",
                    unitCount: expectedDownloadSizeBytes,
                )

                let downloadResponse: OWSUrlDownloadResponse
                if let resumeData {
                    let request = try urlSession.endpoint.buildRequest(urlPath, method: .get, headers: headers)
                    guard let requestUrl = request.url else {
                        throw OWSAssertionError("Request missing url.")
                    }
                    downloadTask = Task {
                        return try await urlSession.performDownload(
                            requestUrl: requestUrl,
                            resumeData: resumeData,
                            progressBlock: wrappedProgressSource.asProgressBlock(),
                        )
                    }
                    downloadResponse = try await downloadTask!.value
                } else {
                    downloadTask = Task {
                        return try await urlSession.performDownload(
                            urlPath,
                            method: .get,
                            headers: headers,
                            progressBlock: wrappedProgressSource.asProgressBlock(),
                        )
                    }
                    downloadResponse = try await downloadTask!.value
                }
                let downloadUrl = downloadResponse.downloadUrl
                let tmpFile = OWSFileSystem.temporaryFileUrl(
                    fileExtension: nil,
                    isAvailableWhileDeviceLocked: false,
                )
                try OWSFileSystem.moveFile(from: downloadUrl, to: tmpFile)
                return tmpFile
            } onError: { error, attemptCount in
                Logger.warn("Error: \(error)")

                if let resumeData = ((error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data)?.nilIfEmpty {
                    await resumeDataCache.set(key: downloadState, value: resumeData)
                }

                switch downloadState.type {
                case .backup, .transientAttachment:
                    break
                case .attachment(_, let attachmentId):
                    NotificationCenter.default.postOnMainThread(
                        name: AttachmentDownloads.attachmentDownloadStoppedNotification,
                        object: nil,
                        userInfo: [
                            AttachmentDownloads.attachmentDownloadAttachmentIDKey: attachmentId,
                        ],
                    )
                }

                if case URLError.cancelled = error {
                    throw error
                }

                let maxAttemptCount = 16
                guard attemptCount < maxAttemptCount, error.isNetworkFailureOrTimeout else {
                    throw error
                }

                // Wait briefly before retrying.
                try await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)
            }
        }

        private nonisolated func handleDownloadProgress(
            downloadState: DownloadState,
            task: Task<OWSUrlDownloadResponse, Error>?,
            progress: OWSProgress,
            expectedDownloadSizeBytes: UInt64?,
            attachmentId: Attachment.IDType?,
        ) {
            if let attachmentId, progressStates.consumeCancellation(of: attachmentId) {
                Logger.info("Cancelling download.")
                // Cancelling will inform the URLSessionTask delegate.
                task?.cancel()
                return
            }

            // Use a slightly non-zero value to ensure that the progress
            // indicator shows up as quickly as possible.
            let progressTheta: Float = 0.001

            let fractionCompleted: Float
            if progress.completedUnitCount > 0 {
                fractionCompleted = max(progressTheta, progress.percentComplete)
            } else if expectedDownloadSizeBytes != nil {
                fractionCompleted = progressTheta
            } else {
                // Don't do anything until we've received at least one byte of data,
                // or estimated the download size.
                return
            }

            switch downloadState.type {
            case .backup, .transientAttachment:
                break
            case .attachment(_, let attachmentId):
                NotificationCenter.default.postOnMainThread(
                    name: AttachmentDownloads.attachmentDownloadProgressNotification,
                    object: nil,
                    userInfo: [
                        AttachmentDownloads.attachmentDownloadProgressKey: fractionCompleted,
                        AttachmentDownloads.attachmentDownloadAttachmentIDKey: attachmentId,
                    ],
                )
            }
        }
    }

    private class Decrypter {

        private let attachmentValidator: AttachmentContentValidator
        private let stickerManager: Shims.StickerManager

        init(
            attachmentValidator: AttachmentContentValidator,
            stickerManager: Shims.StickerManager,
        ) {
            self.attachmentValidator = attachmentValidator
            self.stickerManager = stickerManager
        }

        // Use concurrent=1 queue to ensure that we only load into memory
        // & decrypt a single attachment at a time.
        private let decryptionQueue = ConcurrentTaskQueue(concurrentLimit: 1)

        func decryptTransientAttachment(
            encryptedFileUrl: URL,
            metadata: DecryptionMetadata,
        ) async throws -> URL {
            return try await decryptionQueue.run {
                do {
                    // Transient attachments decrypt to a tmp file.
                    let outputUrl = OWSFileSystem.temporaryFileUrl(
                        fileExtension: nil,
                        isAvailableWhileDeviceLocked: false,
                    )

                    try Cryptography.decryptAttachment(at: encryptedFileUrl, metadata: metadata, output: outputUrl)

                    return outputUrl
                } catch let error {
                    do {
                        try OWSFileSystem.deleteFileIfExists(url: encryptedFileUrl)
                    } catch let deleteFileError {
                        owsFailDebug("Error: \(deleteFileError).")
                    }
                    throw error
                }
            }
        }

        func validateAndPrepareInstalledSticker(
            _ sticker: InstalledStickerRecord,
        ) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            let stickerManager = self.stickerManager
            return try await decryptionQueue.run {
                guard
                    let stickerDataUrl = stickerManager.stickerDataUrl(
                        forInstalledSticker: sticker,
                        verifyExists: true,
                    )
                else {
                    throw OWSAssertionError("Missing sticker")
                }

                let mimeType: MimeType
                let imageMetadata = try? DataImageSource.forPath(stickerDataUrl.path).imageMetadata()
                if let imageMetadata {
                    mimeType = imageMetadata.imageFormat.mimeType
                } else {
                    mimeType = MimeType.imageWebp
                }

                return try await attachmentValidator.validateDataSourceContents(
                    DataSourcePath(fileUrl: stickerDataUrl, ownership: .borrowed),
                    mimeType: mimeType.rawValue,
                    renderingFlag: .borderless,
                    sourceFilename: nil,
                )
            }
        }

        enum ValidationMetadata {
            case transitTier(
                mimeType: String,
                attachmentKey: AttachmentKey,
                plaintextLength: UInt32,
                integrityCheck: AttachmentIntegrityCheck,
            )

            case mediaTier(
                mimeType: String,
                /// "Outer" encryption; always derived via MediaRootBackupKey.
                outerAttachmentKey: AttachmentKey,
                /// "Inner" encryption: transit tier encryption for full-size files and
                /// always derived via MediaRootBackupKey for thumbnails.
                innerDecryptionMetadata: DecryptionMetadata,
                /// Encryption key used to store the file "at rest"/locally. Matches the
                /// "inner" encryption for full-size files (which is also the transit tier
                /// encryption we use for non-backed-up attachments). Matches the full-size
                /// attachment encryption key for thumbnails.
                localAttachmentKey: AttachmentKey,
            )
        }

        func validateAndPrepare(
            encryptedFileUrl: URL,
            validationMetadata: ValidationMetadata,
        ) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            return try await decryptionQueue.run {
                switch validationMetadata {
                case .transitTier(let mimeType, let attachmentKey, let plaintextLength, let integrityCheck):
                    return try await attachmentValidator.validateDownloadedContents(
                        ofEncryptedFileAt: encryptedFileUrl,
                        attachmentKey: attachmentKey,
                        plaintextLength: plaintextLength,
                        integrityCheck: integrityCheck,
                        mimeType: mimeType,
                        renderingFlag: .default,
                        sourceFilename: nil,
                    )
                case .mediaTier(let mimeType, let outerAttachmentKey, let innerDecryptionMetadata, let localEncryptionKey):
                    return try await attachmentValidator.validateBackupMediaFileContents(
                        fileUrl: encryptedFileUrl,
                        outerAttachmentKey: outerAttachmentKey,
                        innerDecryptionMetadata: innerDecryptionMetadata,
                        finalAttachmentKey: localEncryptionKey,
                        mimeType: mimeType,
                        renderingFlag: .default,
                        sourceFilename: nil,
                    )
                }
            }
        }

        func prepareQuotedReplyThumbnail(originalAttachmentStream: AttachmentStream) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            return try await decryptionQueue.run {
                return try await attachmentValidator.prepareQuotedReplyThumbnail(
                    fromOriginalAttachmentStream: originalAttachmentStream,
                )
            }
        }
    }

    private class AttachmentUpdater {

        private let attachmentStore: AttachmentStore
        private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
        private let dateProvider: DateProvider
        private let db: any DB
        private let decrypter: Decrypter
        private let interactionStore: InteractionStore
        private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
        private let orphanedAttachmentStore: OrphanedAttachmentStore
        private let orphanedBackupAttachmentScheduler: OrphanedBackupAttachmentScheduler
        private let storyStore: StoryStore
        private let threadStore: ThreadStore

        init(
            attachmentStore: AttachmentStore,
            backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
            dateProvider: @escaping DateProvider,
            db: any DB,
            decrypter: Decrypter,
            interactionStore: InteractionStore,
            orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
            orphanedAttachmentStore: OrphanedAttachmentStore,
            orphanedBackupAttachmentScheduler: OrphanedBackupAttachmentScheduler,
            storyStore: StoryStore,
            threadStore: ThreadStore,
        ) {
            self.attachmentStore = attachmentStore
            self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
            self.dateProvider = dateProvider
            self.db = db
            self.decrypter = decrypter
            self.interactionStore = interactionStore
            self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
            self.orphanedAttachmentStore = orphanedAttachmentStore
            self.orphanedBackupAttachmentScheduler = orphanedBackupAttachmentScheduler
            self.storyStore = storyStore
            self.threadStore = threadStore
        }

        func updateAttachmentAsDownloaded(
            attachmentId: Attachment.IDType,
            pendingAttachment: PendingAttachment,
            source: QueuedAttachmentDownloadRecord.SourceType,
            priority: AttachmentDownloadPriority,
            timestamp: UInt64,
        ) async throws -> DownloadResult {
            return try await db.awaitableWrite { tx in
                guard orphanedAttachmentStore.orphanAttachmentExists(with: pendingAttachment.orphanRecordId, tx: tx) else {
                    throw OWSAssertionError("Attachment file deleted before creation")
                }

                // We may find, when we go to update the attachment, that we had
                // already downloaded this attachment. If so, we'll thereafter
                // want to refer to the existing attachment instead.
                var attachmentId = attachmentId

                guard var attachmentWeJustDownloaded = attachmentStore.fetch(id: attachmentId, tx: tx) else {
                    throw OWSGenericError("Missing attachment after download; could have been deleted while downloading.")
                }

                if let stream = attachmentWeJustDownloaded.asStream() {
                    // Its already a stream?
                    return .stream(stream)
                }

                let streamInfo = Attachment.StreamInfo(pendingAttachment: pendingAttachment)

                // Try and update the attachment.
                do throws(AttachmentInsertError) {
                    try self.attachmentStore.updateAttachmentAsDownloaded(
                        attachment: attachmentWeJustDownloaded,
                        sourceType: source,
                        priority: priority,
                        streamInfo: streamInfo,
                        timestamp: timestamp,
                        tx: tx,
                    )
                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingAttachment.orphanRecordId, tx: tx)

                    self.orphanedBackupAttachmentScheduler.didCreateOrUpdateAttachment(
                        withMediaName: pendingAttachment.mediaName,
                        tx: tx,
                    )
                } catch {
                    let existingAttachmentId: Attachment.IDType = try AttachmentManagerImpl.handleAttachmentInsertError(
                        error,
                        pendingAttachmentStreamInfo: streamInfo,
                        pendingAttachmentEncryptionKey: pendingAttachment.encryptionKey,
                        pendingAttachmentOrphanRecordId: pendingAttachment.orphanRecordId,
                        pendingAttachmentLatestTransitTierInfo: attachmentWeJustDownloaded.latestTransitTierInfo,
                        pendingAttachmentOriginalTransitTierInfo: attachmentWeJustDownloaded.originalTransitTierInfo,
                        attachmentStore: attachmentStore,
                        orphanedAttachmentCleaner: orphanedAttachmentCleaner,
                        orphanedAttachmentStore: orphanedAttachmentStore,
                        backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                        orphanedBackupAttachmentScheduler: orphanedBackupAttachmentScheduler,
                        dateProvider: dateProvider,
                        tx: tx,
                    )

                    // Already have an attachment with the same plaintext hash or media name!
                    // Move all existing references to that copy, instead.
                    // Doing so should delete the original attachment pointer.

                    // Just hold all refs in memory; there shouldn't in practice be
                    // so many pointers to the same attachment.
                    var references = [AttachmentReference]()
                    self.attachmentStore.enumerateAllReferences(
                        toAttachmentId: attachmentId,
                        tx: tx,
                    ) { reference, _ in
                        references.append(reference)
                    }
                    for reference in references {
                        self.attachmentStore.removeReference(
                            reference: reference,
                            tx: tx,
                        )
                        let newOwnerParams = AttachmentReference.ConstructionParams(
                            owner: reference.owner.forReassignmentWithContentType(
                                pendingAttachment.contentType,
                                mimeType: pendingAttachment.mimeType,
                            ),
                            sourceFilename: reference.sourceFilename,
                            sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
                            sourceMediaSizePixels: reference.sourceMediaSizePixels,
                        )
                        attachmentStore.addReference(
                            newOwnerParams,
                            attachmentRowId: existingAttachmentId,
                            tx: tx,
                        )
                    }

                    attachmentId = existingAttachmentId
                }

                // Refetch the attachment, to reflect `updateAttachmentAsDownloaded`.
                attachmentWeJustDownloaded = attachmentStore.fetch(id: attachmentId, tx: tx)!

                tx.addSyncCompletion { [self] in
                    db.asyncWrite { [self] tx in
                        touchAllOwners(attachmentId: attachmentId, tx: tx)
                    }
                }

                switch source {
                case .transitTier:
                    guard let stream = attachmentWeJustDownloaded.asStream() else {
                        throw OWSAssertionError("Not a stream")
                    }

                    // After we download an attachment and verify its digest, we can
                    // schedule it for "upload" to the media (backup) tier. "Upload"
                    // really means "copy from transit tier" and since we just downloaded
                    // we shouldn't need to reupload to do that; we just needed to verify
                    // the digest before copying.
                    backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                        attachmentWeJustDownloaded,
                        mode: .all,
                        tx: tx,
                    )
                    tx.addSyncCompletion {
                        NotificationCenter.default.post(name: .startBackupAttachmentUploadQueue, object: nil)
                    }

                    return .stream(stream)
                case .mediaTierFullsize:
                    guard let stream = attachmentWeJustDownloaded.asStream() else {
                        throw OWSAssertionError("Not a stream")
                    }

                    return .stream(stream)
                case .mediaTierThumbnail:
                    guard let thumbnail = attachmentWeJustDownloaded.asBackupThumbnail() else {
                        throw OWSAssertionError("Not a thumbnail")
                    }

                    return .thumbnail(thumbnail)
                }
            }
        }

        func updateAttachmentFromInstalledSticker(
            attachmentId: Attachment.IDType,
            pendingAttachment: PendingAttachment,
        ) async throws -> AttachmentStream {
            return try await db.awaitableWriteWithRollbackIfThrows { tx -> AttachmentStream in
                guard let existingAttachment = self.attachmentStore.fetch(id: attachmentId, tx: tx) else {
                    throw OWSGenericError("Missing attachment after download; could have been deleted while downloading.")
                }
                if let stream = existingAttachment.asStream() {
                    // Its already a stream?
                    return stream
                }

                var references = [AttachmentReference]()
                self.attachmentStore.enumerateAllReferences(
                    toAttachmentId: attachmentId,
                    tx: tx,
                ) { reference, _ in
                    references.append(reference)
                }
                // Arbitrarily pick the first reference as the one we will use as the initial ref to
                // the new stream. The others' references will be re-pointed to the new stream afterwards.
                guard let firstReference = references.first else {
                    throw OWSAssertionError("Attachments should never have zero references")
                }

                self.attachmentStore.removeReference(
                    reference: firstReference,
                    tx: tx,
                )

                let streamInfo = Attachment.StreamInfo(pendingAttachment: pendingAttachment)

                let alreadyAssignedFirstReference: Bool

                let newAttachmentStream: AttachmentStream
                do {
                    guard self.orphanedAttachmentStore.orphanAttachmentExists(with: pendingAttachment.orphanRecordId, tx: tx) else {
                        throw OWSAssertionError("Attachment file deleted before creation")
                    }

                    let referenceParams = AttachmentReference.ConstructionParams(
                        owner: firstReference.owner.forReassignmentWithContentType(
                            pendingAttachment.contentType,
                            mimeType: pendingAttachment.mimeType,
                        ),
                        sourceFilename: firstReference.sourceFilename,
                        sourceUnencryptedByteCount: pendingAttachment.unencryptedByteCount,
                        sourceMediaSizePixels: pendingAttachment.mediaPixelSize,
                    )
                    var attachmentRecord = Attachment.Record.forInsertingStream(
                        blurHash: pendingAttachment.blurHash,
                        mimeType: pendingAttachment.mimeType,
                        contentType: pendingAttachment.contentType,
                        encryptionKey: pendingAttachment.encryptionKey,
                        streamInfo: streamInfo,
                        plaintextHash: pendingAttachment.plaintextHash,
                        mediaName: pendingAttachment.mediaName,
                    )

                    let attachment = try self.attachmentStore.insert(
                        &attachmentRecord,
                        reference: referenceParams,
                        tx: tx,
                    )

                    self.orphanedBackupAttachmentScheduler.didCreateOrUpdateAttachment(
                        withMediaName: pendingAttachment.mediaName,
                        tx: tx,
                    )

                    backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                        attachment,
                        mode: .all,
                        tx: tx,
                    )

                    tx.addSyncCompletion {
                        NotificationCenter.default.post(name: .startBackupAttachmentUploadQueue, object: nil)
                    }

                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingAttachment.orphanRecordId, tx: tx)

                    newAttachmentStream = AttachmentStream(
                        attachment: attachment,
                        info: streamInfo,
                    )
                    alreadyAssignedFirstReference = true
                } catch let error {
                    let existingAttachmentId: Attachment.IDType
                    if let error = error as? AttachmentInsertError {
                        existingAttachmentId = try AttachmentManagerImpl.handleAttachmentInsertError(
                            error,
                            pendingAttachmentStreamInfo: streamInfo,
                            pendingAttachmentEncryptionKey: pendingAttachment.encryptionKey,
                            pendingAttachmentOrphanRecordId: pendingAttachment.orphanRecordId,
                            pendingAttachmentLatestTransitTierInfo: nil,
                            pendingAttachmentOriginalTransitTierInfo: nil,
                            attachmentStore: attachmentStore,
                            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
                            orphanedAttachmentStore: orphanedAttachmentStore,
                            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                            orphanedBackupAttachmentScheduler: orphanedBackupAttachmentScheduler,
                            dateProvider: dateProvider,
                            tx: tx,
                        )
                        tx.addSyncCompletion {
                            NotificationCenter.default.post(name: .startBackupAttachmentUploadQueue, object: nil)
                        }
                    } else {
                        throw error
                    }

                    // Already have an attachment with the same plaintext hash or media name!
                    // We will instead re-point all references to this attachment.
                    guard
                        let attachment = attachmentStore.fetch(
                            id: existingAttachmentId,
                            tx: tx,
                        ),
                        let attachmentStream = attachment.asStream()
                    else {
                        throw OWSAssertionError("Missing stream for attachment we just matched against!")
                    }
                    newAttachmentStream = attachmentStream
                    alreadyAssignedFirstReference = false
                }

                let referencesToUpdate = alreadyAssignedFirstReference
                    ? references.suffix(max(references.count - 1, 0))
                    : references
                for reference in referencesToUpdate {
                    attachmentStore.removeReference(
                        reference: reference,
                        tx: tx,
                    )
                    let newOwnerParams = AttachmentReference.ConstructionParams(
                        owner: reference.owner.forReassignmentWithContentType(
                            newAttachmentStream.contentType,
                            mimeType: newAttachmentStream.mimeType,
                        ),
                        sourceFilename: reference.sourceFilename,
                        sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
                        sourceMediaSizePixels: reference.sourceMediaSizePixels,
                    )
                    attachmentStore.addReference(
                        newOwnerParams,
                        attachmentRowId: newAttachmentStream.attachment.id,
                        tx: tx,
                    )
                }
                references.forEach { reference in
                    // Its ok to point at the old owner here; its the same message id
                    // or story message id etc, which is what we use for this.
                    self.touchOwner(reference.owner, tx: tx)
                }
                return newAttachmentStream
            }
        }

        func copyThumbnailForQuotedReplyIfNeeded(_ downloadedAttachment: AttachmentStream) async throws {
            let thumbnailAttachments = db.read { tx in
                return self.attachmentStore.allQuotedReplyAttachments(
                    forOriginalAttachmentId: downloadedAttachment.attachment.id,
                    tx: tx,
                )
            }
            guard thumbnailAttachments.contains(where: { $0.asStream() == nil }) else {
                // all the referencing thumbnails already have their own streams, nothing to do.
                return
            }
            let pendingThumbnailAttachment = try await self.decrypter.prepareQuotedReplyThumbnail(
                originalAttachmentStream: downloadedAttachment,
            )

            try await db.awaitableWriteWithRollbackIfThrows { tx in
                let alreadyAssignedFirstReference: Bool
                let thumbnailAttachments = attachmentStore
                    .allQuotedReplyAttachments(
                        forOriginalAttachmentId: downloadedAttachment.attachment.id,
                        tx: tx,
                    )
                    .filter({ $0.asStream() == nil })

                let references = thumbnailAttachments.flatMap { attachment in
                    var refs = [AttachmentReference]()
                    self.attachmentStore.enumerateAllReferences(
                        toAttachmentId: attachment.id,
                        tx: tx,
                    ) { ref, _ in
                        refs.append(ref)
                    }
                    return refs
                }
                // Arbitrarily pick the first thumbnail as the one we will use as the initial ref to
                // the new stream. The others' references will be re-pointed to the new stream afterwards.
                guard let firstReference = references.first else {
                    // Nothing to update.
                    return
                }

                attachmentStore.removeReference(
                    reference: firstReference,
                    tx: tx,
                )

                let streamInfo = Attachment.StreamInfo(pendingAttachment: pendingThumbnailAttachment)

                let thumbnailAttachmentId: Attachment.IDType
                do {
                    guard self.orphanedAttachmentStore.orphanAttachmentExists(with: pendingThumbnailAttachment.orphanRecordId, tx: tx) else {
                        throw OWSAssertionError("Attachment file deleted before creation")
                    }

                    let referenceParams = AttachmentReference.ConstructionParams(
                        owner: firstReference.owner.forReassignmentWithContentType(
                            pendingThumbnailAttachment.contentType,
                            mimeType: pendingThumbnailAttachment.mimeType,
                        ),
                        sourceFilename: firstReference.sourceFilename,
                        sourceUnencryptedByteCount: pendingThumbnailAttachment.unencryptedByteCount,
                        sourceMediaSizePixels: pendingThumbnailAttachment.mediaPixelSize,
                    )
                    var attachmentRecord = Attachment.Record.forInsertingStream(
                        blurHash: pendingThumbnailAttachment.blurHash,
                        mimeType: pendingThumbnailAttachment.mimeType,
                        contentType: pendingThumbnailAttachment.contentType,
                        encryptionKey: pendingThumbnailAttachment.encryptionKey,
                        streamInfo: streamInfo,
                        plaintextHash: pendingThumbnailAttachment.plaintextHash,
                        mediaName: pendingThumbnailAttachment.mediaName,
                    )

                    let newAttachment = try self.attachmentStore.insert(
                        &attachmentRecord,
                        reference: referenceParams,
                        tx: tx,
                    )

                    self.orphanedBackupAttachmentScheduler.didCreateOrUpdateAttachment(
                        withMediaName: pendingThumbnailAttachment.mediaName,
                        tx: tx,
                    )

                    backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                        newAttachment,
                        mode: .all,
                        tx: tx,
                    )
                    tx.addSyncCompletion {
                        NotificationCenter.default.post(name: .startBackupAttachmentUploadQueue, object: nil)
                    }

                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingThumbnailAttachment.orphanRecordId, tx: tx)

                    guard
                        let referencedAttachment = attachmentStore.fetchAnyReferencedAttachment(
                            for: referenceParams.owner.id,
                            tx: tx,
                        )
                    else {
                        throw OWSAssertionError("Missing attachment we just created")
                    }
                    thumbnailAttachmentId = referencedAttachment.attachment.id
                    alreadyAssignedFirstReference = true
                } catch let error {
                    let existingAttachmentId: Attachment.IDType
                    if let error = error as? AttachmentInsertError {
                        existingAttachmentId = try AttachmentManagerImpl.handleAttachmentInsertError(
                            error,
                            pendingAttachmentStreamInfo: streamInfo,
                            pendingAttachmentEncryptionKey: pendingThumbnailAttachment.encryptionKey,
                            pendingAttachmentOrphanRecordId: pendingThumbnailAttachment.orphanRecordId,
                            pendingAttachmentLatestTransitTierInfo: nil,
                            pendingAttachmentOriginalTransitTierInfo: nil,
                            attachmentStore: attachmentStore,
                            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
                            orphanedAttachmentStore: orphanedAttachmentStore,
                            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                            orphanedBackupAttachmentScheduler: orphanedBackupAttachmentScheduler,
                            dateProvider: dateProvider,
                            tx: tx,
                        )
                        tx.addSyncCompletion {
                            NotificationCenter.default.post(name: .startBackupAttachmentUploadQueue, object: nil)
                        }
                    } else {
                        throw error
                    }

                    // Already have an attachment with the same plaintext hash or media name!
                    // We will instead re-point all references to this attachment.
                    thumbnailAttachmentId = existingAttachmentId
                    alreadyAssignedFirstReference = false
                }

                // Move all existing references to the new thumbnail stream.
                let referencesToUpdate = alreadyAssignedFirstReference
                    ? references.suffix(max(references.count - 1, 0))
                    : references
                for reference in referencesToUpdate {
                    attachmentStore.removeReference(
                        reference: reference,
                        tx: tx,
                    )
                    let newOwnerParams = AttachmentReference.ConstructionParams(
                        owner: reference.owner.forReassignmentWithContentType(
                            pendingThumbnailAttachment.contentType,
                            mimeType: pendingThumbnailAttachment.mimeType,
                        ),
                        sourceFilename: reference.sourceFilename,
                        sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
                        sourceMediaSizePixels: reference.sourceMediaSizePixels,
                    )
                    attachmentStore.addReference(
                        newOwnerParams,
                        attachmentRowId: thumbnailAttachmentId,
                        tx: tx,
                    )
                }
                references.forEach { reference in
                    // Its ok to point at the old owner here; its the same message id
                    // or story message id etc, which is what we use for this.
                    self.touchOwner(reference.owner, tx: tx)
                }

                if let thumbnailAttachment = attachmentStore.fetch(id: thumbnailAttachmentId, tx: tx)?.asStream() {
                    // Schedule upload, if needed.
                    backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                        thumbnailAttachment.attachment,
                        mode: .all,
                        tx: tx,
                    )
                    tx.addSyncCompletion {
                        NotificationCenter.default.post(name: .startBackupAttachmentUploadQueue, object: nil)
                    }
                }
            }
        }

        func touchAllOwners(attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
            self.attachmentStore.enumerateAllReferences(
                toAttachmentId: attachmentId,
                tx: tx,
            ) { reference, _ in
                touchOwner(reference.owner, tx: tx)
            }
        }

        func touchOwner(_ owner: AttachmentReference.Owner, tx: DBWriteTransaction) {
            switch owner {
            case .thread:
                // TODO: perhaps a mechanism to update a thread once wallpaper is loaded?
                break

            case .message(let messageSource):
                guard
                    let interaction = interactionStore.fetchInteraction(
                        rowId: messageSource.messageRowId,
                        tx: tx,
                    )
                else {
                    break
                }
                db.touch(interaction: interaction, shouldReindex: false, tx: tx)

            case .storyMessage(let storyMessageSource):
                guard
                    let storyMessage = storyStore.fetchStoryMessage(
                        rowId: storyMessageSource.storyMessageRowId,
                        tx: tx,
                    )
                else {
                    break
                }
                db.touch(storyMessage: storyMessage, tx: tx)
            }
        }
    }
}

extension AttachmentDownloadManagerImpl {
    public enum Shims {
        public typealias StickerManager = _AttachmentDownloadManagerImpl_StickerManagerShim
    }

    public enum Wrappers {
        public typealias StickerManager = _AttachmentDownloadManagerImpl_StickerManagerWrapper
    }
}

public protocol _AttachmentDownloadManagerImpl_StickerManagerShim {

    func fetchInstalledSticker(packId: Data, stickerId: UInt32, tx: DBReadTransaction) -> InstalledStickerRecord?

    func stickerDataUrl(forInstalledSticker: InstalledStickerRecord, verifyExists: Bool) -> URL?
}

public class _AttachmentDownloadManagerImpl_StickerManagerWrapper: _AttachmentDownloadManagerImpl_StickerManagerShim {
    public init() {}

    public func fetchInstalledSticker(packId: Data, stickerId: UInt32, tx: DBReadTransaction) -> InstalledStickerRecord? {
        return StickerManager.fetchInstalledSticker(packId: packId, stickerId: stickerId, transaction: tx)
    }

    public func stickerDataUrl(forInstalledSticker: InstalledStickerRecord, verifyExists: Bool) -> URL? {
        return StickerManager.stickerDataUrl(forInstalledSticker: forInstalledSticker, verifyExists: verifyExists)
    }
}
