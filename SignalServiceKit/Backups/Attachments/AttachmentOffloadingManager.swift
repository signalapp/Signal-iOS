//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

extension Attachment {
    /// How long we keep attachment files locally by default when "optimize local storage"
    /// is enabled. Measured from the receive time of the most recent owning message.
    public static var offloadingThresholdMs: UInt64 {
        if offloadingThresholdOverride { return 0 }
        return .dayInMs * 30
    }

    /// How long we keep attachment files locally after viewing them when "optimize local storage"
    /// is enabled.
    fileprivate static var offloadingViewThresholdMs: UInt64 {
        if offloadingThresholdOverride { return 0 }
        return .dayInMs * 7
    }

    public static var offloadingThresholdOverride: Bool {
        get { DebugFlags.internalSettings && UserDefaults.standard.bool(forKey: "offloadingThresholdOverride") }
        set {
            guard DebugFlags.internalSettings else { return }
            UserDefaults.standard.set(newValue, forKey: "offloadingThresholdOverride")
        }
    }
}

// MARK: -

public protocol AttachmentOffloadingManager {

    /// Walk over all attachments and delete local files for any that are eligible to be
    /// offloaded.
    /// This can be a very expensive operation (e.g. if "optimize local storage" was
    /// just enabled and there's a lot to clean up) so it is best to call this in a
    /// non-user-blocking context, e.g. during an overnight backup BGProcessingTask.
    ///
    /// Supports cooperative cancellation; makes incremental progress if cancelled.
    func offloadAttachmentsIfNeeded() async throws
}

public class AttachmentOffloadingManagerImpl: AttachmentOffloadingManager {

    private let attachmentStore: AttachmentStore
    private let attachmentThumbnailService: AttachmentThumbnailService
    private let backupAttachmentDownloadStore: BackupAttachmentDownloadStore
    private let backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore
    private let backupSettingsStore: BackupSettingsStore
    private let dateProvider: DateProvider
    private let db: DB
    private let listMediaManager: BackupListMediaManager
    private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
    private let orphanedAttachmentStore: OrphanedAttachmentStore
    private let tsAccountManager: TSAccountManager

    public init(
        attachmentStore: AttachmentStore,
        attachmentThumbnailService: AttachmentThumbnailService,
        backupAttachmentDownloadStore: BackupAttachmentDownloadStore,
        backupAttachmentUploadEraStore: BackupAttachmentUploadEraStore,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: DB,
        listMediaManager: BackupListMediaManager,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
        tsAccountManager: TSAccountManager,
    ) {
        self.attachmentStore = attachmentStore
        self.attachmentThumbnailService = attachmentThumbnailService
        self.backupAttachmentDownloadStore = backupAttachmentDownloadStore
        self.backupAttachmentUploadEraStore = backupAttachmentUploadEraStore
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.db = db
        self.listMediaManager = listMediaManager
        self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
        self.orphanedAttachmentStore = orphanedAttachmentStore
        self.tsAccountManager = tsAccountManager
    }

    public func offloadAttachmentsIfNeeded() async throws {
        guard BuildFlags.Backups.showOptimizeMedia else {
            return
        }

        guard db.read(block: { offloadingIsAllowed(tx: $0) }) else {
            return
        }

        let startTimeMs = dateProvider().ows_millisecondsSince1970
        var lastAttachmentId: Attachment.IDType?
        while true {
            try Task.checkCancellation()
            lastAttachmentId = try await self.offloadNextBatch(startTimeMs: startTimeMs, lastAttachmentId: lastAttachmentId)
            if lastAttachmentId == nil {
                break
            }
        }

        try await orphanedAttachmentCleaner.runUntilFinished()
    }

    static let maxThumbnailedAttachmentsPerBatch = 5
    static let maxOffloadedAttachmentsPerBatch = 50
    static let maxCheckedAttachmentsPerBatch = 100

