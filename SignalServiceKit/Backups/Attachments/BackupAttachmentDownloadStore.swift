//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public extension NSNotification.Name {
    static let backupAttachmentDownloadQueueSuspensionStatusDidChange = Self("backupAttachmentDownloadQueueSuspensionStatusDidChange")
}

public protocol BackupAttachmentDownloadStore {

    /// "Enqueue" an attachment from a backup for download (using its reference).
    ///
    /// If the same attachment pointed to by the reference is already enqueued, updates it to the greater
    /// of the existing and new reference's timestamp.
    ///
    /// Doesn't actually trigger a download; callers must later call ``BackupAttachmentDownloadManager``
    /// to actually kick off downloads.
    func enqueue(
        _ referencedAttachment: ReferencedAttachment,
        thumbnail: Bool,
        canDownloadFromMediaTier: Bool,
        state: QueuedBackupAttachmentDownload.State,
        currentTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws

    func getEnqueuedDownload(
        attachmentRowId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBReadTransaction
    ) throws -> QueuedBackupAttachmentDownload?

    /// Read the next highest priority downloads off the queue, up to count.
    /// Returns an empty array if nothing is left to download.
    func peek(
        count: UInt,
        currentTimestamp: UInt64,
        tx: DBReadTransaction
    ) throws -> [QueuedBackupAttachmentDownload]

    /// Returns true if there are any rows in the ready state.
    func hasAnyReadyDownloads(tx: DBReadTransaction) throws -> Bool

    /// Mark a download as done.
    /// If we mark a fullsize as done, the thumbnail is marked done too
    /// (since we never need a thumbnail once we have a fullsize).
    func markDone(
        attachmentId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBWriteTransaction
    ) throws

    /// Mark a download as ineligible.
    func markIneligible(
        attachmentId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBWriteTransaction
    ) throws

    /// Delete a download.
    /// WARNING: typically when a download finishes, we want to mark it done
    /// rather than deleting, so that it still contributes to the total byte count.
    /// Deleting is appropriate if we learn the upload is gone from the CDN,
    /// the attachment is deleted, etc; things that mean we will never download.
    func remove(
        attachmentId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBWriteTransaction
    ) throws

    /// Mark all enqueued & ready media tier fullsize downloads from the table for attachments
    /// older than the provided timestamp as ineligible.
    /// Applies independently of whether that download is also eligible to download from the
    /// transit tier; its assumed that anything on the media tier is stable and if its offloaded to
    /// there we don't need to worry about downloading from transit tier before it expires.
    func markAllMediaTierFullsizeDownloadsIneligible(
        olderThan timestamp: UInt64,
        tx: DBWriteTransaction
    ) throws

    /// Marks all ineligible rows as ready (no filtering applied).
    func markAllIneligibleReady(tx: DBWriteTransaction) throws

    /// Marks all ready rows as ineligible (no filtering applied).
    func markAllReadyIneligible(tx: DBWriteTransaction) throws

    /// Remove all done rows (effectively resetting the total byte count).
    func deleteAllDone(tx: DBWriteTransaction) throws

    /// Returns nil, NOT 0, if there are no rows.
    func computeEstimatedFinishedByteCount(tx: DBReadTransaction) throws -> UInt64?

    /// Returns nil, NOT 0, if there are no rows.
    func computeEstimatedRemainingByteCount(tx: DBReadTransaction) throws -> UInt64?

    // MARK: Queue State

    /// We "suspend" the queue to prevent media tier downloads from automatically beginning and consuming
    /// device storage when backup plan state changes happen (which can happen in the background).
    /// Once the user opts in, we can un-suspend.
    func setIsQueueSuspended(_ isSuspended: Bool, tx: DBWriteTransaction)

    func isQueueSuspended(tx: DBReadTransaction) -> Bool

    // MARK: Banner state

    /// Whether the banner for downloads being complete was dismissed. Reset when new downloads
    /// are scheduled (when `setTotalPendingDownloadByteCount` is set.)
    func getDidDismissDownloadCompleteBanner(tx: DBReadTransaction) -> Bool

    func setDidDismissDownloadCompleteBanner(tx: DBWriteTransaction)
}

public class BackupAttachmentDownloadStoreImpl: BackupAttachmentDownloadStore {

    private let kvStore: KeyValueStore

    public init() {
        self.kvStore = KeyValueStore(collection: "BackupAttachmentDownloadStoreImpl")
    }

    public func enqueue(
        _ referencedAttachment: ReferencedAttachment,
        thumbnail: Bool,
        canDownloadFromMediaTier: Bool,
        state: QueuedBackupAttachmentDownload.State,
        currentTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
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

        let existingRecord = try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == referencedAttachment.attachment.id)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == thumbnail)
            .fetchOne(db)

