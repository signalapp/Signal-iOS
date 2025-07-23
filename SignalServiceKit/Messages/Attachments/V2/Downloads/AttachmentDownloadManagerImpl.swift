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
    private let db: any DB
    private let decrypter: Decrypter
    private let downloadQueue: DownloadQueue
    private let downloadabilityChecker: DownloadabilityChecker
    private let progressStates: ProgressStates
    private let queueLoader: TaskQueueLoader<DownloadTaskRunner>
    private let tsAccountManager: TSAccountManager

    public init(
        appReadiness: AppReadiness,
        attachmentDownloadStore: AttachmentDownloadStore,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner,
        backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
        backupKeyMaterial: BackupKeyMaterial,
        backupRequestManager: BackupRequestManager,
        currentCallProvider: CurrentCallProvider,
        dateProvider: @escaping DateProvider,
        db: any DB,
        interactionStore: InteractionStore,
        mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
        orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager,
        profileManager: Shims.ProfileManager,
        remoteConfigManager: RemoteConfigManager,
        signalService: OWSSignalServiceProtocol,
        stickerManager: Shims.StickerManager,
        storyStore: StoryStore,
        threadStore: ThreadStore,
        tsAccountManager: TSAccountManager
    ) {
        self.attachmentDownloadStore = attachmentDownloadStore
        self.attachmentStore = attachmentStore
        self.appReadiness = appReadiness
        self.db = db
        self.decrypter = Decrypter(
            attachmentValidator: attachmentValidator,
            stickerManager: stickerManager
        )
        self.progressStates = ProgressStates()
        self.downloadQueue = DownloadQueue(
            progressStates: progressStates,
            signalService: signalService
        )
        self.attachmentUpdater = AttachmentUpdater(
            attachmentStore: attachmentStore,
            backupAttachmentUploadQueueRunner: backupAttachmentUploadQueueRunner,
            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
            db: db,
            decrypter: decrypter,
            interactionStore: interactionStore,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
            storyStore: storyStore,
            threadStore: threadStore
        )
        self.downloadabilityChecker = DownloadabilityChecker(
            attachmentStore: attachmentStore,
            currentCallProvider: currentCallProvider,
            db: db,
            mediaBandwidthPreferenceStore: mediaBandwidthPreferenceStore,
            profileManager: profileManager,
            threadStore: threadStore
        )
        let taskRunner = DownloadTaskRunner(
            attachmentDownloadStore: attachmentDownloadStore,
            attachmentStore: attachmentStore,
            attachmentUpdater: attachmentUpdater,
            backupKeyMaterial: backupKeyMaterial,
            backupRequestManager: backupRequestManager,
            dateProvider: dateProvider,
            db: db,
            decrypter: decrypter,
            downloadQueue: downloadQueue,
            downloadabilityChecker: downloadabilityChecker,
            remoteConfigManager: remoteConfigManager,
            stickerManager: stickerManager,
            tsAccountManager: tsAccountManager
        )
        self.queueLoader = TaskQueueLoader(
            maxConcurrentTasks: 4,
            dateProvider: dateProvider,
            db: db,
            runner: taskRunner
        )
        self.tsAccountManager = tsAccountManager

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            guard let self else { return }
            self.beginDownloadingIfNecessary()

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(registrationStateDidChange),
                name: .registrationStateDidChange,
                object: nil
            )
        }
    }

    @objc
    private func registrationStateDidChange() {
        AssertIsOnMainThread()
        guard tsAccountManager.registrationStateWithMaybeSneakyTransaction.isRegistered else { return }
        self.beginDownloadingIfNecessary()
    }

    public func downloadBackup(
        metadata: BackupReadCredential,
        progress: OWSProgressSink?
    ) -> Promise<URL> {
        let uuid = UUID()
        let downloadState = DownloadState(type: .backup(metadata: metadata, uuid: uuid))
        return Promise.wrapAsync {
            let maxDownloadSize = BackupArchive.Constants.maxDownloadSizeBytes
            return try await self.downloadQueue.enqueueDownload(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxDownloadSize,
                progress: progress
            )
        }
    }

    public func backupCdnInfo(
        metadata: BackupReadCredential
    ) async throws -> AttachmentDownloads.CdnInfo {
        let uuid = UUID()
        let downloadState = DownloadState(type: .backup(metadata: metadata, uuid: uuid))
        return try await self.downloadQueue.performHeadRequest(downloadState: downloadState)
    }

    public func downloadTransientAttachment(
        metadata: AttachmentDownloads.DownloadMetadata,
        progress: OWSProgressSink?
    ) -> Promise<URL> {
        return Promise.wrapAsync {
            // We want to avoid large downloads from a compromised or buggy service.
            let maxDownloadSize = RemoteConfig.current.maxAttachmentDownloadSizeBytes
            let downloadState = DownloadState(type: .transientAttachment(metadata, uuid: UUID()))

            let encryptedFileUrl = try await self.downloadQueue.enqueueDownload(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxDownloadSize,
                progress: progress
            )
            switch metadata.source {
            case .linkNSyncBackup:
                return encryptedFileUrl
            default:
                return try await self.decrypter.decryptTransientAttachment(encryptedFileUrl: encryptedFileUrl, metadata: metadata)
            }
        }
    }

    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        guard let messageRowId = message.sqliteRowId else {
            owsFailDebug("Downloading attachments for uninserted message!")
            return
        }
        var ownerTypes = AttachmentReference.MessageOwnerTypeRaw.allCases
        // Do not enqueue download of the thumbnail for quotes for which
        // we have the target message locally; the thumbnail will be filled in
        // IFF we download the original attachment.
        if
            let quotedMessage = message.quotedMessage,
            quotedMessage.bodySource == .local
        {
            ownerTypes.removeAll(where: { $0 == .quotedReplyAttachment })
        }
        let referencedAttachments = attachmentStore
            .fetchReferencedAttachments(
                owners: ownerTypes.map {
                    $0.with(messageRowId: messageRowId)
                },
                tx: tx
            )
        enqueueDownloadOfAttachments(referencedAttachments, priority: priority, tx: tx)
    }

    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        guard let storyMessageRowId = message.id else {
            owsFailDebug("Downloading attachments for uninserted message!")
            return
        }
        let referencedAttachments = attachmentStore
            .fetchReferencedAttachments(
                owners: AttachmentReference.StoryMessageOwnerTypeRaw.allCases.map {
                    $0.with(storyMessageRowId: storyMessageRowId)
                },
                tx: tx
            )
        enqueueDownloadOfAttachments(referencedAttachments, priority: priority, tx: tx)
    }

    private func enqueueDownloadOfAttachments(
        _ referencedAttachments: [ReferencedAttachment],
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        var didEnqueueAnyDownloads = false
        referencedAttachments.forEach { referencedAttachment in
            let sourceToUse: QueuedAttachmentDownloadRecord.SourceType = {
                let transitTierInfo = referencedAttachment.attachment.transitTierInfo
                let mediaTierInfo = referencedAttachment.attachment.mediaTierInfo
                guard
                    let transitTierInfo,
                    let mediaTierInfo
                else {
                    // If we don't have both there's nothing to decide
                    return mediaTierInfo == nil ? .transitTier : .mediaTierFullsize
                }
                if
                    FeatureFlags.Backups.supported,
                    mediaTierInfo.lastDownloadAttemptTimestamp == nil
                {
                    // If we've never tried media tier, always try that first.
                    return .mediaTierFullsize
                } else
                    if transitTierInfo.lastDownloadAttemptTimestamp == nil
                {
                    // If we tried media tier and failed, try transit tier
                    // next time.
                    return .transitTier
                } else {
                    // If both have failed fall back to default.
                    return FeatureFlags.Backups.supported
                        ? .mediaTierFullsize
                        : .transitTier
                }
            }()

            let downloadability = downloadabilityChecker.downloadability(
                of: referencedAttachment.reference,
                priority: priority,
                source: sourceToUse,
                mimeType: referencedAttachment.attachment.mimeType,
                tx: tx
            )
            switch downloadability {
            case .downloadable:
                didEnqueueAnyDownloads = true
                try? attachmentDownloadStore.enqueueDownloadOfAttachment(
                    withId: referencedAttachment.reference.attachmentRowId,
                    source: sourceToUse,
                    priority: priority,
                    tx: tx
                )
            case .blockedByActiveCall:
                Logger.info("Skipping enqueue of download during active call")
            case .blockedByPendingMessageRequest:
                Logger.info("Skipping enqueue of download due to pending message request")
            case .blockedByAutoDownloadSettings:
                Logger.info("Skipping enqueue of download due to auto download settings")
            case .blockedByNetworkState:
                Logger.info("Skipping enqueue of download due to network state")
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

    public func enqueueDownloadOfAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
        tx: DBWriteTransaction
    ) {
        if CurrentAppContext().isRunningTests {
            // No need to enqueue downloads if we're running tests.
            return
        }

        try? attachmentDownloadStore.enqueueDownloadOfAttachment(
            withId: id,
            source: source,
            priority: priority,
            tx: tx
        )
        tx.addSyncCompletion { [weak self] in
            self?.beginDownloadingIfNecessary()
        }
    }

    public func downloadAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
        progress: OWSProgressSink?
    ) async throws {
        if CurrentAppContext().isRunningTests {
            // No need to enqueue downloads if we're running tests.
            return
        }

        let downloadWaitingTask = Task {
            try await self.downloadQueue.waitForDownloadOfAttachment(
                id: id,
                source: source,
                progress: progress
            )
        }

        try await db.awaitableWrite { tx in
            try self.attachmentDownloadStore.enqueueDownloadOfAttachment(
                withId: id,
                source: source,
                priority: priority,
                tx: tx
            )
        }

        self.beginDownloadingIfNecessary()

        try await downloadWaitingTask.value
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
            try? attachmentDownloadStore.removeAttachmentFromQueue(
                withId: attachmentId,
                source: source,
                tx: tx
            )
        }
        self.attachmentUpdater.touchAllOwners(
            attachmentId: attachmentId,
            tx: tx
        )
    }

    public func downloadProgress(for attachmentId: Attachment.IDType, tx: DBReadTransaction) -> CGFloat? {
        return progressStates.fractionCompleted(for: attachmentId).map { CGFloat($0) }
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

        func peek(count: UInt, tx: DBReadTransaction) throws -> [DownloadTaskRecord] {
            return try store.peek(count: count, tx: tx).map {
                return .init(id: $0.id!, record: $0)
            }
        }

        func removeRecord(_ record: DownloadTaskRecord, tx: DBWriteTransaction) throws {
            try store.removeAttachmentFromQueue(
                withId: record.record.attachmentId,
                source: record.record.sourceType,
                tx: tx
            )
        }
    }

    private final class DownloadTaskRunner: TaskRecordRunner {
        typealias Store = DownloadTaskRecordStore

        private let attachmentDownloadStore: AttachmentDownloadStore
        private let attachmentStore: AttachmentStore
        private let attachmentUpdater: AttachmentUpdater
        private let backupKeyMaterial: BackupKeyMaterial
        private let backupRequestManager: BackupRequestManager
        private let dateProvider: DateProvider
        private let db: any DB
        private let decrypter: Decrypter
        private let downloadabilityChecker: DownloadabilityChecker
        private let downloadQueue: DownloadQueue
        private let remoteConfigManager: RemoteConfigManager
        private let stickerManager: Shims.StickerManager
        let store: Store
        private let tsAccountManager: TSAccountManager

        init(
            attachmentDownloadStore: AttachmentDownloadStore,
            attachmentStore: AttachmentStore,
            attachmentUpdater: AttachmentUpdater,
            backupKeyMaterial: BackupKeyMaterial,
            backupRequestManager: BackupRequestManager,
            dateProvider: @escaping DateProvider,
            db: any DB,
            decrypter: Decrypter,
            downloadQueue: DownloadQueue,
            downloadabilityChecker: DownloadabilityChecker,
            remoteConfigManager: RemoteConfigManager,
            stickerManager: Shims.StickerManager,
            tsAccountManager: TSAccountManager
        ) {
            self.attachmentDownloadStore = attachmentDownloadStore
            self.attachmentStore = attachmentStore
            self.attachmentUpdater = attachmentUpdater
            self.backupKeyMaterial = backupKeyMaterial
            self.backupRequestManager = backupRequestManager
            self.dateProvider = dateProvider
            self.db = db
            self.decrypter = decrypter
            self.downloadQueue = downloadQueue
            self.downloadabilityChecker = downloadabilityChecker
            self.remoteConfigManager = remoteConfigManager
            self.stickerManager = stickerManager
            self.store = DownloadTaskRecordStore(store: attachmentDownloadStore)
            self.tsAccountManager = tsAccountManager
        }

        // MARK: TaskRecordRunner conformance

        func runTask(
            record: DownloadTaskRecord,
            loader: TaskQueueLoader<DownloadTaskRunner>
        ) async -> TaskRecordResult {
            return await self.downloadRecord(record.record)
        }

        func didSucceed(
            record: DownloadTaskRecord,
            tx: DBWriteTransaction
        ) throws {
            Logger.info("Succeeded download of attachment \(record.record.attachmentId)")
            let downloadKey = DownloadQueue.downloadKey(record: record.record)
            Task {
                await downloadQueue.updateObservers(downloadKey: downloadKey, error: nil)
            }
        }

        func didCancel(
            record: DownloadTaskRecord,
            tx: DBWriteTransaction
        ) throws {
            Logger.info("Cancelled download of attachment \(record.record.attachmentId)")
            let downloadKey = DownloadQueue.downloadKey(record: record.record)
            Task {
                await downloadQueue.updateObservers(downloadKey: downloadKey, error: nil)
            }
        }

        func didFail(record: DownloadTaskRecord, error: Error, isRetryable: Bool, tx: DBWriteTransaction) throws {
            let record = record.record
            Logger.error("Failed download of attachment \(record.attachmentId)")
            if isRetryable, let retryTime = self.retryTime(for: record) {
                // Don't update observers; they'll be updated when the retry succeeds.
                try? self.attachmentDownloadStore.markQueuedDownloadFailed(
                    withId: record.id!,
                    minRetryTimestamp: retryTime,
                    tx: tx
                )
            } else {
                let attachment = attachmentStore.fetch(id: record.attachmentId, tx: tx)

                // If we tried to download as media tier, and failed, and we have
                // a transit tier fallback available, try downloading from that.
                let shouldReEnqueueAsTransitTier =
                    record.sourceType == .mediaTierFullsize
                    && attachment?.transitTierInfo != nil
                    // Backup restore download queue does its own fallbacks
                    && record.priority != .backupRestore

                // Not retrying; just delete the enqueued download
                try? self.attachmentDownloadStore.removeAttachmentFromQueue(
                    withId: record.attachmentId,
                    source: record.sourceType,
                    tx: tx
                )
                if error is TransitTierExpiredError {
                    Logger.info("Expiring transit tier due to failed download")
                    try? self.attachmentStore.removeTransitTierInfo(
                        forAttachmentId: record.attachmentId,
                        tx: tx
                    )
                } else if record.priority != .backupRestore {
                    // Backup restore doenload queue does its own marking of failed state.
                    try? self.attachmentStore.updateAttachmentAsFailedToDownload(
                        from: record.sourceType,
                        id: record.attachmentId,
                        timestamp: self.dateProvider().ows_millisecondsSince1970,
                        tx: tx
                    )
                }
                if shouldReEnqueueAsTransitTier {
                    try? self.attachmentDownloadStore.enqueueDownloadOfAttachment(
                        withId: record.attachmentId,
                        source: .transitTier,
                        priority: record.priority,
                        tx: tx
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
                            tx: tx
                        )
                    }
                }
            }
        }

        private struct TransitTierExpiredError: Error {}

        private func wrapDownloadError(
            error: Error,
            record: QueuedAttachmentDownloadRecord,
            attachmentBeforeDownloadAttempt: Attachment
        ) -> TaskRecordResult {

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
                    block: { attachmentStore.fetch(id: record.attachmentId, tx: $0) }
                ),
                refetchedAttachment.transitTierInfo?.cdnKey
                    == attachmentBeforeDownloadAttempt.transitTierInfo?.cdnKey,

                // Only proactively expire if the upload is old enough
                let uploadTimestamp = refetchedAttachment.transitTierInfo?.uploadTimestamp,
                uploadTimestamp < now,
                now - uploadTimestamp >= remoteConfigManager.currentConfig().messageQueueTimeMs
            {
                return .unretryableError(TransitTierExpiredError())
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
            _ record: QueuedAttachmentDownloadRecord
        ) async -> TaskRecordResult {
            guard let attachment = db.read(block: { tx in
                attachmentStore.fetch(id: record.attachmentId, tx: tx)
            }) else {
                // Because of the foreign key relationship and cascading deletes, this should
                // only happen if the attachment got deleted between when we fetched the
                // download queue record and now. Regardless, the record should now be deleted.
                owsFailDebug("Attempting to download an attachment that doesn't exist!")
                return .cancelled
            }

            guard attachment.asStream() == nil else {
                // Already a stream! No need to download.
                return .cancelled
            }

            struct SkipDownloadError: Error {}

            switch self.downloadabilityChecker.downloadability(record, attachment: attachment) {
            case .downloadable:
                break
            case .blockedByActiveCall:
                // This is a temporary setback; retry in a bit if the source allows it.
                Logger.info("Skipping attachment download due to active call \(record.attachmentId)")
                return .retryableError(SkipDownloadError())
            case .blockedByPendingMessageRequest:
                Logger.info("Skipping attachment download due to pending message request \(record.attachmentId)")
                // These can only be resolved by user action; cancel the enqueued download.
                return .unretryableError(SkipDownloadError())
            case .blockedByAutoDownloadSettings:
                Logger.info("Skipping attachment download due to auto download settings \(record.attachmentId)")
                // These can only be resolved by user action; cancel the enqueued download.
                return .unretryableError(SkipDownloadError())
            case .blockedByNetworkState:
                Logger.info("Skipping attachment download due to network state \(record.attachmentId)")
                return .unretryableError(SkipDownloadError())
            }

            Logger.info("Downloading attachment \(record.attachmentId)")

            if
                let originalAttachmentIdForQuotedReply = attachment.originalAttachmentIdForQuotedReply,
                await quoteUnquoteDownloadQuotedReplyFromOriginalStream(
                    originalAttachmentIdForQuotedReply: originalAttachmentIdForQuotedReply,
                    record: record
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

            let downloadMetadata: DownloadMetadata?
            switch record.sourceType {
            case .transitTier:
                guard let transitTierInfo = attachment.transitTierInfo else {
                    downloadMetadata = nil
                    break
                }
                downloadMetadata = .init(
                    mimeType: attachment.mimeType,
                    cdnNumber: transitTierInfo.cdnNumber,
                    encryptionKey: transitTierInfo.encryptionKey,
                    source: .transitTier(
                        cdnKey: transitTierInfo.cdnKey,
                        integrityCheck: transitTierInfo.integrityCheck,
                        plaintextLength: transitTierInfo.unencryptedByteCount
                    )
                )
            case .mediaTierFullsize:
                let cdnNumber = attachment.mediaTierInfo?.cdnNumber ?? remoteConfigManager.currentConfig().mediaTierFallbackCdnNumber
                guard
                    let mediaTierInfo = attachment.mediaTierInfo,
                    let mediaName = attachment.mediaName,
                    let encryptionMetadata = buildCdnEncryptionMetadata(mediaName: mediaName, type: .outerLayerFullsizeOrThumbnail),
                    let cdnCredential = await fetchBackupCdnReadCredential(for: cdnNumber)
                else {
                    downloadMetadata = nil
                    break
                }
                let integrityCheck = AttachmentIntegrityCheck.sha256ContentHash(mediaTierInfo.sha256ContentHash)
                downloadMetadata = .init(
                    mimeType: attachment.mimeType,
                    cdnNumber: cdnNumber,
                    encryptionKey: attachment.encryptionKey,
                    source: .mediaTierFullsize(
                        cdnReadCredential: cdnCredential,
                        outerEncryptionMetadata: encryptionMetadata,
                        integrityCheck: integrityCheck,
                        plaintextLength: mediaTierInfo.unencryptedByteCount
                    )
                )
            case .mediaTierThumbnail:
                let cdnNumber = attachment.thumbnailMediaTierInfo?.cdnNumber ?? remoteConfigManager.currentConfig().mediaTierFallbackCdnNumber
                guard
                    attachment.thumbnailMediaTierInfo != nil || MimeTypeUtil.isSupportedVisualMediaMimeType(attachment.mimeType),
                    let mediaName = attachment.mediaName,
                    // This is the outer encryption
                    let outerEncryptionMetadata = buildCdnEncryptionMetadata(
                        mediaName: AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName),
                        type: .outerLayerFullsizeOrThumbnail
                    ),
                    // inner encryption
                    let innerEncryptionMetadata = buildCdnEncryptionMetadata(
                        mediaName: AttachmentBackupThumbnail.thumbnailMediaName(fullsizeMediaName: mediaName),
                        type: .transitTierThumbnail
                    ),
                    let cdnReadCredential = await fetchBackupCdnReadCredential(for: cdnNumber)
                else {
                    downloadMetadata = nil
                    break
                }

                downloadMetadata = .init(
                    mimeType: attachment.mimeType,
                    cdnNumber: cdnNumber,
                    encryptionKey: attachment.encryptionKey,
                    source: .mediaTierThumbnail(
                        cdnReadCredential: cdnReadCredential,
                        outerEncyptionMetadata: outerEncryptionMetadata,
                        innerEncryptionMetadata: innerEncryptionMetadata
                    )
                )
            }

            guard let downloadMetadata else {
                return .unretryableError(OWSAssertionError("Attempting to download an attachment without cdn info"))
            }

            let downloadedFileUrl: URL
            do {
                downloadedFileUrl = try await downloadQueue.enqueueDownload(
                    downloadState: .init(type: .attachment(downloadMetadata, id: attachment.id)),
                    maxDownloadSizeBytes: RemoteConfig.current.maxAttachmentDownloadSizeBytes,
                    progress: nil
                )
            } catch let error {
                Logger.error("Failed to download: \(error)")
                return wrapDownloadError(
                    error: error,
                    record: record,
                    attachmentBeforeDownloadAttempt: attachment
                )
            }

            let pendingAttachment: PendingAttachment
            do {
                pendingAttachment = try await decrypter.validateAndPrepare(
                    encryptedFileUrl: downloadedFileUrl,
                    metadata: downloadMetadata
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
                    timestamp: dateProvider().ows_millisecondsSince1970
                )
            } catch let error {
                return .retryableError(OWSAssertionError("Failed to update attachment: \(error)"))
            }

            if case .stream(let attachmentStream) = result {
                do {
                    try await attachmentUpdater.copyThumbnailForQuotedReplyIfNeeded(
                        attachmentStream
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
            record: QueuedAttachmentDownloadRecord
        ) async -> Bool {
            let originalAttachmentStream = db.read { tx in
                attachmentStore.fetch(id: originalAttachmentIdForQuotedReply, tx: tx)?.asStream()
            }
            guard let originalAttachmentStream else {
                return false
            }
            do {
                try await attachmentUpdater.copyThumbnailForQuotedReplyIfNeeded(
                    originalAttachmentStream
                )
                return true
            } catch let error {
                Logger.error("Failed to update thumbnails: \(error)")
                return false
            }
        }

        private nonisolated func quoteUnquoteDownloadStickerFromInstalledPackIfPossible(
            record: QueuedAttachmentDownloadRecord
        ) async -> Bool {
            let installedSticker: InstalledSticker? = db.read { tx in
                var stickerMetadata: AttachmentReference.Owner.MessageSource.StickerMetadata?
                try? attachmentStore.enumerateAllReferences(
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
                    }
                )
                guard let stickerMetadata else {
                    return nil
                }
                return self.stickerManager.fetchInstalledSticker(
                    packId: stickerMetadata.stickerPackId,
                    stickerId: stickerMetadata.stickerId,
                    tx: tx
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
                    pendingAttachment: pendingAttachment
                )
            } catch let error {
                Logger.error("Failed to update attachment: \(error)")
                return false
            }

            do {
                try await attachmentUpdater.copyThumbnailForQuotedReplyIfNeeded(
                    attachmentStream
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
            type: MediaTierEncryptionType
        ) -> MediaTierEncryptionMetadata? {
            guard let mediaEncryptionMetadata = try? db.read(block: { tx in
                try backupKeyMaterial.mediaEncryptionMetadata(
                    mediaName: mediaName,
                    type: type,
                    tx: tx
                )
            }) else {
                owsFailDebug("Failed to build backup media metadata")
                return nil
            }
            return mediaEncryptionMetadata
        }

        private func fetchBackupCdnReadCredential(for cdn: UInt32) async -> MediaTierReadCredential? {
            guard let localAci = db.read(block: { tx in
                self.tsAccountManager.localIdentifiers(tx: tx)?.aci
            }) else {
                owsFailDebug("Missing local identifier")
                return nil
            }

            guard let auth = try? await backupRequestManager.fetchBackupServiceAuth(
                for: .media,
                localAci: localAci,
                auth: .implicit()
            ) else {
                owsFailDebug("Failed to fetch backup credential")
                return nil
            }

            guard let metadata = try? await backupRequestManager.fetchMediaTierCdnRequestMetadata(
                cdn: Int32(cdn),
                auth: auth
            ) else {
                owsFailDebug("Failed to fetch backup credential")
                return nil
            }

            return metadata
        }
    }

    // MARK: - Downloadability

    private class DownloadabilityChecker {

        private let attachmentStore: AttachmentStore
        private let currentCallProvider: CurrentCallProvider
        private let db: any DB
        private let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
        private let profileManager: Shims.ProfileManager
        private let threadStore: ThreadStore

        init(
            attachmentStore: AttachmentStore,
            currentCallProvider: CurrentCallProvider,
            db: any DB,
            mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
            profileManager: Shims.ProfileManager,
            threadStore: ThreadStore
        ) {
            self.attachmentStore = attachmentStore
            self.currentCallProvider = currentCallProvider
            self.db = db
            self.mediaBandwidthPreferenceStore = mediaBandwidthPreferenceStore
            self.profileManager = profileManager
            self.threadStore = threadStore
        }

        enum Downloadability: Equatable {
            case downloadable
            case blockedByActiveCall
            case blockedByPendingMessageRequest
            case blockedByAutoDownloadSettings
            case blockedByNetworkState
        }

        func downloadability(
            _ record: QueuedAttachmentDownloadRecord,
            attachment: Attachment
        ) -> Downloadability {
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

                try? self.attachmentStore.enumerateAllReferences(
                    toAttachmentId: record.attachmentId,
                    tx: tx
                ) { reference, stop in
                    downloadability = self.downloadability(
                        of: reference,
                        priority: record.priority,
                        source: record.sourceType,
                        mimeType: attachment.mimeType,
                        tx: tx
                    )
                    // If one reference marks it downloadable, don't check further ones.
                    if downloadability == .downloadable {
                        stop = true
                    }
                }
                guard let downloadability else {
                    owsFailDebug("Downloading attachment with no references")
                    return .downloadable
                }
                return downloadability
            }
        }

        func downloadability(
            of reference: AttachmentReference,
            priority: AttachmentDownloadPriority,
            source: QueuedAttachmentDownloadRecord.SourceType,
            mimeType: String,
            tx: DBReadTransaction
        ) -> Downloadability {

            let blockedByCall = self.isDownloadBlockedByActiveCall(
                priority: priority,
                owner: reference.owner,
                tx: tx
            )
            if blockedByCall {
                return .blockedByActiveCall
            }

            if !self.mediaBandwidthPreferenceStore.downloadableSources().contains(source) {
                return .blockedByNetworkState
            }

            let blockedByAutoDownloadSettings = self.isDownloadBlockedByAutoDownloadSettings(
                priority: priority,
                owner: reference.owner,
                renderingFlag: reference.renderingFlag,
                mimeType: mimeType,
                tx: tx
            )
            if blockedByAutoDownloadSettings {
                return .blockedByAutoDownloadSettings
            }

            let blockedByPendingMessageRequest = self.isDownloadBlockedByPendingMessageRequest(
                priority: priority,
                owner: reference.owner,
                tx: tx
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
            tx: DBReadTransaction
        ) -> Bool {
            switch priority {
            case .userInitiated, .localClone:
                // Always download at these priorities.
                return false
            case .default, .backupRestore:
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
            owner: AttachmentReference.Owner,
            tx: DBReadTransaction
        ) -> Bool {
            switch priority {
            case .userInitiated, .localClone:
                // Always download at these priorities.
                return false
            case .default, .backupRestore:
                break
            }

            let threadRowId: Int64
            switch owner {
            case .message(.oversizeText), .message(.sticker):
                return false
            case  .message(.bodyAttachment(let metadata)):
                threadRowId = metadata.threadRowId
            case .message(.quotedReply(let metadata)):
                threadRowId = metadata.threadRowId
            case .message(.linkPreview(let metadata)):
                threadRowId = metadata.threadRowId
            case .message(.contactAvatar(let metadata)):
                threadRowId = metadata.threadRowId

            case .storyMessage, .thread:
                // Ignore non-message cases for purposes of pending message request.
                return false
            }

            // If there's not a thread, err on the safe side and don't download it.
            guard let thread = threadStore.fetchThread(rowId: threadRowId, tx: tx) else {
                return true
            }

            // If the message that created this attachment was the first message in the
            // thread, the thread may not yet be marked visible. In that case, just
            // check if the thread is whitelisted. We know we just received a message.
            // TODO: Mark the thread visible before this point to share more logic.
            guard thread.shouldThreadBeVisible else {
                return !profileManager.isThread(inProfileWhitelist: thread, tx: tx)
            }

            return threadStore.hasPendingMessageRequest(thread: thread, tx: tx)
        }

        private func isDownloadBlockedByAutoDownloadSettings(
            priority: AttachmentDownloadPriority,
            owner: AttachmentReference.Owner,
            renderingFlag: AttachmentReference.RenderingFlag,
            mimeType: String,
            tx: DBReadTransaction
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
                } else if MimeTypeUtil.isSupportedVideoMimeType(mimeType) {
                    return !autoDownloadableMediaTypes.contains(.video)
                } else if MimeTypeUtil.isSupportedAudioMimeType(mimeType) {
                    if renderingFlag == .voiceMessage {
                        return false
                    } else {
                        return !autoDownloadableMediaTypes.contains(.audio)
                    }
                } else {
                    return !autoDownloadableMediaTypes.contains(.document)
                }
            case .message(.oversizeText):
                return false
            case .message(.sticker):
                return !autoDownloadableMediaTypes.contains(.photo)
            case
                    .message(.quotedReply),
                    .message(.linkPreview), .storyMessage(.textStoryLinkPreview),
                    .message(.contactAvatar):
                return false
            case .thread(.threadWallpaperImage), .thread(.globalThreadWallpaperImage):
                return false
            }
        }
    }

    // MARK: - Downloads

    typealias DownloadMetadata = AttachmentDownloads.DownloadMetadata

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
                case .transitTier(let cdnKey, _, _), .linkNSyncBackup(let cdnKey):
                    guard let encodedKey = cdnKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                        throw OWSAssertionError("Invalid cdnKey.")
                    }
                    return "attachments/\(encodedKey)"
                case
                        .mediaTierFullsize(let cdnCredential, let outerEncryptionMetadata, _, _),
                        .mediaTierThumbnail(let cdnCredential, let outerEncryptionMetadata, _):
                    let prefix = cdnCredential.mediaTierUrlPrefix()
                    return "\(prefix)/\(outerEncryptionMetadata.mediaId.asBase64Url)"
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
                case .transitTier, .linkNSyncBackup:
                    return [:]
                case .mediaTierFullsize(let cdnCredential, _, _, _), .mediaTierThumbnail(let cdnCredential, _, _):
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
                case .transitTier, .linkNSyncBackup:
                    return false
                case .mediaTierFullsize(let cdnCredential, _, _, _), .mediaTierThumbnail(let cdnCredential, _, _):
                    return cdnCredential.isExpired
                }
            }
        }
    }

    private class DownloadState {
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
    }

    private final class ProgressStates: Sendable {
        private struct States {
            var states: [Attachment.IDType: Double] = [:]
            var cancelledAttachmentIds: Set<Attachment.IDType> = []
        }

        private let states = TSMutex(initialState: States())

        func fractionCompleted(for attachmentId: Attachment.IDType) -> Double? {
            states.withLock { $0.states[attachmentId] }
        }

        func setFractionCompleted(_ fractionComplete: Double, for attachmentId: Attachment.IDType) {
            states.withLock { $0.states[attachmentId] = fractionComplete }
        }

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

        init(
            progressStates: ProgressStates,
            signalService: OWSSignalServiceProtocol
        ) {
            self.progressStates = progressStates
            self.signalService = signalService
        }

        private let maxConcurrentDownloads = 4
        private var concurrentDownloads = 0
        private var queue = [CheckedContinuation<Void, Error>]()

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

        func waitForDownloadOfAttachment(
            id: Attachment.IDType,
            source: QueuedAttachmentDownloadRecord.SourceType,
            progress: OWSProgressSink?
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

        static nonisolated func downloadKey(record: QueuedAttachmentDownloadRecord) -> DownloadKey {
            return DownloadKey(id: record.attachmentId, source: record.sourceType)
        }

        private static nonisolated func downloadKey(state: DownloadState) -> DownloadKey? {
            switch state.type {
            case .backup, .transientAttachment:
                return nil
            case .attachment(let downloadMetadata, let id):
                return DownloadKey(id: id, source: downloadMetadata.source.asQueuedDownloadSource)
            }
        }

        fileprivate func performHeadRequest(
            downloadState: DownloadState
        ) async throws -> AttachmentDownloads.CdnInfo {
            let urlSession = self.signalService.urlSessionForCdn(
                cdnNumber: downloadState.cdnNumber(),
                maxResponseSize: BackupArchive.Constants.maxDownloadSizeBytes
            )
            let urlPath = try downloadState.urlPath()
            var headers = downloadState.additionalHeaders()
            headers["Content-Type"] = MimeType.applicationOctetStream.rawValue

            // Perform a HEAD request to get the byte length & last modified date from cdn.
            let request = try urlSession.endpoint.buildRequest(urlPath, method: .head, headers: headers)
            let response = try await urlSession.performRequest(request: request, ignoreAppExpiry: true)
            guard
                let contentLengthRaw = response.headers["Content-Length"],
                let contentLengthBytes = UInt(contentLengthRaw)
            else {
                Logger.error("Missing content length from cdn")
                throw OWSUnretryableError()
            }

            guard
                let lastModifiedRaw = response.headers["Last-Modified"],
                let lastModifiedDate = Date.ows_parseFromHTTPDateString(lastModifiedRaw)
            else {
                Logger.error("Missing last modified from cdn")
                throw OWSUnretryableError()
            }
            return AttachmentDownloads.CdnInfo(
                contentLength: contentLengthBytes,
                lastModified: lastModifiedDate
            )
        }

        func enqueueDownload(
            downloadState: DownloadState,
            maxDownloadSizeBytes: UInt,
            progress: OWSProgressSink?
        ) async throws -> URL {
            let progresses = (
                [progress]
                + (
                    Self.downloadKey(state: downloadState)
                        .map({ self.downloadProgresses[$0] ?? [] })
                    ?? []
                )
            ).compacted()

            try Task.checkCancellation()

            try await withCheckedThrowingContinuation { continuation in
                queue.append(continuation)
                runNextQueuedDownloadIfPossible()
            }

            defer {
                concurrentDownloads -= 1
                runNextQueuedDownloadIfPossible()
            }
            try Task.checkCancellation()
            return try await performDownloadAttempt(
                downloadState: downloadState,
                progresses: progresses,
                progressSources: nil,
                maxDownloadSizeBytes: maxDownloadSizeBytes,
                resumeData: nil,
                attemptCount: 0
            )
        }

        private func runNextQueuedDownloadIfPossible() {
            if queue.isEmpty || concurrentDownloads >= maxConcurrentDownloads { return }

            concurrentDownloads += 1
            let continuation = queue.removeFirst()
            continuation.resume()
        }

        private struct ResumeData {
            let expectedDownloadSizeBytes: UInt?
            let data: Data?
        }

        private nonisolated func performDownloadAttempt(
            downloadState: DownloadState,
            progresses: [OWSProgressSink],
            progressSources inputProgressSources: [OWSProgressSource]?,
            maxDownloadSizeBytes: UInt,
            resumeData: ResumeData?,
            attemptCount: UInt
        ) async throws -> URL {
            guard downloadState.isExpired().negated else {
                throw AttachmentDownloads.Error.expiredCredentials
            }

            let urlSession = self.signalService.urlSessionForCdn(
                cdnNumber: downloadState.cdnNumber(),
                maxResponseSize: maxDownloadSizeBytes
            )
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

            var expectedDownloadSizeBytes: UInt? = resumeData?.expectedDownloadSizeBytes
            var progressSources: [OWSProgressSource] = []

            do {
                var downloadTask: Task<OWSUrlDownloadResponse, Error>?

                if let inputProgressSources {
                    progressSources = inputProgressSources
                } else if let expectedDownloadSizeBytes {
                    for progress in progresses {
                        progressSources.append(await progress.addSource(
                            withLabel: AttachmentDownloads.downloadProgressLabel,
                            unitCount: UInt64(expectedDownloadSizeBytes)
                        ))
                    }
                } else {
                    // Perform a HEAD request just to get the byte length from cdn.
                    let downloadInfo = try await performHeadRequest(downloadState: downloadState)
                    expectedDownloadSizeBytes = downloadInfo.contentLength
                    for progress in progresses {
                        progressSources.append(await progress.addSource(
                            withLabel: AttachmentDownloads.downloadProgressLabel,
                            unitCount: UInt64(downloadInfo.contentLength)
                        ))
                    }
                }

                let wrappedProgress = OWSProgress.createSink { progressValue in
                    for progressSource in progressSources {
                        if progressSource.completedUnitCount < progressValue.completedUnitCount {
                            progressSource.incrementCompletedUnitCount(by: progressValue.completedUnitCount - progressSource.completedUnitCount)
                        }
                    }
                    self.handleDownloadProgress(
                        downloadState: downloadState,
                        task: downloadTask,
                        progress: progressValue,
                        expectedDownloadSizeBytes: expectedDownloadSizeBytes,
                        attachmentId: attachmentId
                    )
                }
                let wrappedProgressSource = await wrappedProgress.addSource(
                    withLabel: "source",
                    unitCount: UInt64(expectedDownloadSizeBytes ?? maxDownloadSizeBytes)
                )

                let downloadResponse: OWSUrlDownloadResponse
                if let resumeData = resumeData?.data {
                    let request = try urlSession.endpoint.buildRequest(urlPath, method: .get, headers: headers)
                    guard let requestUrl = request.url else {
                        throw OWSAssertionError("Request missing url.")
                    }
                    downloadTask = Task {
                        return try await urlSession.performDownload(
                            requestUrl: requestUrl,
                            resumeData: resumeData,
                            progress: wrappedProgressSource
                        )
                    }
                    downloadResponse = try await downloadTask!.value
                } else {
                    downloadTask = Task {
                         return try await urlSession.performDownload(
                            urlPath,
                            method: .get,
                            headers: headers,
                            progress: wrappedProgressSource
                        )
                    }
                    downloadResponse = try await downloadTask!.value
                }
                let downloadUrl = downloadResponse.downloadUrl
                guard let fileSize = OWSFileSystem.fileSize(of: downloadUrl) else {
                    throw OWSAssertionError("Could not determine attachment file size.")
                }
                guard fileSize.int64Value <= maxDownloadSizeBytes else {
                    throw OWSGenericError("Attachment download length exceeds max size.")
                }
                let tmpFile = OWSFileSystem.temporaryFileUrl()
                try OWSFileSystem.copyFile(from: downloadUrl, to: tmpFile)
                return tmpFile
            } catch let error {
                Logger.warn("Error: \(error)")

                let maxAttemptCount = 16
                guard
                    error.isNetworkFailureOrTimeout,
                    attemptCount < maxAttemptCount
                else {
                    throw error
                }

                // Wait briefly before retrying.
                try await Task.sleep(nanoseconds: 250 * NSEC_PER_MSEC)

                let newResumeData = (error as NSError)
                    .userInfo[NSURLSessionDownloadTaskResumeData]
                    .map { $0 as? Data }
                    .map(\.?.nilIfEmpty)
                    ?? nil
                return try await self.performDownloadAttempt(
                    downloadState: downloadState,
                    progresses: progresses,
                    progressSources: progressSources,
                    maxDownloadSizeBytes: maxDownloadSizeBytes,
                    resumeData: .init(
                        expectedDownloadSizeBytes: expectedDownloadSizeBytes,
                        data: newResumeData
                    ),
                    attemptCount: attemptCount + 1
                )
            }
        }

        private nonisolated func handleDownloadProgress(
            downloadState: DownloadState,
            task: Task<OWSUrlDownloadResponse, Error>?,
            progress: OWSProgress,
            expectedDownloadSizeBytes: UInt?,
            attachmentId: Attachment.IDType?
        ) {
            if let attachmentId, progressStates.consumeCancellation(of: attachmentId) {
                Logger.info("Cancelling download.")
                // Cancelling will inform the URLSessionTask delegate.
                task?.cancel()
                return
            }

            // Use a slightly non-zero value to ensure that the progress
            // indicator shows up as quickly as possible.
            let progressTheta: Double = 0.001

            let fractionCompleted: Double
            if progress.completedUnitCount > 0 {
                fractionCompleted = max(progressTheta, Double(progress.percentComplete))
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
                progressStates.setFractionCompleted(fractionCompleted, for: attachmentId)

                NotificationCenter.default.postOnMainThread(
                    name: AttachmentDownloads.attachmentDownloadProgressNotification,
                    object: nil,
                    userInfo: [
                        AttachmentDownloads.attachmentDownloadProgressKey: NSNumber(value: fractionCompleted),
                        AttachmentDownloads.attachmentDownloadAttachmentIDKey: attachmentId
                    ]
                )
            }
        }
    }

    private class Decrypter {

        private let attachmentValidator: AttachmentContentValidator
        private let stickerManager: Shims.StickerManager

        init(
            attachmentValidator: AttachmentContentValidator,
            stickerManager: Shims.StickerManager
        ) {
            self.attachmentValidator = attachmentValidator
            self.stickerManager = stickerManager
        }

        // Use concurrent=1 queue to ensure that we only load into memory
        // & decrypt a single attachment at a time.
        private let decryptionQueue = ConcurrentTaskQueue(concurrentLimit: 1)

        func decryptTransientAttachment(
            encryptedFileUrl: URL,
            metadata: DownloadMetadata
        ) async throws -> URL {
            return try await decryptionQueue.run {
                do {
                    // Transient attachments decrypt to a tmp file.
                    let outputUrl = OWSFileSystem.temporaryFileUrl()

                    try Cryptography.decryptAttachment(
                        at: encryptedFileUrl,
                        metadata: DecryptionMetadata(
                            key: metadata.encryptionKey,
                            integrityCheck: metadata.integrityCheck,
                            plaintextLength: metadata.plaintextLength.map(Int.init)
                        ),
                        output: outputUrl
                    )

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
            _ sticker: InstalledSticker
        ) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            let stickerManager = self.stickerManager
            return try await decryptionQueue.run {
                // AttachmentValidator runs synchronously _and_ opens write transactions
                // internally. We can't block on the write lock in the cooperative thread
                // pool, so bridge out of structured concurrency to run the validation.
                return try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global().async {
                        do {
                            guard let stickerDataUrl = stickerManager.stickerDataUrl(
                                forInstalledSticker: sticker,
                                verifyExists: true
                            ) else {
                                throw OWSAssertionError("Missing sticker")
                            }

                            let mimeType: String
                            let imageMetadata = Data.imageMetadata(withPath: stickerDataUrl.path, mimeType: nil)
                            if imageMetadata.imageFormat != .unknown,
                               let mimeTypeFromMetadata = imageMetadata.mimeType {
                                mimeType = mimeTypeFromMetadata
                            } else {
                                mimeType = MimeType.imageWebp.rawValue
                            }

                            let pendingAttachment = try attachmentValidator.validateContents(
                                dataSource: DataSourcePath(
                                    fileUrl: stickerDataUrl,
                                    shouldDeleteOnDeallocation: false
                                ),
                                shouldConsume: false,
                                mimeType: mimeType,
                                renderingFlag: .borderless,
                                sourceFilename: nil
                            )
                            continuation.resume(with: .success(pendingAttachment))
                        } catch let error {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }

        func validateAndPrepare(
            encryptedFileUrl: URL,
            metadata: DownloadMetadata
        ) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            return try await decryptionQueue.run {
                // AttachmentValidator runs synchronously _and_ opens write transactions
                // internally. We can't block on the write lock in the cooperative thread
                // pool, so bridge out of structured concurrency to run the validation.
                return try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global().async {
                        do {
                            let pendingAttachment: PendingAttachment
                            switch metadata.source {
                            case .transitTier(_, let integrityCheck, let plaintextLength):
                                pendingAttachment = try attachmentValidator.validateDownloadedContents(
                                    ofEncryptedFileAt: encryptedFileUrl,
                                    encryptionKey: metadata.encryptionKey,
                                    plaintextLength: plaintextLength,
                                    integrityCheck: integrityCheck,
                                    mimeType: metadata.mimeType,
                                    renderingFlag: .default,
                                    sourceFilename: nil
                                )
                            case .mediaTierFullsize(_, let outerEncryptionMetadata, let integrityCheck, let plaintextLength):
                                let innerPlaintextLength: Int? = {
                                    guard let plaintextLength else { return nil }
                                    return Int(plaintextLength)
                                }()

                                pendingAttachment = try attachmentValidator.validateContents(
                                    ofBackupMediaFileAt: encryptedFileUrl,
                                    outerDecryptionData: DecryptionMetadata(key: outerEncryptionMetadata.encryptionKey),
                                    innerDecryptionData: DecryptionMetadata(
                                        key: metadata.encryptionKey,
                                        integrityCheck: integrityCheck,
                                        plaintextLength: innerPlaintextLength
                                    ),
                                    finalEncryptionKey: metadata.encryptionKey,
                                    mimeType: metadata.mimeType,
                                    renderingFlag: .default,
                                    sourceFilename: nil
                                )
                            case .mediaTierThumbnail(_, let outerEncryptionMetadata, let innerEncryptionData):
                                pendingAttachment = try attachmentValidator.validateContents(
                                    ofBackupMediaFileAt: encryptedFileUrl,
                                    outerDecryptionData: DecryptionMetadata(key: outerEncryptionMetadata.encryptionKey),
                                    innerDecryptionData: DecryptionMetadata(key: innerEncryptionData.encryptionKey),
                                    finalEncryptionKey: metadata.encryptionKey,
                                    mimeType: metadata.mimeType,
                                    renderingFlag: .default,
                                    sourceFilename: nil
                                )
                            case .linkNSyncBackup:
                                throw OWSAssertionError("Should not be validating link'n'sync backups")
                            }
                            continuation.resume(with: .success(pendingAttachment))
                        } catch let error {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }

        func prepareQuotedReplyThumbnail(originalAttachmentStream: AttachmentStream) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            return try await decryptionQueue.run {
                // AttachmentValidator runs synchronously _and_ opens write transactions
                // internally. We can't block on the write lock in the cooperative thread
                // pool, so bridge out of structured concurrency to run the validation.
                return try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global().async {
                        do {
                            let pendingAttachment = try attachmentValidator.prepareQuotedReplyThumbnail(
                                fromOriginalAttachmentStream: originalAttachmentStream
                            )
                            continuation.resume(with: .success(pendingAttachment))
                        } catch let error {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }
        }
    }

    private class AttachmentUpdater {

        private let attachmentStore: AttachmentStore
        private let backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner
        private let backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler
        private let db: any DB
        private let decrypter: Decrypter
        private let interactionStore: InteractionStore
        private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
        private let orphanedAttachmentStore: OrphanedAttachmentStore
        private let orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager
        private let storyStore: StoryStore
        private let threadStore: ThreadStore

        public init(
            attachmentStore: AttachmentStore,
            backupAttachmentUploadQueueRunner: BackupAttachmentUploadQueueRunner,
            backupAttachmentUploadScheduler: BackupAttachmentUploadScheduler,
            db: any DB,
            decrypter: Decrypter,
            interactionStore: InteractionStore,
            orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
            orphanedAttachmentStore: OrphanedAttachmentStore,
            orphanedBackupAttachmentManager: OrphanedBackupAttachmentManager,
            storyStore: StoryStore,
            threadStore: ThreadStore
        ) {
            self.attachmentStore = attachmentStore
            self.backupAttachmentUploadQueueRunner = backupAttachmentUploadQueueRunner
            self.backupAttachmentUploadScheduler = backupAttachmentUploadScheduler
            self.db = db
            self.decrypter = decrypter
            self.interactionStore = interactionStore
            self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
            self.orphanedAttachmentStore = orphanedAttachmentStore
            self.orphanedBackupAttachmentManager = orphanedBackupAttachmentManager
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
                guard let attachmentWeJustDownloaded = self.attachmentStore.fetch(id: attachmentId, tx: tx) else {
                    Logger.error("Missing attachment after download; could have been deleted while downloading.")
                    throw OWSUnretryableError()
                }
                if let stream = attachmentWeJustDownloaded.asStream() {
                    // Its already a stream?
                    return .stream(stream)
                }

                let mediaName = Attachment.mediaName(
                    sha256ContentHash: pendingAttachment.sha256ContentHash,
                    encryptionKey: pendingAttachment.encryptionKey
                )
                let streamInfo = Attachment.StreamInfo(
                    sha256ContentHash: pendingAttachment.sha256ContentHash,
                    mediaName: mediaName,
                    encryptedByteCount: pendingAttachment.encryptedByteCount,
                    unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                    contentType: pendingAttachment.validatedContentType,
                    digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                    localRelativeFilePath: pendingAttachment.localRelativeFilePath
                )

                do {
                    guard self.orphanedAttachmentStore.orphanAttachmentExists(with: pendingAttachment.orphanRecordId, tx: tx) else {
                        throw OWSAssertionError("Attachment file deleted before creation")
                    }

                    // Try and update the attachment.
                    try self.attachmentStore.updateAttachmentAsDownloaded(
                        from: source,
                        priority: priority,
                        id: attachmentId,
                        validatedMimeType: pendingAttachment.mimeType,
                        streamInfo: streamInfo,
                        timestamp: timestamp,
                        tx: tx
                    )
                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingAttachment.orphanRecordId, tx: tx)

                    self.orphanedBackupAttachmentManager.didCreateOrUpdateAttachment(
                        withMediaName: mediaName,
                        tx: tx
                    )

                    let attachment = self.attachmentStore.fetch(id: attachmentId, tx: tx)

                    if let attachment {
                        switch source {
                        case .transitTier:
                            // After we download an attachment and verify its digest, we can
                            // schedule it for "upload" to the media (backup) tier. "Upload"
                            // really means "copy from transit tier" and since we just downloaded
                            // we shouldn't need to reupload to do that; we just needed to verify
                            // the digest before copying.
                            try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                                attachment,
                                tx: tx
                            )
                            backupAttachmentUploadQueueRunner.backUpAllAttachmentsAfterTxCommits(tx: tx)
                        case .mediaTierFullsize, .mediaTierThumbnail:
                            break
                        }
                    }

                    let result: DownloadResult
                    switch source {
                    case .transitTier, .mediaTierFullsize:
                        guard let stream = attachment?.asStream() else {
                            throw OWSAssertionError("Not a stream")
                        }
                        result = .stream(stream)
                    case .mediaTierThumbnail:
                        guard let thumbnail = attachment?.asBackupThumbnail() else {
                            throw OWSAssertionError("Not a thumbnail")
                        }
                        result = .thumbnail(thumbnail)
                    }

                    tx.addSyncCompletion { [weak self] in
                        guard let self else { return }
                        self.db.asyncWrite { tx in
                            self.touchAllOwners(attachmentId: attachmentId, tx: tx)
                        }
                    }

                    return result

                } catch let error {
                    let existingAttachmentId: Attachment.IDType
                    if let error = error as? AttachmentInsertError {
                        existingAttachmentId = try AttachmentManagerImpl.handleAttachmentInsertError(
                            error,
                            pendingAttachmentStreamInfo: streamInfo,
                            pendingAttachmentEncryptionKey: pendingAttachment.encryptionKey,
                            pendingAttachmentMimeType: pendingAttachment.mimeType,
                            pendingAttachmentOrphanRecordId: pendingAttachment.orphanRecordId,
                            pendingAttachmentTransitTierInfo: attachmentWeJustDownloaded.transitTierInfo,
                            attachmentStore: attachmentStore,
                            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
                            orphanedAttachmentStore: orphanedAttachmentStore,
                            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
                            tx: tx
                        )
                        backupAttachmentUploadQueueRunner.backUpAllAttachmentsAfterTxCommits(tx: tx)
                    } else {
                        throw error
                    }

                    // Already have an attachment with the same plaintext hash or media name!
                    // Move all existing references to that copy, instead.
                    // Doing so should delete the original attachment pointer.

                    // Just hold all refs in memory; there shouldn't in practice be
                    // so many pointers to the same attachment.
                    var references = [AttachmentReference]()
                    try self.attachmentStore.enumerateAllReferences(
                        toAttachmentId: attachmentId,
                        tx: tx
                    ) { reference, _ in
                        references.append(reference)
                    }
                    try references.forEach { reference in
                        try self.attachmentStore.removeOwner(
                            reference: reference,
                            tx: tx
                        )
                        let newOwnerParams = AttachmentReference.ConstructionParams(
                            owner: reference.owner.forReassignmentWithContentType(pendingAttachment.validatedContentType.raw),
                            sourceFilename: reference.sourceFilename,
                            sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
                            sourceMediaSizePixels: reference.sourceMediaSizePixels
                        )
                        try self.attachmentStore.addOwner(
                            newOwnerParams,
                            for: existingAttachmentId,
                            tx: tx
                        )
                    }

                    guard let stream = self.attachmentStore.fetch(id: existingAttachmentId, tx: tx)?.asStream() else {
                        throw OWSAssertionError("Not a stream")
                    }

                    let attachmentId = stream.attachment.id
                    tx.addSyncCompletion { [weak self] in
                        guard let self else { return }
                        self.db.asyncWrite { tx in
                            self.touchAllOwners(attachmentId: attachmentId, tx: tx)
                        }
                    }

                    return .stream(stream)
                }
            }
        }

        func updateAttachmentFromInstalledSticker(
            attachmentId: Attachment.IDType,
            pendingAttachment: PendingAttachment
        ) async throws -> AttachmentStream {
            return try await db.awaitableWrite { tx -> AttachmentStream in
                guard let existingAttachment = self.attachmentStore.fetch(id: attachmentId, tx: tx) else {
                    Logger.error("Missing attachment after download; could have been deleted while downloading.")
                    throw OWSUnretryableError()
                }
                if let stream = existingAttachment.asStream() {
                    // Its already a stream?
                    return stream
                }

                var references = [AttachmentReference]()
                try self.attachmentStore.enumerateAllReferences(
                    toAttachmentId: attachmentId,
                    tx: tx
                ) { reference, _ in
                    references.append(reference)
                }
                // Arbitrarily pick the first reference as the one we will use as the initial ref to
                // the new stream. The others' references will be re-pointed to the new stream afterwards.
                guard let firstReference = references.first else {
                    throw OWSAssertionError("Attachments should never have zero references")
                }

                try self.attachmentStore.removeOwner(
                    reference: firstReference,
                    tx: tx
                )

                let mediaName = Attachment.mediaName(
                    sha256ContentHash: pendingAttachment.sha256ContentHash,
                    encryptionKey: pendingAttachment.encryptionKey
                )
                let streamInfo = Attachment.StreamInfo(
                    sha256ContentHash: pendingAttachment.sha256ContentHash,
                    mediaName: mediaName,
                    encryptedByteCount: pendingAttachment.encryptedByteCount,
                    unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                    contentType: pendingAttachment.validatedContentType,
                    digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                    localRelativeFilePath: pendingAttachment.localRelativeFilePath
                )

                let alreadyAssignedFirstReference: Bool

                let newAttachment: AttachmentStream
                do {
                    guard self.orphanedAttachmentStore.orphanAttachmentExists(with: pendingAttachment.orphanRecordId, tx: tx) else {
                        throw OWSAssertionError("Attachment file deleted before creation")
                    }

                    let mediaSizePixels: CGSize?
                    switch pendingAttachment.validatedContentType {
                    case .invalid, .file, .audio:
                        mediaSizePixels = nil
                    case .image(let pixelSize), .video(_, let pixelSize, _), .animatedImage(let pixelSize):
                        mediaSizePixels = pixelSize
                    }
                    let referenceParams = AttachmentReference.ConstructionParams(
                        owner: firstReference.owner,
                        sourceFilename: firstReference.sourceFilename,
                        sourceUnencryptedByteCount: pendingAttachment.unencryptedByteCount,
                        sourceMediaSizePixels: mediaSizePixels
                    )
                    let attachmentParams = Attachment.ConstructionParams.fromStream(
                        blurHash: pendingAttachment.blurHash,
                        mimeType: pendingAttachment.mimeType,
                        encryptionKey: pendingAttachment.encryptionKey,
                        streamInfo: streamInfo,
                        sha256ContentHash: pendingAttachment.sha256ContentHash,
                        mediaName: mediaName
                    )

                    try self.attachmentStore.insert(
                        attachmentParams,
                        reference: referenceParams,
                        tx: tx
                    )

                    if let mediaName = attachmentParams.mediaName {
                        self.orphanedBackupAttachmentManager.didCreateOrUpdateAttachment(
                            withMediaName: mediaName,
                            tx: tx
                        )

                        if
                            let attachment = attachmentStore.fetchAttachment(
                                mediaName: mediaName,
                                tx: tx
                            )
                        {
                            try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                                attachment,
                                tx: tx
                            )
                            backupAttachmentUploadQueueRunner.backUpAllAttachmentsAfterTxCommits(tx: tx)
                        }
                    }

                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingAttachment.orphanRecordId, tx: tx)

                    guard let attachment = self.attachmentStore.fetchFirst(
                        owner: referenceParams.owner.id,
                        tx: tx
                    )?.asStream() else {
                        throw OWSAssertionError("Missing attachment we just created")
                    }
                    newAttachment = attachment
                    alreadyAssignedFirstReference = true
                } catch let error {
                    let existingAttachmentId: Attachment.IDType
                    if let error = error as? AttachmentInsertError {
                        existingAttachmentId = try AttachmentManagerImpl.handleAttachmentInsertError(
                            error,
                            pendingAttachmentStreamInfo: streamInfo,
                            pendingAttachmentEncryptionKey: pendingAttachment.encryptionKey,
                            pendingAttachmentMimeType: pendingAttachment.mimeType,
                            pendingAttachmentOrphanRecordId: pendingAttachment.orphanRecordId,
                            pendingAttachmentTransitTierInfo: nil,
                            attachmentStore: attachmentStore,
                            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
                            orphanedAttachmentStore: orphanedAttachmentStore,
                            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
                            tx: tx
                        )
                        backupAttachmentUploadQueueRunner.backUpAllAttachmentsAfterTxCommits(tx: tx)
                    } else {
                        throw error
                    }

                    // Already have an attachment with the same plaintext hash or media name!
                    // We will instead re-point all references to this attachment.
                    guard
                        let attachment = self.attachmentStore.fetch(id: existingAttachmentId, tx: tx)?.asStream()
                    else {
                        throw OWSAssertionError("Missing attachment we just matched against")
                    }
                    newAttachment = attachment
                    alreadyAssignedFirstReference = false
                }

                // Move all existing references to the new thumbnail stream.
                let referencesToUpdate = alreadyAssignedFirstReference
                    ? references.suffix(max(references.count - 1, 0))
                    : references
                try referencesToUpdate.forEach { reference in
                    try self.attachmentStore.removeOwner(
                        reference: reference,
                        tx: tx
                    )
                    let newOwnerParams = AttachmentReference.ConstructionParams(
                        owner: reference.owner.forReassignmentWithContentType(newAttachment.contentType.raw),
                        sourceFilename: reference.sourceFilename,
                        sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
                        sourceMediaSizePixels: reference.sourceMediaSizePixels
                    )
                    try self.attachmentStore.addOwner(
                        newOwnerParams,
                        for: newAttachment.attachment.id,
                        tx: tx
                    )
                }
                references.forEach { reference in
                    // Its ok to point at the old owner here; its the same message id
                    // or story message id etc, which is what we use for this.
                    self.touchOwner(reference.owner, tx: tx)
                }
                return newAttachment
            }
        }

        func copyThumbnailForQuotedReplyIfNeeded(_ downloadedAttachment: AttachmentStream) async throws {
            let thumbnailAttachments = try db.read { tx in
                return try self.attachmentStore.allQuotedReplyAttachments(
                    forOriginalAttachmentId: downloadedAttachment.attachment.id,
                    tx: tx
                )
            }
            guard thumbnailAttachments.contains(where: { $0.asStream() == nil }) else {
                // all the referencing thumbnails already have their own streams, nothing to do.
                return
            }
            let pendingThumbnailAttachment = try await self.decrypter.prepareQuotedReplyThumbnail(
                originalAttachmentStream: downloadedAttachment
            )

            try await db.awaitableWrite { tx in
                let alreadyAssignedFirstReference: Bool
                let thumbnailAttachments = try self.attachmentStore
                    .allQuotedReplyAttachments(
                        forOriginalAttachmentId: downloadedAttachment.attachment.id,
                        tx: tx
                    )
                    .filter({ $0.asStream() == nil })

                let references = try thumbnailAttachments.flatMap { attachment in
                    var refs = [AttachmentReference]()
                    try self.attachmentStore.enumerateAllReferences(
                        toAttachmentId: attachment.id,
                        tx: tx
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

                try self.attachmentStore.removeOwner(
                    reference: firstReference,
                    tx: tx
                )

                let mediaName = Attachment.mediaName(
                    sha256ContentHash: pendingThumbnailAttachment.sha256ContentHash,
                    encryptionKey: pendingThumbnailAttachment.encryptionKey
                )
                let streamInfo = Attachment.StreamInfo(
                    sha256ContentHash: pendingThumbnailAttachment.sha256ContentHash,
                    mediaName: mediaName,
                    encryptedByteCount: pendingThumbnailAttachment.encryptedByteCount,
                    unencryptedByteCount: pendingThumbnailAttachment.unencryptedByteCount,
                    contentType: pendingThumbnailAttachment.validatedContentType,
                    digestSHA256Ciphertext: pendingThumbnailAttachment.digestSHA256Ciphertext,
                    localRelativeFilePath: pendingThumbnailAttachment.localRelativeFilePath
                )

                let thumbnailAttachmentId: Attachment.IDType
                do {
                    guard self.orphanedAttachmentStore.orphanAttachmentExists(with: pendingThumbnailAttachment.orphanRecordId, tx: tx) else {
                        throw OWSAssertionError("Attachment file deleted before creation")
                    }

                    let mediaSizePixels: CGSize?
                    switch pendingThumbnailAttachment.validatedContentType {
                    case .invalid, .file, .audio:
                        mediaSizePixels = nil
                    case .image(let pixelSize), .video(_, let pixelSize, _), .animatedImage(let pixelSize):
                        mediaSizePixels = pixelSize
                    }
                    let referenceParams = AttachmentReference.ConstructionParams(
                        owner: firstReference.owner,
                        sourceFilename: firstReference.sourceFilename,
                        sourceUnencryptedByteCount: pendingThumbnailAttachment.unencryptedByteCount,
                        sourceMediaSizePixels: mediaSizePixels
                    )
                    let attachmentParams = Attachment.ConstructionParams.fromStream(
                        blurHash: pendingThumbnailAttachment.blurHash,
                        mimeType: pendingThumbnailAttachment.mimeType,
                        encryptionKey: pendingThumbnailAttachment.encryptionKey,
                        streamInfo: streamInfo,
                        sha256ContentHash: pendingThumbnailAttachment.sha256ContentHash,
                        mediaName: mediaName,
                    )

                    try self.attachmentStore.insert(
                        attachmentParams,
                        reference: referenceParams,
                        tx: tx
                    )

                    if let mediaName = attachmentParams.mediaName {
                        self.orphanedBackupAttachmentManager.didCreateOrUpdateAttachment(
                            withMediaName: mediaName,
                            tx: tx
                        )

                        if
                            let attachment = attachmentStore.fetchAttachment(
                                mediaName: mediaName,
                                tx: tx
                            )
                        {
                            try backupAttachmentUploadScheduler.enqueueUsingHighestPriorityOwnerIfNeeded(
                                attachment,
                                tx: tx
                            )
                            backupAttachmentUploadQueueRunner.backUpAllAttachmentsAfterTxCommits(tx: tx)
                        }
                    }

                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingThumbnailAttachment.orphanRecordId, tx: tx)

                    guard let attachment = self.attachmentStore.fetchFirst(
                        owner: referenceParams.owner.id,
                        tx: tx
                    ) else {
                        throw OWSAssertionError("Missing attachment we just created")
                    }
                    thumbnailAttachmentId = attachment.id
                    alreadyAssignedFirstReference = true
                } catch let error {
                    let existingAttachmentId: Attachment.IDType
                    if let error = error as? AttachmentInsertError {
                        existingAttachmentId = try AttachmentManagerImpl.handleAttachmentInsertError(
                            error,
                            pendingAttachmentStreamInfo: streamInfo,
                            pendingAttachmentEncryptionKey: pendingThumbnailAttachment.encryptionKey,
                            pendingAttachmentMimeType: pendingThumbnailAttachment.mimeType,
                            pendingAttachmentOrphanRecordId: pendingThumbnailAttachment.orphanRecordId,
                            pendingAttachmentTransitTierInfo: nil,
                            attachmentStore: attachmentStore,
                            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
                            orphanedAttachmentStore: orphanedAttachmentStore,
                            backupAttachmentUploadScheduler: backupAttachmentUploadScheduler,
                            orphanedBackupAttachmentManager: orphanedBackupAttachmentManager,
                            tx: tx
                        )
                        backupAttachmentUploadQueueRunner.backUpAllAttachmentsAfterTxCommits(tx: tx)
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
                try referencesToUpdate.forEach { reference in
                    try self.attachmentStore.removeOwner(
                        reference: reference,
                        tx: tx
                    )
                    let newOwnerParams = AttachmentReference.ConstructionParams(
                        owner: reference.owner.forReassignmentWithContentType(pendingThumbnailAttachment.validatedContentType.raw),
                        sourceFilename: reference.sourceFilename,
                        sourceUnencryptedByteCount: reference.sourceUnencryptedByteCount,
                        sourceMediaSizePixels: reference.sourceMediaSizePixels
                    )
                    try self.attachmentStore.addOwner(
                        newOwnerParams,
                        for: thumbnailAttachmentId,
                        tx: tx
                    )
                }
                references.forEach { reference in
                    // Its ok to point at the old owner here; its the same message id
                    // or story message id etc, which is what we use for this.
                    self.touchOwner(reference.owner, tx: tx)
                }
            }
        }

        func touchAllOwners(attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
            try? self.attachmentStore.enumerateAllReferences(
                toAttachmentId: attachmentId,
                tx: tx
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
                        tx: tx
                    )
                else {
                    break
                }
                db.touch(interaction: interaction, shouldReindex: false, tx: tx)
            case .storyMessage(let storyMessageSource):
                guard
                    let storyMessage = storyStore.fetchStoryMessage(
                        rowId: storyMessageSource.storyMsessageRowId,
                        tx: tx
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
        public typealias ProfileManager = _AttachmentDownloadManagerImpl_ProfileManagerShim
        public typealias StickerManager = _AttachmentDownloadManagerImpl_StickerManagerShim
    }

    public enum Wrappers {
        public typealias ProfileManager = _AttachmentDownloadManagerImpl_ProfileManagerWrapper
        public typealias StickerManager = _AttachmentDownloadManagerImpl_StickerManagerWrapper
    }
}

public protocol _AttachmentDownloadManagerImpl_ProfileManagerShim {

    func isThread(inProfileWhitelist thread: TSThread, tx: DBReadTransaction) -> Bool
}

public class _AttachmentDownloadManagerImpl_ProfileManagerWrapper: _AttachmentDownloadManagerImpl_ProfileManagerShim {

    private let profileManager: ProfileManagerProtocol

    public init(_ profileManager: ProfileManagerProtocol) {
        self.profileManager = profileManager
    }

    public func isThread(inProfileWhitelist thread: TSThread, tx: DBReadTransaction) -> Bool {
        profileManager.isThread(inProfileWhitelist: thread, transaction: SDSDB.shimOnlyBridge(tx))
    }
}

public protocol _AttachmentDownloadManagerImpl_StickerManagerShim {

    func fetchInstalledSticker(packId: Data, stickerId: UInt32, tx: DBReadTransaction) -> InstalledSticker?

    func stickerDataUrl(forInstalledSticker: InstalledSticker, verifyExists: Bool) -> URL?
}

public class _AttachmentDownloadManagerImpl_StickerManagerWrapper: _AttachmentDownloadManagerImpl_StickerManagerShim {
    public init() {}

    public func fetchInstalledSticker(packId: Data, stickerId: UInt32, tx: DBReadTransaction) -> InstalledSticker? {
        return StickerManager.fetchInstalledSticker(packId: packId, stickerId: stickerId, transaction: SDSDB.shimOnlyBridge(tx))
    }

    public func stickerDataUrl(forInstalledSticker: InstalledSticker, verifyExists: Bool) -> URL? {
        return StickerManager.stickerDataUrl(forInstalledSticker: forInstalledSticker, verifyExists: verifyExists)
    }
}