    // Returns nil if finished.
    private func offloadNextBatch(
        startTimeMs: UInt64,
        lastAttachmentId: Attachment.IDType?,
    ) async throws -> Attachment.IDType? {
        let viewedTimestampCutoff = startTimeMs - Attachment.offloadingViewThresholdMs

        let needsListMedia = db.read(block: listMediaManager.getNeedsQueryListMedia(tx:))
        if needsListMedia {
            throw NeedsListMediaError()
        }

        let (candidateAttachments, didHitEnd) = try db.read { tx -> ([Attachment], Bool) in
            guard offloadingIsAllowed(tx: tx) else {
                return ([], false)
            }

            let currentUploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: tx)

            var attachmentQuery = Attachment.Record
                // We only offload downloaded attachments, duh
                .filter(Column(Attachment.Record.CodingKeys.localRelativeFilePath) != nil)
                // Only offload stuff we've uploaded in the current upload era.
                .filter(Column(Attachment.Record.CodingKeys.mediaTierUploadEra) == currentUploadEra)
                .filter(Column(Attachment.Record.CodingKeys.mediaTierCdnNumber) != nil)
                // Don't offload stuff viewed recently
                .filter(
                    Column(Attachment.Record.CodingKeys.lastFullscreenViewTimestamp) == nil
                        || Column(Attachment.Record.CodingKeys.lastFullscreenViewTimestamp) < viewedTimestampCutoff,
                )

            if let lastAttachmentId {
                attachmentQuery = attachmentQuery
                    .filter(Column(Attachment.Record.CodingKeys.sqliteId) > lastAttachmentId)
            }

            var attachments = [Attachment]()
            var numAttachmentsChecked = 0
            var numAttachmentsNeedingThumbnail = 0
            let cursor = try attachmentQuery
                .order(Column(Attachment.Record.CodingKeys.sqliteId).asc)
                .fetchCursor(tx.database)

            while let record = try cursor.next() {
                let attachment = try Attachment(record: record)
                let mostRecentReference = try attachmentStore.fetchMostRecentReference(
                    toAttachmentId: attachment.id,
                    tx: tx,
                )

                if
                    shouldAttachmentBeOffloaded(
                        attachment,
                        currentUploadEra: currentUploadEra,
                        currentTimestamp: startTimeMs,
                        mostRecentReference: mostRecentReference,
                        tx: tx,
                    )
                {
                    attachments.append(attachment)
                    if self.thumbnailableAttachment(attachment) != nil {
                        numAttachmentsNeedingThumbnail += 1
                    }
                }

                numAttachmentsChecked += 1
                if numAttachmentsChecked >= Self.maxCheckedAttachmentsPerBatch {
                    return (attachments, false)
                }
                if attachments.count >= Self.maxOffloadedAttachmentsPerBatch {
                    return (attachments, false)
                }
                if numAttachmentsNeedingThumbnail >= Self.maxThumbnailedAttachmentsPerBatch {
                    return (attachments, false)
                }
            }

            // If we get here we reached the end of the cursor
            return (attachments, true)
        }

        if candidateAttachments.isEmpty {
            return nil
        }

        let pendingThumbnails = try await generateThumbnails(candidateAttachments)

        try await db.awaitableWrite { tx in
            guard offloadingIsAllowed(tx: tx) else {
                return
            }

            let currentUploadEra = backupAttachmentUploadEraStore.currentUploadEra(tx: tx)

            for nextAttachment in candidateAttachments {
                // Refetch the attachment and reference.
                guard
                    let attachment = attachmentStore.fetch(id: nextAttachment.id, tx: tx)
                else {
                    return
                }

                let mostRecentReference = try attachmentStore.fetchMostRecentReference(
                    toAttachmentId: attachment.id,
                    tx: tx,
                )

                guard
                    shouldAttachmentBeOffloaded(
                        attachment,
                        currentUploadEra: currentUploadEra,
                        currentTimestamp: startTimeMs,
                        mostRecentReference: mostRecentReference,
                        tx: tx,
                    )
                else {
                    return
                }
                _ = OrphanedAttachmentRecord.insertRecord(
                    OrphanedAttachmentRecord.InsertableRecord(
                        isPendingAttachment: false,
                        localRelativeFilePath: attachment.streamInfo?.localRelativeFilePath,
                        // Don't delete the thumbnail
                        localRelativeFilePathThumbnail: nil,
                        localRelativeFilePathAudioWaveform: {
                            switch attachment.streamInfo?.contentType {
                            case .audio(_, let waveformRelativeFilePath):
                                return waveformRelativeFilePath
                            default:
                                return nil
                            }
                        }(),
                        localRelativeFilePathVideoStillFrame: {
                            switch attachment.streamInfo?.contentType {
                            case .video(_, _, let stillFrameRelativeFilePath):
                                return stillFrameRelativeFilePath
                            default:
                                return nil
                            }
                        }(),
                    ),
                    tx: tx,
                )
                let params = Attachment.ConstructionParams.forOffloadingFiles(
                    attachment: attachment,
                    localRelativeFilePathThumbnail: pendingThumbnails[attachment.id]?.reservedRelativeFilePath,
                )
                var newRecord = Attachment.Record(params: params)
                newRecord.sqliteId = attachment.id
                try newRecord.update(tx.database)

                // Enqueue a download for the attachment we just offloaded, in the `ineligible` state,
                // so that if we ever disable offloading again it will redownload.
                backupAttachmentDownloadStore.enqueue(
                    ReferencedAttachment(
                        reference: mostRecentReference,
                        attachment: try Attachment(record: newRecord),
                    ),
                    // Only re-enqueue the fullsize attachment for download
                    thumbnail: false,
                    // We're only here because we offloaded to media tier
                    canDownloadFromMediaTier: true,
                    state: .ineligible,
                    currentTimestamp: dateProvider().ows_millisecondsSince1970,
                    tx: tx,
                )

                if let thumbnailOrphanRecordId = pendingThumbnails[attachment.id]?.orphanRecordId {
                    orphanedAttachmentCleaner.releasePendingAttachment(withId: thumbnailOrphanRecordId, tx: tx)
                }
            }
        }

