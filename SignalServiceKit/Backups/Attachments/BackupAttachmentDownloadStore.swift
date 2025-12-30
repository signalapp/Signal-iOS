//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class BackupAttachmentDownloadStore {

    private let kvStore: KeyValueStore

    public init() {
        self.kvStore = KeyValueStore(collection: "BackupAttachmentDownloadStoreImpl")
    }

    /// "Enqueue" an attachment from a backup for download (using its reference).
    ///
    /// If the same attachment pointed to by the reference is already enqueued, updates it to the greater
    /// of the existing and new reference's timestamp.
    ///
    /// Doesn't actually trigger a download; callers must later call ``BackupAttachmentDownloadManager``
    /// to actually kick off downloads.
    public func enqueue(
        _ referencedAttachment: ReferencedAttachment,
        thumbnail: Bool,
        canDownloadFromMediaTier: Bool,
        state: QueuedBackupAttachmentDownload.State,
        currentTimestamp: UInt64,
        tx: DBWriteTransaction,
        file: StaticString? = #file,
        function: StaticString? = #function,
        line: UInt? = #line,
    ) {
        if let file, let function, let line {
            Logger.info("Enqueuing \(referencedAttachment.attachment.id) thumbnail? \(thumbnail) from \(file) \(line): \(function)")
        }

        if thumbnail {
            owsPrecondition(canDownloadFromMediaTier, "All thumbnails are media tier")
        }

        let db = tx.database
        var timestamp: UInt64? = {
            switch referencedAttachment.reference.owner {
            case .message(let messageSource):
                return messageSource.receivedAtTimestamp
            case .storyMessage, .thread:
                return nil
            }
        }()

        let existingRecordQuery = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == referencedAttachment.attachment.id)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == thumbnail)
        let existingRecord = failIfThrows {
            return try existingRecordQuery.fetchOne(db)
        }

        if
            let existingRecord,
            existingRecord.maxOwnerTimestamp ?? .max < timestamp ?? .max
        {
            // If we have an existing record with a smaller timestamp,
            // delete it in favor of the new row we are about to insert.
            // (nil timestamp counts as the largest timestamp)
            // This will also reset the retry count, which is fine.
            failIfThrows {
                try existingRecord.delete(db)
            }
        } else if
            let existingRecord,
            existingRecord.state != state
            || existingRecord.canDownloadFromMediaTier != canDownloadFromMediaTier
        {
            // We can modify the state of the existing record even if the
            // new timestamp doesn't match; use the greater timestamp and
            // delete the old record so we write a new one.
            failIfThrows {
                try existingRecord.delete(db)
            }
            if existingRecord.maxOwnerTimestamp ?? .max > timestamp ?? .max {
                timestamp = existingRecord.maxOwnerTimestamp
            }
        } else if existingRecord != nil {
            // Otherwise we had an existing record with a larger
            // timestamp, stop.
            return
        }

        // Initialize the min retry timestamp to a lower value
        // the higher the timestamp is, as we dequeue in ASC order.
        let minRetryTimestamp: UInt64
        if let timestamp, timestamp < currentTimestamp {
            minRetryTimestamp = currentTimestamp - timestamp
        } else {
            minRetryTimestamp = 0
        }

        var record = QueuedBackupAttachmentDownload(
            attachmentRowId: referencedAttachment.attachment.id,
            isThumbnail: thumbnail,
            canDownloadFromMediaTier: canDownloadFromMediaTier,
            maxOwnerTimestamp: timestamp,
            minRetryTimestamp: minRetryTimestamp,
            state: state,
            estimatedByteCount: QueuedBackupAttachmentDownload.estimatedByteCount(
                attachment: referencedAttachment.attachment,
                reference: referencedAttachment.reference,
                isThumbnail: thumbnail,
                canDownloadFromMediaTier: canDownloadFromMediaTier,
            ),
        )
        failIfThrows {
            try record.insert(db)
        }
    }

    public func getEnqueuedDownload(
        attachmentRowId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBReadTransaction,
    ) -> QueuedBackupAttachmentDownload? {
        let query = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == attachmentRowId)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == thumbnail)

        return failIfThrows {
            return try query.fetchOne(tx.database)
        }
    }

    /// Read the next highest priority downloads off the queue, up to count.
    /// Returns an empty array if nothing is left to download.
    public func peek(
        count: UInt,
        isThumbnail: Bool,
        tx: DBReadTransaction,
    ) throws -> [QueuedBackupAttachmentDownload] {
        let query = QueuedBackupAttachmentDownload
            .filter(
                Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                    == QueuedBackupAttachmentDownload.State.ready.rawValue,
            )
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == isThumbnail)
            .order([
                Column(QueuedBackupAttachmentDownload.CodingKeys.minRetryTimestamp).asc,
            ])
            .limit(Int(count))

        return failIfThrows {
            return try query.fetchAll(tx.database)
        }
    }

    /// Returns true if there are any rows in the ready state.
    public func hasAnyReadyDownloads(
        isThumbnail: Bool,
        tx: DBReadTransaction,
    ) -> Bool {
        let query = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.state) == QueuedBackupAttachmentDownload.State.ready.rawValue)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == isThumbnail)

        return failIfThrows {
            return try !query.isEmpty(tx.database)
        }
    }

    /// Mark a download as done.
    /// If we mark a fullsize as done, the thumbnail is marked done too
    /// (since we never need a thumbnail once we have a fullsize).
    public func markDone(
        attachmentId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBWriteTransaction,
    ) {
        var query = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == attachmentId)

        // If not a thumbnail, mark both fullsize and thumbnail done, as we never
        // need a thumbnail after we have the fullsize download.
        if thumbnail {
            query = query.filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == true)
        }

        failIfThrows {
            try query.updateAll(
                tx.database,
                Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                    .set(to: QueuedBackupAttachmentDownload.State.done.rawValue),
            )
        }
    }

    /// Mark a download as ineligible.
    public func markIneligible(
        attachmentId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBWriteTransaction,
    ) {
        let query = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == attachmentId)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == thumbnail)

        failIfThrows {
            try query.updateAll(
                tx.database,
                [
                    Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                        .set(to: QueuedBackupAttachmentDownload.State.ineligible.rawValue),
                ],
            )
        }
    }

    /// Delete a download.
    /// WARNING: typically when a download finishes, we want to mark it done
    /// rather than deleting, so that it still contributes to the total byte count.
    /// Deleting is appropriate if we learn the upload is gone from the CDN,
    /// the attachment is deleted, etc; things that mean we will never download.
    public func remove(
        attachmentId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBWriteTransaction,
        file: StaticString? = #file,
        function: StaticString? = #function,
        line: UInt? = #line,
    ) {
        if let file, let function, let line {
            Logger.info("Deleting \(attachmentId) thumbnail? \(thumbnail) from \(file) \(line): \(function)")
        }
        let query = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == attachmentId)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == thumbnail)

        failIfThrows {
            try query.deleteAll(tx.database)
        }
    }

    /// Mark all enqueued & ready media tier fullsize downloads from the table for attachments
    /// older than the provided timestamp as ineligible.
    /// Applies independently of whether that download is also eligible to download from the
    /// transit tier; its assumed that anything on the media tier is stable and if its offloaded to
    /// there we don't need to worry about downloading from transit tier before it expires.
    public func markAllMediaTierFullsizeDownloadsIneligible(
        olderThan timestamp: UInt64,
        tx: DBWriteTransaction,
    ) {
        let query = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.state) ==
                QueuedBackupAttachmentDownload.State.ready.rawValue)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.canDownloadFromMediaTier) == true)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.maxOwnerTimestamp) != nil)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.maxOwnerTimestamp) < timestamp)

        failIfThrows {
            try query.updateAll(
                tx.database,
                [
                    Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                        .set(to: QueuedBackupAttachmentDownload.State.ineligible.rawValue),
                ],
            )
        }
    }

    /// Marks all ineligible rows as ready (no filtering applied).
    public func markAllIneligibleReady(tx: DBWriteTransaction) {
        let query = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.state) ==
                QueuedBackupAttachmentDownload.State.ineligible.rawValue)

        failIfThrows {
            try query.updateAll(
                tx.database,
                [
                    Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                        .set(to: QueuedBackupAttachmentDownload.State.ready.rawValue),
                ],
            )
        }
    }

    /// Marks all ready rows as ineligible (no filtering applied).
    public func markAllReadyIneligible(tx: DBWriteTransaction) {
        let query = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.state) ==
                QueuedBackupAttachmentDownload.State.ready.rawValue)

        failIfThrows {
            try query.updateAll(
                tx.database,
                [
                    Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                        .set(to: QueuedBackupAttachmentDownload.State.ineligible.rawValue),
                ],
            )
        }
    }

    /// Remove all done rows (effectively resetting the total byte count).
    public func deleteAllDone(
        tx: DBWriteTransaction,
        file: StaticString? = #file,
        function: StaticString? = #function,
        line: UInt? = #line,
    ) {
        if let file, let function, let line {
            Logger.info("Deleting all done rows from \(file) \(line): \(function)")
        }

        if let byteCountSnapshot = computeEstimatedFinishedFullsizeByteCount(tx: tx) {
            kvStore.setUInt64(byteCountSnapshot, key: self.downloadCompleteBannerByteCountSnapshotKey, transaction: tx)
        }

        let query = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.state) ==
                QueuedBackupAttachmentDownload.State.done.rawValue)

        failIfThrows {
            try query.deleteAll(tx.database)
        }
    }

    public func computeEstimatedFinishedFullsizeByteCount(tx: DBReadTransaction) -> UInt64? {
        let sql = """
        SELECT SUM(\(QueuedBackupAttachmentDownload.CodingKeys.estimatedByteCount.rawValue))
        FROM \(QueuedBackupAttachmentDownload.databaseTableName)
        WHERE
            \(QueuedBackupAttachmentDownload.CodingKeys.state.rawValue) = \(QueuedBackupAttachmentDownload.State.done.rawValue)
            AND \(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail.rawValue) = 0;
        """

        return failIfThrows {
            try UInt64.fetchOne(tx.database, sql: sql)
        }
    }

    public func computeEstimatedRemainingFullsizeByteCount(tx: DBReadTransaction) -> UInt64? {
        let sql = """
        SELECT SUM(\(QueuedBackupAttachmentDownload.CodingKeys.estimatedByteCount.rawValue))
        FROM \(QueuedBackupAttachmentDownload.databaseTableName)
        WHERE
            \(QueuedBackupAttachmentDownload.CodingKeys.state.rawValue) = \(QueuedBackupAttachmentDownload.State.ready.rawValue)
            AND \(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail.rawValue) = 0;
        """

        return failIfThrows {
            try UInt64.fetchOne(tx.database, sql: sql)
        }
    }

    private let didDismissDownloadCompleteBannerKey = "didDismissDownloadCompleteBannerKey"
    private let downloadCompleteBannerByteCountSnapshotKey = "downloadCompleteBannerByteCountSnapshotKey"

    public func getDownloadCompleteBannerByteCount(tx: DBReadTransaction) -> UInt64? {
        if let snapshot = kvStore.getUInt64(self.downloadCompleteBannerByteCountSnapshotKey, transaction: tx) {
            return snapshot
        }
        return computeEstimatedFinishedFullsizeByteCount(tx: tx)
    }

    /// Whether the banner for downloads being complete was dismissed. Reset when new downloads
    /// are scheduled (when `setTotalPendingDownloadByteCount` is set.)
    public func getDidDismissDownloadCompleteBanner(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(didDismissDownloadCompleteBannerKey, defaultValue: false, transaction: tx)
    }

    public func setDidDismissDownloadCompleteBanner(tx: DBWriteTransaction) {
        kvStore.setBool(true, key: didDismissDownloadCompleteBannerKey, transaction: tx)
        kvStore.removeValue(forKey: downloadCompleteBannerByteCountSnapshotKey, transaction: tx)
    }

    public func resetDidDismissDownloadCompleteBanner(tx: DBWriteTransaction) {
        kvStore.setBool(false, key: didDismissDownloadCompleteBannerKey, transaction: tx)
        kvStore.removeValue(forKey: downloadCompleteBannerByteCountSnapshotKey, transaction: tx)
    }
}

