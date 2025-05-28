//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

extension Attachment {
    /// How long we keep attachment files locally by default when "optimize local storage"
    /// is enabled. Measured from the receive time of the most recent owning message.
    public static let offloadingThresholdMs: UInt64 = .dayInMs * 30

    /// How long we keep attachment files locally after viewing them when "optimize local storage"
    /// is enabled.
    private static let offloadingViewThresholdMs: UInt64 = .dayInMs

    /// Returns true if the given attachment should be offloaded (have its local file(s) deleted)
    /// because it has met the criteria to be stored exclusively in the backup media tier.
    public func shouldBeOffloaded(
        shouldOptimizeLocalStorage: Bool,
        currentUploadEra: String,
        currentTimestamp: UInt64,
        attachmentStore: AttachmentStore,
        tx: DBReadTransaction
    ) throws -> Bool {
        guard shouldOptimizeLocalStorage else {
            // Don't offload anything unless this setting is enabled.
            return false
        }
        guard let stream = self.asStream() else {
            // We only offload stuff we have locally, duh.
            return false
        }
        if stream.needsMediaTierUpload(currentUploadEra: currentUploadEra) {
            // Don't offload until we've backed up to media tier.
            return false
        }
        if
            let viewedTimestamp = self.lastFullscreenViewTimestamp,
            viewedTimestamp + Self.offloadingViewThresholdMs > currentTimestamp
        {
            // Don't offload if viewed recently.
            return false
        }

        // Lastly find the most recent owner and use its timestamp to determine
        // eligibility to offload.
        switch try attachmentStore.fetchMostRecentReference(toAttachmentId: self.id, tx: tx).owner {
        case .message(let messageSource):
            return messageSource.receivedAtTimestamp + Self.offloadingThresholdMs > currentTimestamp
        case .storyMessage:
            // Story messages expire on their own; never offload
            // any attachment owned by a story message.
            return false
        case .thread:
            // We never offload thread wallpapers.
            return false
        }
    }
}

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
    private let dateProvider: DateProvider
    private let db: DB
    private let backupSettingsStore: BackupSettingsStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let listMediaManager: BackupListMediaManager
    private let orphanedAttachmentCleaner: OrphanedAttachmentCleaner
    private let orphanedAttachmentStore: OrphanedAttachmentStore

    public init(
        attachmentStore: AttachmentStore,
        dateProvider: @escaping DateProvider,
        db: DB,
        backupSettingsStore: BackupSettingsStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        listMediaManager: BackupListMediaManager,
        orphanedAttachmentCleaner: OrphanedAttachmentCleaner,
        orphanedAttachmentStore: OrphanedAttachmentStore,
    ) {
        self.attachmentStore = attachmentStore
        self.dateProvider = dateProvider
        self.db = db
        self.backupSettingsStore = backupSettingsStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.listMediaManager = listMediaManager
        self.orphanedAttachmentCleaner = orphanedAttachmentCleaner
        self.orphanedAttachmentStore = orphanedAttachmentStore
    }

    public func offloadAttachmentsIfNeeded() async throws {
        guard FeatureFlags.Backups.remoteExportAlpha else {
            return
        }

        guard db.read(block: { backupPlanAllowsOffloading(tx: $0) }) else {
            return
        }

        // Query list media if needed to ensure we have the latest cdn info
        // for all our uploads.
        try await listMediaManager.queryListMediaIfNeeded()

        let startTimeMs = dateProvider().ows_millisecondsSince1970
        var lastAttachmentId: Attachment.IDType?
        while true {
            try Task.checkCancellation()
            lastAttachmentId = try await db.awaitableWrite { tx in
                try self.offloadNextBatch(startTimeMs: startTimeMs, lastAttachmentId: lastAttachmentId, tx: tx)
            }
            if lastAttachmentId == nil {
                break
            }
        }

        await orphanedAttachmentCleaner.runUntilFinished()
    }

    // Returns nil if finished.
    private func offloadNextBatch(
        startTimeMs: UInt64,
        lastAttachmentId: Attachment.IDType?,
        tx: DBWriteTransaction
    ) throws -> Attachment.IDType? {
        guard backupPlanAllowsOffloading(tx: tx) else {
            return nil
        }

        let currentUploadEra = backupSubscriptionManager.getUploadEra(tx: tx)
        let viewedTimestampCutoff = startTimeMs - Attachment.offloadingThresholdMs

        var attachmentsQuery = Attachment.Record
            // We only offload downloaded attachments, duh
            .filter(Column(Attachment.Record.CodingKeys.localRelativeFilePath) != nil)
            // Only offload stuff we've uploaded in the current upload era.
            .filter(Column(Attachment.Record.CodingKeys.mediaTierUploadEra) == currentUploadEra)
            .filter(Column(Attachment.Record.CodingKeys.mediaTierCdnNumber) != nil)
            // Don't offload stuff viewed recently
            .filter(Column(Attachment.Record.CodingKeys.lastFullscreenViewTimestamp) < viewedTimestampCutoff)

        if let lastAttachmentId {
            attachmentsQuery = attachmentsQuery
                .filter(Column(Attachment.Record.CodingKeys.sqliteId) > lastAttachmentId)
        }

        let attachmentCursor = try attachmentsQuery
            .order(Column(Attachment.Record.CodingKeys.sqliteId).asc)
            .fetchCursor(tx.database)

        var lastAttachmentId: Attachment.IDType?
        var numAttachmentsChecked = 0
        var numAttachmentsDeleted = 0
        while let attachment = try attachmentCursor.next() {
            let attachment = try Attachment(record: attachment)
            lastAttachmentId = attachment.id

            if
                try attachment.shouldBeOffloaded(
                    shouldOptimizeLocalStorage: true,
                    currentUploadEra: currentUploadEra,
                    currentTimestamp: startTimeMs,
                    attachmentStore: attachmentStore,
                    tx: tx
                )
            {
                var orphanRecord = OrphanedAttachmentRecord(
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
                    }()
                )
                try orphanedAttachmentStore.insert(&orphanRecord, tx: tx)
                let params = Attachment.ConstructionParams.forOffloadingFiles(attachment: attachment)
                var newRecord = Attachment.Record(params: params)
                newRecord.sqliteId = attachment.id
                try newRecord.update(tx.database)
                numAttachmentsDeleted += 1
            }
            numAttachmentsChecked += 1
            if
                // Do up to 50 mark-for-deletions per batch
                numAttachmentsDeleted >= 50
                // But because checking is expensive (requires an AttachmentReference join)
                // and we may skip many we check, limit batch size by skipped ones too
                || numAttachmentsChecked >= 100
            {
                return lastAttachmentId
            }
        }

        // If we reached the end of the cursor, we're done.
        return nil
    }

    private func backupPlanAllowsOffloading(tx: DBReadTransaction) -> Bool {
        switch db.read(block: { backupSettingsStore.backupPlan(tx: $0) }) {
        case .disabled, .free:
            return false
        case .paidExpiringSoon(_):
            // Don't offload if our subscription expires soon, regardless of the
            // optimizeLocalStorage setting.
            return false
        case .paid(let optimizeLocalStorage):
            return optimizeLocalStorage
        }
    }
}

extension AttachmentStore {

    func fetchMostRecentReference(
        toAttachmentId attachmentId: Attachment.IDType,
        tx: DBReadTransaction
    ) throws -> AttachmentReference {
        var mostRecentReference: AttachmentReference?
        var maxMessageTimestamp: UInt64 = 0
        try self.enumerateAllReferences(
            toAttachmentId: attachmentId,
            tx: tx
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