        if didHitEnd {
            return nil
        } else {
            return candidateAttachments.last?.id
        }
    }

    private func offloadingIsAllowed(tx: DBReadTransaction) -> Bool {
        guard tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice else {
            return false
        }

        switch backupSettingsStore.backupPlan(tx: tx) {
        case .disabled, .disabling, .free:
            return false
        case .paidExpiringSoon:
            // Don't offload if our subscription expires soon, regardless of the
            // optimizeLocalStorage setting.
            return false
        case .paid(let optimizeLocalStorage), .paidAsTester(let optimizeLocalStorage):
            return optimizeLocalStorage
        }
    }

    /// Returns true if the given attachment should be offloaded (have its local file(s) deleted)
    /// because it has met the criteria to be stored exclusively in the backup media tier.
    private func shouldAttachmentBeOffloaded(
        _ attachment: Attachment,
        currentUploadEra: String,
        currentTimestamp: UInt64,
        mostRecentReference: AttachmentReference,
        tx: DBReadTransaction,
    ) -> Bool {
        guard attachment.asStream() != nil else {
            // We only offload stuff we have locally, duh.
            return false
        }
        guard
            let mediaTierInfo = attachment.mediaTierInfo,
            mediaTierInfo.isUploaded(currentUploadEra: currentUploadEra)
        else {
            // Don't offload until we've backed up to media tier.
            // Note that attachments that are ineligible for media tier upload
            // (some DMs, view-once, oversized text) won't be uploaded and therefore
            // won't pass this check. We don't need to also check for "eligibility"
            // here and can just rely on upload mechanisms to have checked that.
            return false
        }

        // Lastly, use the most recent owner's timestamp to determine
        // eligibility to offload.
        switch mostRecentReference.owner {
        case .message(let messageSource):
            return messageSource.receivedAtTimestamp + Attachment.offloadingThresholdMs < currentTimestamp
        case .storyMessage:
            // Story messages expire on their own; never offload
            // any attachment owned by a story message.
            return false
        case .thread:
            // We never offload thread wallpapers.
            return false
        }
    }

    // MARK: -

    private struct PendingThumbnail {
        let attachmentId: Attachment.IDType
        let reservedRelativeFilePath: String
        let orphanRecordId: OrphanedAttachmentRecord.RowId
    }

    private struct ThumbnailableAttachment {
        let stream: AttachmentStream
        let mediaName: String
        let thumbnailEncryptionKey: Data

        var id: Attachment.IDType { stream.id }
    }

    /// Returns nil if the attachment cannot or does not need to be thumbnailed.
    private func thumbnailableAttachment(_ attachment: Attachment) -> ThumbnailableAttachment? {
        guard
            attachment.localRelativeFilePathThumbnail == nil,
            AttachmentBackupThumbnail.canBeThumbnailed(attachment),
            let stream = attachment.asStream(),
            let mediaName = attachment.mediaName
        else {
            return nil
        }
        return ThumbnailableAttachment(
            stream: stream,
            mediaName: mediaName,
            thumbnailEncryptionKey: attachment.encryptionKey,
        )
    }

    private func generateThumbnails(_ attachments: [Attachment]) async throws -> [Attachment.IDType: PendingThumbnail] {
        let attachments = attachments.compactMap(self.thumbnailableAttachment(_:))
        if attachments.isEmpty {
            return [:]
        }

        // Create thumbnails, reserving the file location first and then
        // setting it on the attachment in the same transaction as we clear
        // the fullsize files.
        let reservedThumbnailFilePaths = attachments.reduce(into: [Attachment.IDType: String]()) {
            $0[$1.id] = AttachmentStream.newRelativeFilePath()
        }

        // do the whole batch in one big write.
        let thumbnailOrphanRecordIds: [Attachment.IDType: OrphanedAttachmentRecord.RowId] = await orphanedAttachmentCleaner
            .commitPendingAttachments(
                reservedThumbnailFilePaths.mapValues { reservedThumbnailFilePath in
                    OrphanedAttachmentRecord.InsertableRecord(
                        isPendingAttachment: true,
                        localRelativeFilePath: nil,
                        localRelativeFilePathThumbnail: reservedThumbnailFilePath,
                        localRelativeFilePathAudioWaveform: nil,
                        localRelativeFilePathVideoStillFrame: nil,
                    )
                },
            )

        // Generate thumbnails in parallel
        let successfulThumbnails: Set<Attachment.IDType>
        successfulThumbnails = try await withThrowingTaskGroup { [attachmentThumbnailService, reservedThumbnailFilePaths] taskGroup in
            for attachment in attachments {
                guard let reservedThumbnailFilePath = reservedThumbnailFilePaths[attachment.id] else {
                    continue
                }
                taskGroup.addTask { () throws -> Attachment.IDType? in
                    guard
                        let thumbnailImage = await attachmentThumbnailService.thumbnailImage(
                            for: attachment.stream,
                            quality: .backupThumbnail,
                        )
                    else {
                        return nil
                    }

                    let thumbnailData: Data
                    do {
                        thumbnailData = try attachmentThumbnailService.backupThumbnailData(image: thumbnailImage)
                    } catch {
                        // Unable to generate a small enough thumbnail, abort.
                        // This attachment will just be offloaded with no local
                        // thumbnail and can be redownloaded whenever.
                        return nil
                    }

                    let (encryptedThumbnailData, _) = try Cryptography.encrypt(
                        thumbnailData,
                        attachmentKey: AttachmentKey(combinedKey: attachment.thumbnailEncryptionKey),
                        applyExtraPadding: true,
                    )

                    // Write the thumbnail to the reserved file location.
                    let fileUrl = AttachmentStream.absoluteAttachmentFileURL(relativeFilePath: reservedThumbnailFilePath)
                    guard OWSFileSystem.ensureDirectoryExists(fileUrl.deletingLastPathComponent().path) else {
                        throw OWSAssertionError("Unable to create directory")
                    }
                    guard OWSFileSystem.ensureFileExists(fileUrl.path) else {
                        throw OWSAssertionError("Unable to create file")
                    }
                    try encryptedThumbnailData.write(to: fileUrl)
                    return attachment.id
                }
            }

            var results = Set<Attachment.IDType>()
            for try await id in taskGroup {
                if let id {
                    results.insert(id)
                }
            }
            return results
        }

        return attachments.reduce(into: [Attachment.IDType: PendingThumbnail]()) { dictionary, attachment in
            guard
                let reservedThumbnailFilePath = reservedThumbnailFilePaths[attachment.id],
                let thumbnailOrphanRecordId = thumbnailOrphanRecordIds[attachment.id],
                successfulThumbnails.contains(attachment.id)
            else {
                return
            }
            dictionary[attachment.id] = PendingThumbnail(
                attachmentId: attachment.id,
                reservedRelativeFilePath: reservedThumbnailFilePath,
                orphanRecordId: thumbnailOrphanRecordId,
            )
        }
    }
}