        if
            let existingRecord,
            existingRecord.maxOwnerTimestamp ?? .max < timestamp ?? .max
        {
            // If we have an existing record with a smaller timestamp,
            // delete it in favor of the new row we are about to insert.
            // (nil timestamp counts as the largest timestamp)
            // This will also reset the retry count, which is fine.
            try existingRecord.delete(db)
        } else if
            let existingRecord,
            existingRecord.state != state
                || existingRecord.canDownloadFromMediaTier != canDownloadFromMediaTier
        {
            // We can modify the state of the existing record even if the
            // new timestamp doesn't match; use the greater timestamp and
            // delete the old record so we write a new one.
            try existingRecord.delete(db)
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
                canDownloadFromMediaTier: canDownloadFromMediaTier
            )
        )
        try record.insert(db)
    }

    public func getEnqueuedDownload(
        attachmentRowId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBReadTransaction
    ) throws -> QueuedBackupAttachmentDownload? {
        return try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == attachmentRowId)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == thumbnail)
            .fetchOne(tx.database)
    }

    /// We first dequeue thumbnails more recent than this long ago, then fullsize recent,
    /// then all thumbnails, then all fullsize.
    static let dequeueRecencyThresholdMs: UInt64 = (.dayInMs * 30)

    public func peek(
        count: UInt,
        currentTimestamp: UInt64,
        tx: DBReadTransaction
    ) throws -> [QueuedBackupAttachmentDownload] {
        var results = [QueuedBackupAttachmentDownload]()
        func baseQuery() -> QueryInterfaceRequest<QueuedBackupAttachmentDownload> {
            return QueuedBackupAttachmentDownload
                .filter(
                    Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                    == QueuedBackupAttachmentDownload.State.ready.rawValue
                )
                .order([
                    Column(QueuedBackupAttachmentDownload.CodingKeys.minRetryTimestamp).asc
                ])
                .limit(Int(count) - results.count)
        }

        // First we try recent thumbnails. Stop when we hit the recency threshold.
        // Note that the query sorts by minRetryTimestamp, which effectively sorts
        // by recency (newest first) for anything with a retry count of 0. If we
        // ask SQL to filter by owner timestamp, it will get confused and use a
        // B-Tree, since it doesn't know that minRetryTimestamp ordering and
        // maxOwnerTimestamp ordering as the same. So we use a cursor and just stop
        // when we reach the timestamp threshold.
        let recencyThreshold = currentTimestamp - Self.dequeueRecencyThresholdMs

        var thumbnailMinRetryTimestampThreshold: UInt64 = 0
        var cursor = try baseQuery()
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == true)
            .fetchCursor(tx.database)
        while let record = try cursor.next() {
            if record.maxOwnerTimestamp ?? .max < recencyThreshold {
                thumbnailMinRetryTimestampThreshold = record.minRetryTimestamp
                break
            }
            results.append(record)
        }
        if results.count == count {
            return results
        }

        // Now try recent fullsize.
        var fullsizeMinRetryTimestampThreshold: UInt64 = 0
        cursor = try baseQuery()
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == false)
            .fetchCursor(tx.database)
        while let record = try cursor.next() {
            if record.maxOwnerTimestamp ?? .max < recencyThreshold {
                fullsizeMinRetryTimestampThreshold = record.minRetryTimestamp
                break
            }
            results.append(record)
        }
        if results.count == count {
            return results
        }

        // Next get all thumbnails with no time threshold.
        results.append(contentsOf: try baseQuery()
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == true)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.minRetryTimestamp) >= thumbnailMinRetryTimestampThreshold)
            .fetchAll(tx.database)
        )
        if results.count == count {
            return results
        }

        // Lastly get all fullsize with no time threshold.
        results.append(contentsOf: try baseQuery()
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == false)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.minRetryTimestamp) >= fullsizeMinRetryTimestampThreshold)
            .fetchAll(tx.database)
        )
        return results
    }

    public func hasAnyReadyDownloads(tx: DBReadTransaction) throws -> Bool {
        return try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.state) == QueuedBackupAttachmentDownload.State.ready.rawValue)
            .isEmpty(tx.database)
            .negated
    }

    public func markDone(
        attachmentId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBWriteTransaction
    ) throws {
        var query = QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == attachmentId)

        // If not a thumbnail, mark both fullsize and thumbnail done, as we never
        // need a thumbnail after we have the fullsize download.
        if thumbnail {
            query = query.filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == true)
        }
        try query.updateAll(
            tx.database,
            [Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                .set(to: QueuedBackupAttachmentDownload.State.done.rawValue)
            ]
        )
    }

    public func markIneligible(
        attachmentId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBWriteTransaction
    ) throws {
        try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == attachmentId)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == thumbnail)
            .updateAll(
                tx.database,
                [Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                    .set(to: QueuedBackupAttachmentDownload.State.ineligible.rawValue)
                ]
            )
    }

    public func remove(
        attachmentId: Attachment.IDType,
        thumbnail: Bool,
        tx: DBWriteTransaction
    ) throws {
        try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == attachmentId)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.isThumbnail) == thumbnail)
            .deleteAll(tx.database)
    }

    public func removeAll(tx: DBWriteTransaction) throws {
        try QueuedBackupAttachmentDownload.deleteAll(tx.database)
    }

    public func markAllMediaTierFullsizeDownloadsIneligible(
        olderThan timestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.state) ==
                    QueuedBackupAttachmentDownload.State.ready.rawValue)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.canDownloadFromMediaTier) == true)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.maxOwnerTimestamp) != nil)
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.maxOwnerTimestamp) < timestamp)
            .updateAll(
                tx.database,
                [Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                    .set(to: QueuedBackupAttachmentDownload.State.ineligible.rawValue)
                ]
            )
    }

    public func markAllIneligibleReady(tx: DBWriteTransaction) throws {
        try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.state) ==
                    QueuedBackupAttachmentDownload.State.ineligible.rawValue)
            .updateAll(
                tx.database,
                [Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                    .set(to: QueuedBackupAttachmentDownload.State.ready.rawValue)
                ]
            )
    }

    public func markAllReadyIneligible(tx: DBWriteTransaction) throws {
        try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.state) ==
                    QueuedBackupAttachmentDownload.State.ready.rawValue)
            .updateAll(
                tx.database,
                [Column(QueuedBackupAttachmentDownload.CodingKeys.state)
                    .set(to: QueuedBackupAttachmentDownload.State.ineligible.rawValue)
                ]
            )
    }

    public func deleteAllDone(tx: DBWriteTransaction) throws {
        try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.state) ==
                    QueuedBackupAttachmentDownload.State.done.rawValue)
            .deleteAll(tx.database)
    }

    public func computeEstimatedFinishedByteCount(tx: DBReadTransaction) throws -> UInt64? {
        try UInt64.fetchOne(tx.database, sql: """
            SELECT SUM(\(QueuedBackupAttachmentDownload.CodingKeys.estimatedByteCount.rawValue))
            FROM \(QueuedBackupAttachmentDownload.databaseTableName)
            WHERE \(QueuedBackupAttachmentDownload.CodingKeys.state.rawValue) = \(QueuedBackupAttachmentDownload.State.done.rawValue);
            """
        )
    }

    public func computeEstimatedRemainingByteCount(tx: DBReadTransaction) throws -> UInt64? {
        try UInt64.fetchOne(tx.database, sql: """
            SELECT SUM(\(QueuedBackupAttachmentDownload.CodingKeys.estimatedByteCount.rawValue))
            FROM \(QueuedBackupAttachmentDownload.databaseTableName)
            WHERE \(QueuedBackupAttachmentDownload.CodingKeys.state.rawValue) = \(QueuedBackupAttachmentDownload.State.ready.rawValue);
            """
        )
    }

    private let isQueueSuspendedKey = "isQueueSuspendedKey"

    public func setIsQueueSuspended(_ isSuspended: Bool, tx: DBWriteTransaction) {
        kvStore.setBool(isSuspended, key: isQueueSuspendedKey, transaction: tx)
        tx.addSyncCompletion {
            NotificationCenter.default.post(name: .backupAttachmentDownloadQueueSuspensionStatusDidChange, object: nil)
        }
    }

    public func isQueueSuspended(tx: DBReadTransaction) -> Bool {
        kvStore.getBool(isQueueSuspendedKey, defaultValue: false, transaction: tx)
    }

    private let didDismissDownloadCompleteBannerKey = "didDismissDownloadCompleteBannerKey"

    public func getDidDismissDownloadCompleteBanner(tx: DBReadTransaction) -> Bool {
        return kvStore.getBool(didDismissDownloadCompleteBannerKey, defaultValue: false, transaction: tx)
    }

    public func setDidDismissDownloadCompleteBanner(tx: DBWriteTransaction) {
        kvStore.setBool(true, key: didDismissDownloadCompleteBannerKey, transaction: tx)
    }
}

public extension QueuedBackupAttachmentDownload {

    static func estimatedByteCount(
        attachment: Attachment,
        reference: AttachmentReference?,
        isThumbnail: Bool,
        canDownloadFromMediaTier: Bool
    ) -> UInt32 {
        if isThumbnail {
            // We don't know how big the thumbnail will be; just estimate
            // it to be its largest allowed size.
            return Cryptography.estimatedMediaTierCDNSize(
                unencryptedSize: UInt32(AttachmentThumbnailQuality.estimatedMaxBackupThumbnailFilesize)
            )
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
                    ?? attachment.transitTierInfo?.unencryptedByteCount
                    ?? reference?.sourceUnencryptedByteCount
            {
                return Cryptography.estimatedMediaTierCDNSize(
                    unencryptedSize: unencryptedByteCount
                )
            } else if
                let unencryptedByteCount =
                    attachment.transitTierInfo?.unencryptedByteCount
                    ?? attachment.mediaTierInfo?.unencryptedByteCount
                    ?? reference?.sourceUnencryptedByteCount
            {
                return Cryptography.estimatedTransitTierCDNSize(
                    unencryptedSize: unencryptedByteCount
                )
            } else {
                return 0
            }
        }
    }
}
