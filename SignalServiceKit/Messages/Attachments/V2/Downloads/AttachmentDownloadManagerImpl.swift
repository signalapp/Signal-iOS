//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentDownloadManagerImpl: AttachmentDownloadManager {

    private let attachmentDownloadStore: AttachmentDownloadStore
    private let attachmentStore: AttachmentStore
    private let attachmentUpdater: AttachmentUpdater
    private let db: DB
    private let decrypter: Decrypter
    private let downloadQueue: DownloadQueue
    private let downloadabilityChecker: DownloadabilityChecker
    private let progressStates: ProgressStates
    private let queueLoader: PersistedQueueLoader

    public init(
        appReadiness: Shims.AppReadiness,
        attachmentDownloadStore: AttachmentDownloadStore,
        attachmentStore: AttachmentStore,
        attachmentValidator: AttachmentContentValidator,
        currentCallProvider: CurrentCallProvider,
        dateProvider: @escaping DateProvider,
        db: DB,
        interactionStore: InteractionStore,
        mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
        profileManager: Shims.ProfileManager,
        signalService: OWSSignalServiceProtocol,
        stickerManager: Shims.StickerManager,
        storyStore: StoryStore,
        threadStore: ThreadStore
    ) {
        self.attachmentDownloadStore = attachmentDownloadStore
        self.attachmentStore = attachmentStore
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
            db: db,
            decrypter: decrypter,
            interactionStore: interactionStore,
            orphanedAttachmentCleaner: orphanedAttachmentCleaner,
            orphanedAttachmentStore: orphanedAttachmentStore,
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
        self.queueLoader = PersistedQueueLoader(
            attachmentDownloadStore: attachmentDownloadStore,
            attachmentStore: attachmentStore,
            attachmentUpdater: attachmentUpdater,
            dateProvider: dateProvider,
            db: db,
            decrypter: decrypter,
            downloadQueue: downloadQueue,
            downloadabilityChecker: downloadabilityChecker,
            stickerManager: stickerManager
        )

        appReadiness.runNowOrWhenMainAppDidBecomeReadyAsync { [weak self] in
            guard AttachmentFeatureFlags.writeStories || AttachmentFeatureFlags.writeMessages else {
                return
            }
            self?.beginDownloadingIfNecessary()
        }
    }

    public func downloadBackup(metadata: MessageBackupRemoteInfo, authHeaders: [String: String]) -> Promise<URL> {
        let downloadState = DownloadState(type: .backup(metadata, authHeaders: authHeaders))
        return Promise.wrapAsync {
            let maxDownloadSize = MessageBackup.Constants.maxDownloadSizeBytes
            return try await self.downloadQueue.enqueueDownload(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxDownloadSize
            )
        }
    }

    public func downloadTransientAttachment(metadata: AttachmentDownloads.DownloadMetadata) -> Promise<URL> {
        return Promise.wrapAsync {
            // We want to avoid large downloads from a compromised or buggy service.
            let maxDownloadSize = RemoteConfig.maxAttachmentDownloadSizeBytes
            let downloadState = DownloadState(type: .transientAttachment(metadata))

            let encryptedFileUrl = try await self.downloadQueue.enqueueDownload(
                downloadState: downloadState,
                maxDownloadSizeBytes: maxDownloadSize
            )
            return try await self.decrypter.decryptTransientAttachment(encryptedFileUrl: encryptedFileUrl, metadata: metadata)
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
        let referencedAttachments = attachmentStore
            .fetchReferencedAttachments(
                owners: AttachmentReference.MessageOwnerTypeRaw.allCases.map {
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
            let downloadability = downloadabilityChecker.downloadability(
                of: referencedAttachment.reference,
                priority: priority,
                mimeType: referencedAttachment.attachment.mimeType,
                tx: tx
            )
            switch downloadability {
            case .downloadable:
                didEnqueueAnyDownloads = true
                try? attachmentDownloadStore.enqueueDownloadOfAttachment(
                    withId: referencedAttachment.reference.attachmentRowId,
                    source: .transitTier,
                    priority: priority,
                    tx: tx
                )
            case .blockedByActiveCall:
                Logger.info("Skipping enqueue of download during active call")
            case .blockedByPendingMessageRequest:
                Logger.info("Skipping enqueue of download due to pending message request")
            case .blockedByAutoDownloadSettings:
                Logger.info("Skipping enqueue of download due to auto download settings")
            }
        }
        if didEnqueueAnyDownloads {
            tx.addAsyncCompletion(on: SyncScheduler()) { [weak self] in
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
        try? attachmentDownloadStore.enqueueDownloadOfAttachment(
            withId: id,
            source: source,
            priority: priority,
            tx: tx
        )
        tx.addAsyncCompletion(on: SyncScheduler()) { [weak self] in
            self?.beginDownloadingIfNecessary()
        }
    }

    public func beginDownloadingIfNecessary() {
        guard CurrentAppContext().isMainApp else {
            return
        }
        Task { [weak self] in
            try await self?.queueLoader.loadFromQueueIfAble()
        }
    }

    public func cancelDownload(for attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        progressStates.cancelledAttachmentIds.insert(attachmentId)
        progressStates.states[attachmentId] = nil
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
        return progressStates.states[attachmentId].map { CGFloat($0) }
    }

    // MARK: - Persisted Queue

    private actor PersistedQueueLoader {

        private let attachmentDownloadStore: AttachmentDownloadStore
        private let attachmentStore: AttachmentStore
        private let attachmentUpdater: AttachmentUpdater
        private let dateProvider: DateProvider
        private let db: DB
        private let decrypter: Decrypter
        private let downloadabilityChecker: DownloadabilityChecker
        private let downloadQueue: DownloadQueue
        private let stickerManager: Shims.StickerManager

        init(
            attachmentDownloadStore: AttachmentDownloadStore,
            attachmentStore: AttachmentStore,
            attachmentUpdater: AttachmentUpdater,
            dateProvider: @escaping DateProvider,
            db: DB,
            decrypter: Decrypter,
            downloadQueue: DownloadQueue,
            downloadabilityChecker: DownloadabilityChecker,
            stickerManager: Shims.StickerManager
        ) {
            self.attachmentDownloadStore = attachmentDownloadStore
            self.attachmentStore = attachmentStore
            self.attachmentUpdater = attachmentUpdater
            self.dateProvider = dateProvider
            self.db = db
            self.decrypter = decrypter
            self.downloadQueue = downloadQueue
            self.downloadabilityChecker = downloadabilityChecker
            self.stickerManager = stickerManager
        }

        private let maxConcurrentDownloads: UInt = 4
        private var currentRecordIds = Set<Int64>()

        /// Load the next N enqueued downloads, and begin downloading any
        /// that are not already downloading.
        /// (N = max concurrent downloads)
        func loadFromQueueIfAble() async throws {
            try Task.checkCancellation()

            if currentRecordIds.count >= maxConcurrentDownloads {
                return
            }

            let recordCandidates = try db.read { tx in
                try attachmentDownloadStore.peek(count: self.maxConcurrentDownloads, tx: tx)
            }

            let records = recordCandidates.filter { record in
                !currentRecordIds.contains(record.id!)
            }
            guard !records.isEmpty else {
                return
            }
            records.lazy.compactMap(\.id).forEach {
                currentRecordIds.insert($0)
            }

            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                records.forEach { record in
                    taskGroup.addTask {
                        await self.downloadRecord(record)
                        // As soon as we finish any download, start downloading more.
                        try await self.loadFromQueueIfAble()
                    }
                }
                try await taskGroup.waitForAll()
            }
        }

        private func didFinishDownloading(_ record: QueuedAttachmentDownloadRecord) async {
            Logger.info("Succeeded download of attachment \(record.attachmentId)")
            self.currentRecordIds.remove(record.id!)
            await db.awaitableWrite { tx in
                try? self.attachmentDownloadStore.removeAttachmentFromQueue(
                    withId: record.attachmentId,
                    source: record.sourceType,
                    tx: tx
                )
            }
        }

        private func didFailToDownload(
            _ record: QueuedAttachmentDownloadRecord,
            isRetryable: Bool
        ) async {
            Logger.error("Failed download of attachment \(record.attachmentId)")
            self.currentRecordIds.remove(record.id!)
            if isRetryable, let retryTime = self.retryTime(for: record) {
                await db.awaitableWrite { tx in
                    try? self.attachmentDownloadStore.markQueuedDownloadFailed(
                        withId: record.id!,
                        minRetryTimestamp: retryTime,
                        tx: tx
                    )
                }
            } else {
                // Not retrying; just delete.
                await db.awaitableWrite { tx in
                    try? self.attachmentDownloadStore.removeAttachmentFromQueue(
                        withId: record.attachmentId,
                        source: record.sourceType,
                        tx: tx
                    )
                    try? self.attachmentStore.updateAttachmentAsFailedToDownload(
                        from: record.sourceType,
                        id: record.attachmentId,
                        timestamp: self.dateProvider().ows_millisecondsSince1970,
                        tx: tx
                    )

                    tx.addAsyncCompletion(on: SyncScheduler()) { [weak self] in
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
                switch record.priority {
                case .default, .backupRestoreLow, .backupRestoreHigh:
                    guard record.retryAttempts < 32 else {
                        owsFailDebug("risk of integer overflow")
                        return nil
                    }
                    // Exponential backoff, starting at 1 day.
                    let initialDelay = kDayInMs
                    let delay = UInt64(pow(2.0, Double(record.retryAttempts))) * initialDelay
                    if delay > kDayInMs * 30 {
                        // Don't go more than 30 days; stop retrying.
                        Logger.info("Giving up retrying attachment download")
                        return nil
                    }
                    return delay
                case .userInitiated:
                    // Don't _persist_ a retry for this; let the error
                    // bubble up to the user, they can tap to retry.
                    return nil
                case .localClone:
                    owsFailDebug("Trying to retry a local clone? Shouldn't happen")
                    return nil
                }
            }
        }

        private nonisolated func downloadRecord(_ record: QueuedAttachmentDownloadRecord) async {
            guard let attachment = db.read(block: { tx in
                attachmentStore.fetch(id: record.attachmentId, tx: tx)
            }) else {
                // Because of the foreign key relationship and cascading deletes, this should
                // only happen if the attachment got deleted between when we fetched the
                // download queue record and now. Regardless, the record should now be deleted.
                owsFailDebug("Attempting to download an attachment that doesn't exist!")
                return
            }

            guard attachment.asStream() == nil else {
                // Already a stream! No need to download.
                await self.didFinishDownloading(record)
                return
            }

            switch self.downloadabilityChecker.downloadability(record, attachment: attachment) {
            case .downloadable:
                break
            case .blockedByActiveCall:
                // This is a temporary setback; retry in a bit if the source allows it.
                Logger.info("Skipping attachment download due to active call \(record.attachmentId)")
                await self.didFailToDownload(record, isRetryable: true)
                return
            case .blockedByPendingMessageRequest:
                Logger.info("Skipping attachment download due to pending message request \(record.attachmentId)")
                // These can only be resolved by user action; cancel the enqueued download.
                await self.didFailToDownload(record, isRetryable: false)
                return
            case .blockedByAutoDownloadSettings:
                Logger.info("Skipping attachment download due to auto download settings \(record.attachmentId)")
                // These can only be resolved by user action; cancel the enqueued download.
                await self.didFailToDownload(record, isRetryable: false)
                return
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
                await self.didFinishDownloading(record)
                return
            }

            if await quoteUnquoteDownloadStickerFromInstalledPackIfPossible(record: record) {
                // Done!
                Logger.info("Sourced sticker attachment from installed sticker \(record.attachmentId)")
                await self.didFinishDownloading(record)
                return
            }

            if record.priority == .localClone {
                // Local clone happens in two ways:
                // 1. Original's local stream for a quoted reply
                // 2. Local installed sticker for a sticker message
                // If we were trying for either of these and got this far,
                // we failed to use the local data, so just fail the whole thing.
                await self.didFailToDownload(record, isRetryable: false)
                return
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
                        digest: transitTierInfo.digestSHA256Ciphertext,
                        plaintextLength: transitTierInfo.unencryptedByteCount
                    )
                )
            case .mediaTierFullsize:
                guard
                    let mediaTierInfo = attachment.mediaTierInfo,
                    let mediaName = attachment.mediaName,
                    let cdnNumber = mediaTierInfo.cdnNumber
                else {
                    downloadMetadata = nil
                    break
                }
                downloadMetadata = .init(
                    mimeType: attachment.mimeType,
                    cdnNumber: cdnNumber,
                    encryptionKey: attachment.encryptionKey,
                    source: .mediaTierFullsize(
                        mediaName: mediaName,
                        digest: mediaTierInfo.digestSHA256Ciphertext,
                        plaintextLength: mediaTierInfo.unencryptedByteCount
                    )
                )
            case .mediaTierThumbnail:
                guard
                    let thumbnailInfo = attachment.thumbnailMediaTierInfo,
                    let mediaName = attachment.mediaName,
                    let cdnNumber = thumbnailInfo.cdnNumber
                else {
                    downloadMetadata = nil
                    break
                }
                downloadMetadata = .init(
                    mimeType: attachment.mimeType,
                    cdnNumber: cdnNumber,
                    encryptionKey: attachment.encryptionKey,
                    source: .mediaTierThumbnail(
                        mediaName: mediaName
                    )
                )
            }

            guard let downloadMetadata else {
                owsFailDebug("Attempting to download an attachment without cdn info")
                // Remove the download.
                await self.didFailToDownload(record, isRetryable: false)
                return
            }

            let downloadedFileUrl: URL
            do {
                downloadedFileUrl = try await downloadQueue.enqueueDownload(
                    downloadState: .init(type: .attachment(downloadMetadata, id: attachment.id)),
                    maxDownloadSizeBytes: RemoteConfig.maxAttachmentDownloadSizeBytes
                )
            } catch let error {
                Logger.error("Failed to download: \(error)")
                // We retry all network-level errors (with an exponential backoff).
                // Even if we get e.g. a 404, the file may not be available _yet_
                // but might be in the future.
                await self.didFailToDownload(record, isRetryable: true)
                return
            }

            let pendingAttachment: PendingAttachment
            do {
                pendingAttachment = try await decrypter.validateAndPrepare(
                    encryptedFileUrl: downloadedFileUrl,
                    metadata: downloadMetadata
                )
            } catch let error {
                Logger.error("Failed to validate: \(error)")
                await self.didFailToDownload(record, isRetryable: false)
                return
            }

            let attachmentStream: AttachmentStream
            do {
                attachmentStream = try await attachmentUpdater.updateAttachmentAsDownloaded(
                    attachmentId: attachment.id,
                    pendingAttachment: pendingAttachment,
                    source: record.sourceType
                )
            } catch let error {
                Logger.error("Failed to update attachment: \(error)")
                await self.didFailToDownload(record, isRetryable: true)
                return
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

            await self.didFinishDownloading(record)
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
                    block: { reference in
                        switch reference.owner {
                        case .message(.sticker(let metadata)):
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
    }

    // MARK: - Downloadability

    private class DownloadabilityChecker {

        private let attachmentStore: AttachmentStore
        private let currentCallProvider: CurrentCallProvider
        private let db: DB
        private let mediaBandwidthPreferenceStore: MediaBandwidthPreferenceStore
        private let profileManager: Shims.ProfileManager
        private let threadStore: ThreadStore

        init(
            attachmentStore: AttachmentStore,
            currentCallProvider: CurrentCallProvider,
            db: DB,
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
            case .default, .backupRestoreHigh, .backupRestoreLow:
                break
            }
            return db.read { tx in
                var downloadability: Downloadability?

                try? self.attachmentStore.enumerateAllReferences(
                    toAttachmentId: record.attachmentId,
                    tx: tx
                ) { reference in
                    // If one reference marks it downloadable, don't check further ones.
                    if downloadability == .downloadable {
                        return
                    }
                    downloadability = self.downloadability(
                        of: reference,
                        priority: record.priority,
                        mimeType: attachment.mimeType,
                        tx: tx
                    )
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
            case .default, .backupRestoreLow, .backupRestoreHigh:
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
            case .default, .backupRestoreLow, .backupRestoreHigh:
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
            case .backupRestoreLow, .backupRestoreHigh:
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
        case backup(MessageBackupRemoteInfo, authHeaders: [String: String])
        case transientAttachment(DownloadMetadata)
        case attachment(DownloadMetadata, id: Attachment.IDType)

        // MARK: - Helpers
        func urlPath() throws -> String {
            switch self {
            case .backup(let info, _):
                return "backups/\(info.backupDir)/\(info.backupName)"
            case .attachment(let metadata, _), .transientAttachment(let metadata):
                switch metadata.source {
                case .transitTier(let cdnKey, _, _):
                    guard let encodedKey = cdnKey.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
                        throw OWSAssertionError("Invalid cdnKey.")
                    }
                    return "attachments/\(encodedKey)"
                case .mediaTierFullsize:
                    throw OWSAssertionError("Unimplemented")
                case .mediaTierThumbnail:
                    throw OWSAssertionError("Unimplemented")
                }
            }
        }

        func cdnNumber() -> UInt32 {
            switch self {
            case .backup(let info, _):
                return UInt32(clamping: info.cdn)
            case .attachment(let metadata, _), .transientAttachment(let metadata):
                return metadata.cdnNumber
            }
        }

        func additionalHeaders() -> [String: String] {
            switch self {
            case .backup(_, let authHeaders):
                return authHeaders
            case .attachment(let metadata, _), .transientAttachment(let metadata):
                switch metadata.source {
                case .transitTier:
                    return [:]
                case .mediaTierFullsize:
                    // TODO: apply headers
                    return [:]
                case .mediaTierThumbnail:
                    // TODO: apply headers
                    return [:]
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

        func additionalHeaders() -> [String: String] {
            return type.additionalHeaders()
        }
    }

    private class ProgressStates {
        private let lock = UnfairLock()
        private(set) lazy var states = AtomicDictionary<Attachment.IDType, Double>(lock: lock)
        private(set) lazy var cancelledAttachmentIds = AtomicSet<Attachment.IDType>(lock: lock)

        init() {}
    }

    private actor DownloadQueue {

        private let progressStates: ProgressStates
        private let signalService: OWSSignalServiceProtocol

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

        func enqueueDownload(
            downloadState: DownloadState,
            maxDownloadSizeBytes: UInt
        ) async throws -> URL {
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

        private nonisolated func performDownloadAttempt(
            downloadState: DownloadState,
            maxDownloadSizeBytes: UInt,
            resumeData: Data?,
            attemptCount: UInt
        ) async throws -> URL {
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

            let progress = { (task: URLSessionTask, progress: Progress) in
                self.handleDownloadProgress(
                    downloadState: downloadState,
                    task: task,
                    progress: progress,
                    attachmentId: attachmentId
                )
            }

            do {
                let downloadResponse: OWSUrlDownloadResponse
                if let resumeData = resumeData {
                    let request = try urlSession.endpoint.buildRequest(urlPath, method: .get, headers: headers)
                    guard let requestUrl = request.url else {
                        throw OWSAssertionError("Request missing url.")
                    }
                    downloadResponse = try await urlSession.downloadTaskPromise(
                        requestUrl: requestUrl,
                        resumeData: resumeData,
                        progress: progress
                    ).awaitable()
                } else {
                    downloadResponse = try await urlSession.downloadTaskPromise(
                        urlPath,
                        method: .get,
                        headers: headers,
                        progress: progress
                    ).awaitable()
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
                    maxDownloadSizeBytes: maxDownloadSizeBytes,
                    resumeData: newResumeData,
                    attemptCount: attemptCount + 1
                )
            }
        }

        private nonisolated func handleDownloadProgress(
            downloadState: DownloadState,
            task: URLSessionTask,
            progress: Progress,
            attachmentId: Attachment.IDType?
        ) {
            if let attachmentId, progressStates.cancelledAttachmentIds.contains(attachmentId) {
                Logger.info("Cancelling download.")
                // Cancelling will inform the URLSessionTask delegate.
                task.cancel()
                return
            }

            // Don't do anything until we've received at least one byte of data.
            guard progress.completedUnitCount > 0 else {
                return
            }

            // Use a slightly non-zero value to ensure that the progress
            // indicator shows up as quickly as possible.
            let progressTheta: Double = 0.001
            let fractionCompleted = max(progressTheta, progress.fractionCompleted)

            switch downloadState.type {
            case .backup, .transientAttachment:
                break
            case .attachment(_, let attachmentId):
                progressStates.states[attachmentId] = fractionCompleted

                NotificationCenter.default.postNotificationNameAsync(
                    AttachmentDownloads.attachmentDownloadProgressNotification,
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

        // Use serialQueue to ensure that we only load into memory
        // & decrypt a single attachment at a time.
        private let decryptionQueue = SerialTaskQueue()

        func decryptTransientAttachment(
            encryptedFileUrl: URL,
            metadata: DownloadMetadata
        ) async throws -> URL {
            return try await decryptionQueue.enqueue(operation: {
                do {
                    // Transient attachments decrypt to a tmp file.
                    let outputUrl = OWSFileSystem.temporaryFileUrl()

                    try Cryptography.decryptAttachment(
                        at: encryptedFileUrl,
                        metadata: EncryptionMetadata(
                            key: metadata.encryptionKey,
                            digest: metadata.digest,
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
            }).value
        }

        func validateAndPrepareInstalledSticker(
            _ sticker: InstalledSticker
        ) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            let stickerManager = self.stickerManager
            return try await decryptionQueue.enqueue(operation: {
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
                                dataSource: DataSourcePath.dataSource(
                                    with: stickerDataUrl,
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
            }).value
        }

        func validateAndPrepare(
            encryptedFileUrl: URL,
            metadata: DownloadMetadata
        ) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            return try await decryptionQueue.enqueue(operation: {
                // AttachmentValidator runs synchronously _and_ opens write transactions
                // internally. We can't block on the write lock in the cooperative thread
                // pool, so bridge out of structured concurrency to run the validation.
                return try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global().async {
                        do {
                            let pendingAttachment: PendingAttachment
                            switch metadata.source {
                            case .transitTier(_, let digest, let plaintextLength):
                                pendingAttachment = try attachmentValidator.validateContents(
                                    ofEncryptedFileAt: encryptedFileUrl,
                                    encryptionKey: metadata.encryptionKey,
                                    plaintextLength: plaintextLength,
                                    digestSHA256Ciphertext: digest,
                                    mimeType: metadata.mimeType,
                                    renderingFlag: .default,
                                    sourceFilename: nil
                                )
                            case .mediaTierFullsize(_, let digest, let plaintextLength):
                                pendingAttachment = try attachmentValidator.validateContents(
                                    ofBackupMediaFileAt: encryptedFileUrl,
                                    encryptionKey: metadata.encryptionKey,
                                    plaintextLength: plaintextLength,
                                    digestSHA256Ciphertext: digest,
                                    mimeType: metadata.mimeType,
                                    renderingFlag: .default,
                                    sourceFilename: nil
                                )
                            case .mediaTierThumbnail(_):
                                pendingAttachment = try attachmentValidator.validateContents(
                                    ofBackupMediaFileAt: encryptedFileUrl,
                                    encryptionKey: metadata.encryptionKey,
                                    plaintextLength: nil,
                                    digestSHA256Ciphertext: nil,
                                    mimeType: metadata.mimeType,
                                    renderingFlag: .default,
                                    sourceFilename: nil
                                )
                            }
                            continuation.resume(with: .success(pendingAttachment))
                        } catch let error {
                            continuation.resume(throwing: error)
                        }
                    }
                }
            }).value
        }

        func prepareQuotedReplyThumbnail(originalAttachmentStream: AttachmentStream) async throws -> PendingAttachment {
            let attachmentValidator = self.attachmentValidator
            return try await decryptionQueue.enqueue(operation: {
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
            }).value
        }
    }

    private class AttachmentUpdater {

        private let attachmentStore: AttachmentStore
        private let db: DB
        private let decrypter: Decrypter
        private let interactionStore: InteractionStore
        private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
        private let orphanedAttachmentStore: OrphanedAttachmentStore
        private let storyStore: StoryStore
        private let threadStore: ThreadStore

        public init(
            attachmentStore: AttachmentStore,
            db: DB,
            decrypter: Decrypter,
            interactionStore: InteractionStore,
            orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
            orphanedAttachmentStore: OrphanedAttachmentStore,
            storyStore: StoryStore,
            threadStore: ThreadStore
        ) {
            self.attachmentStore = attachmentStore
            self.db = db
            self.decrypter = decrypter
            self.interactionStore = interactionStore
            self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
            self.orphanedAttachmentStore = orphanedAttachmentStore
            self.storyStore = storyStore
            self.threadStore = threadStore
        }

        func updateAttachmentAsDownloaded(
            attachmentId: Attachment.IDType,
            pendingAttachment: PendingAttachment,
            source: QueuedAttachmentDownloadRecord.SourceType
        ) async throws -> AttachmentStream {
            return try await db.awaitableWrite { tx in
                guard let existingAttachment = self.attachmentStore.fetch(id: attachmentId, tx: tx) else {
                    throw OWSAssertionError("Missing attachment!")
                }
                if let stream = existingAttachment.asStream() {
                    // Its already a stream?
                    return stream
                }

                do {
                    guard self.orphanedAttachmentStore.orphanAttachmentExists(with: pendingAttachment.orphanRecordId, tx: tx) else {
                        throw OWSAssertionError("Attachment file deleted before creation")
                    }

                    // Try and update the attachment.
                    try self.attachmentStore.updateAttachmentAsDownloaded(
                        from: source,
                        id: attachmentId,
                        validatedMimeType: pendingAttachment.mimeType,
                        streamInfo: .init(
                            sha256ContentHash: pendingAttachment.sha256ContentHash,
                            encryptedByteCount: pendingAttachment.encryptedByteCount,
                            unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                            contentType: pendingAttachment.validatedContentType,
                            digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                            localRelativeFilePath: pendingAttachment.localRelativeFilePath
                        ),
                        tx: tx
                    )
                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    try self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingAttachment.orphanRecordId, tx: tx)

                    guard let stream = self.attachmentStore.fetch(id: attachmentId, tx: tx)?.asStream() else {
                        throw OWSAssertionError("Not a stream")
                    }

                    tx.addAsyncCompletion(on: SyncScheduler()) { [weak self] in
                        guard let self else { return }
                        self.db.asyncWrite { tx in
                            self.touchAllOwners(attachmentId: attachmentId, tx: tx)
                        }
                    }

                    return stream

                } catch let AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId) {
                    // Already have an attachment with the same plaintext hash!
                    // Move all existing references to that copy, instead.
                    // Doing so should delete the original attachment pointer.

                    // Just hold all refs in memory; this is a pointer so really there
                    // should only ever be one reference as we don't dedupe pointers.
                    var references = [AttachmentReference]()
                    try self.attachmentStore.enumerateAllReferences(
                        toAttachmentId: attachmentId,
                        tx: tx
                    ) { reference in
                        references.append(reference)
                    }
                    try references.forEach { reference in
                        try self.attachmentStore.removeOwner(
                            reference.owner.id,
                            for: attachmentId,
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
                    tx.addAsyncCompletion(on: SyncScheduler()) { [weak self] in
                        guard let self else { return }
                        self.db.asyncWrite { tx in
                            self.touchAllOwners(attachmentId: attachmentId, tx: tx)
                        }
                    }

                    return stream
                } catch let error {
                    throw error
                }
            }
        }

        func updateAttachmentFromInstalledSticker(
            attachmentId: Attachment.IDType,
            pendingAttachment: PendingAttachment
        ) async throws -> AttachmentStream {
            return try await db.awaitableWrite { tx -> AttachmentStream in
                guard let existingAttachment = self.attachmentStore.fetch(id: attachmentId, tx: tx) else {
                    throw OWSAssertionError("Missing attachment!")
                }
                if let stream = existingAttachment.asStream() {
                    // Its already a stream?
                    return stream
                }

                var references = [AttachmentReference]()
                try self.attachmentStore.enumerateAllReferences(
                    toAttachmentId: attachmentId,
                    tx: tx
                ) {
                    references.append($0)
                }
                // Arbitrarily pick the first reference as the one we will use as the initial ref to
                // the new stream. The others' references will be re-pointed to the new stream afterwards.
                guard let firstReference = references.first else {
                    throw OWSAssertionError("Attachments should never have zero references")
                }

                try self.attachmentStore.removeOwner(
                    firstReference.owner.id,
                    for: firstReference.attachmentRowId,
                    tx: tx
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
                        streamInfo: .init(
                            sha256ContentHash: pendingAttachment.sha256ContentHash,
                            encryptedByteCount: pendingAttachment.encryptedByteCount,
                            unencryptedByteCount: pendingAttachment.unencryptedByteCount,
                            contentType: pendingAttachment.validatedContentType,
                            digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext,
                            localRelativeFilePath: pendingAttachment.localRelativeFilePath
                        ),
                        mediaName: Attachment.mediaName(digestSHA256Ciphertext: pendingAttachment.digestSHA256Ciphertext)
                    )

                    try self.attachmentStore.insert(
                        attachmentParams,
                        reference: referenceParams,
                        tx: tx
                    )

                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    try self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingAttachment.orphanRecordId, tx: tx)

                    guard let attachment = self.attachmentStore.fetchFirst(
                        owner: referenceParams.owner.id,
                        tx: tx
                    )?.asStream() else {
                        throw OWSAssertionError("Missing attachment we just created")
                    }
                    newAttachment = attachment
                    alreadyAssignedFirstReference = true
                } catch let AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId) {
                    // Already have an attachment with the same plaintext hash!
                    // We will instead re-point all references to this attachment.
                    guard
                        let attachment = self.attachmentStore.fetch(id: existingAttachmentId, tx: tx)?.asStream()
                    else {
                        throw OWSAssertionError("Missing attachment we just matched against")
                    }
                    newAttachment = attachment
                    alreadyAssignedFirstReference = false
                } catch let error {
                    throw error
                }

                // Move all existing references to the new thumbnail stream.
                let referencesToUpdate = alreadyAssignedFirstReference
                    ? references.suffix(max(references.count - 1, 0))
                    : references
                try referencesToUpdate.forEach { reference in
                    try self.attachmentStore.removeOwner(
                        reference.owner.id,
                        for: reference.attachmentRowId,
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
                    try self.attachmentStore.enumerateAllReferences(toAttachmentId: attachment.id, tx: tx) {
                        refs.append($0)
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
                    firstReference.owner.id,
                    for: firstReference.attachmentRowId,
                    tx: tx
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
                        streamInfo: .init(
                            sha256ContentHash: pendingThumbnailAttachment.sha256ContentHash,
                            encryptedByteCount: pendingThumbnailAttachment.encryptedByteCount,
                            unencryptedByteCount: pendingThumbnailAttachment.unencryptedByteCount,
                            contentType: pendingThumbnailAttachment.validatedContentType,
                            digestSHA256Ciphertext: pendingThumbnailAttachment.digestSHA256Ciphertext,
                            localRelativeFilePath: pendingThumbnailAttachment.localRelativeFilePath
                        ),
                        mediaName: Attachment.mediaName(digestSHA256Ciphertext: pendingThumbnailAttachment.digestSHA256Ciphertext)
                    )

                    try self.attachmentStore.insert(
                        attachmentParams,
                        reference: referenceParams,
                        tx: tx
                    )

                    // Make sure to clear out the pending attachment from the orphan table so it isn't deleted!
                    try self.orphanedAttachmentCleaner.releasePendingAttachment(withId: pendingThumbnailAttachment.orphanRecordId, tx: tx)

                    guard let attachment = self.attachmentStore.fetchFirst(
                        owner: referenceParams.owner.id,
                        tx: tx
                    ) else {
                        throw OWSAssertionError("Missing attachment we just created")
                    }
                    thumbnailAttachmentId = attachment.id
                    alreadyAssignedFirstReference = true
                } catch let AttachmentInsertError.duplicatePlaintextHash(existingAttachmentId) {
                    // Already have an attachment with the same plaintext hash!
                    // We will instead re-point all references to this attachment.
                    thumbnailAttachmentId = existingAttachmentId
                    alreadyAssignedFirstReference = false
                } catch let error {
                    throw error
                }

                // Move all existing references to the new thumbnail stream.
                let referencesToUpdate = alreadyAssignedFirstReference
                    ? references.suffix(max(references.count - 1, 0))
                    : references
                try referencesToUpdate.forEach { reference in
                    try self.attachmentStore.removeOwner(
                        reference.owner.id,
                        for: reference.attachmentRowId,
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
            ) { reference in
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
                db.touch(interaction, shouldReindex: false, tx: tx)
            case .storyMessage(let storyMessageSource):
                guard
                    let storyMessage = storyStore.fetchStoryMessage(
                        rowId: storyMessageSource.storyMsessageRowId,
                        tx: tx
                    )
                else {
                    break
                }
                db.touch(storyMessage, tx: tx)
            }
        }
    }
}

extension AttachmentDownloadManagerImpl {
    public enum Shims {
        public typealias AppReadiness = _AttachmentDownloadManagerImpl_AppReadinessShim
        public typealias ProfileManager = _AttachmentDownloadManagerImpl_ProfileManagerShim
        public typealias StickerManager = _AttachmentDownloadManagerImpl_StickerManagerShim
    }

    public enum Wrappers {
        public typealias AppReadiness = _AttachmentDownloadManagerImpl_AppReadinessWrapper
        public typealias ProfileManager = _AttachmentDownloadManagerImpl_ProfileManagerWrapper
        public typealias StickerManager = _AttachmentDownloadManagerImpl_StickerManagerWrapper
    }
}

public protocol _AttachmentDownloadManagerImpl_AppReadinessShim {

    func runNowOrWhenMainAppDidBecomeReadyAsync(_ block: @escaping () -> Void)
}

public class _AttachmentDownloadManagerImpl_AppReadinessWrapper: _AttachmentDownloadManagerImpl_AppReadinessShim {

    public init() {}

    public func runNowOrWhenMainAppDidBecomeReadyAsync(_ block: @escaping () -> Void) {
        AppReadiness.runNowOrWhenMainAppDidBecomeReadyAsync(block)
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