// MARK: -

extension AttachmentStore {

    func fetchMostRecentReference(
        toAttachmentId attachmentId: Attachment.IDType,
        tx: DBReadTransaction,
    ) throws -> AttachmentReference {
        var mostRecentReference: AttachmentReference?
        var maxMessageTimestamp: UInt64 = 0
        self.enumerateAllReferences(
            toAttachmentId: attachmentId,
            tx: tx,
        ) { reference, stop in
            switch reference.owner {
            case .message(let messageSource):
                switch mostRecentReference?.owner {
                case nil, .message:
                    if messageSource.receivedAtTimestamp > maxMessageTimestamp {
                        maxMessageTimestamp = messageSource.receivedAtTimestamp
                        mostRecentReference = reference
                    }
                case .storyMessage, .thread:
                    // Always consider these more "recent" than messages.
                    break
                }

            case .storyMessage:
                switch mostRecentReference?.owner {
                case nil, .message, .storyMessage:
                    mostRecentReference = reference
                case .thread:
                    // Always consider these more "recent" than story messages.
                    break
                }

            case .thread:
                // We always treat wallpapers as "most recent".
                stop = true
                mostRecentReference = reference
            }
        }
        guard let mostRecentReference else {
            throw OWSAssertionError("Attachment without an owner! Was the attachment deleted?")
        }
        return mostRecentReference
    }
}