// MARK: -

public extension QueuedBackupAttachmentDownload {

    static func estimatedByteCount(
        attachment: Attachment,
        reference: AttachmentReference?,
        isThumbnail: Bool,
        canDownloadFromMediaTier: Bool,
    ) -> UInt32 {
        if isThumbnail {
            // We don't know how big the thumbnail will be; just estimate
            // it to be its largest allowed size.
            return Cryptography.estimatedMediaTierCDNSize(
                unencryptedSize: UInt64(safeCast: AttachmentThumbnailQuality.backupThumbnailMaxSizeBytes),
            ).flatMap(UInt32.init(exactly:))!
        } else {
            // Media tier has the larger byte count, and its better to overcount than
            // undercount, so prefer that if we think there's a chance to download from
            // media tier. The media tier download may fail, and we may fall back to
            // transit tier, but there are mechanisms to attribute the full (larger)
            // estimated byte count even if the actual download ends up smaller.
            //
            // For the actual source of unencrypted byte count, prefer the particular
            // cdn info but fall back to whatever else we have; they should all be
            // equivalent if no foolery is happening (and this is all an estimate anyway).
            if
                canDownloadFromMediaTier,
                let unencryptedByteCount =
                attachment.mediaTierInfo?.unencryptedByteCount
                    ?? attachment.latestTransitTierInfo?.unencryptedByteCount
                    ?? reference?.sourceUnencryptedByteCount
            {
                return UInt32(clamping: Cryptography.estimatedMediaTierCDNSize(
                    unencryptedSize: UInt64(safeCast: unencryptedByteCount),
                ) ?? .max)
            } else if
                let unencryptedByteCount =
                attachment.latestTransitTierInfo?.unencryptedByteCount
                    ?? attachment.mediaTierInfo?.unencryptedByteCount
                    ?? reference?.sourceUnencryptedByteCount
            {
                return UInt32(clamping: Cryptography.estimatedTransitTierCDNSize(
                    unencryptedSize: UInt64(safeCast: unencryptedByteCount),
                ) ?? .max)
            } else {
                return 0
            }
        }
    }
}
