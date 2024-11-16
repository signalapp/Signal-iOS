//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol BackupAttachmentDownloadStore {

    /// If true, keep a copy of all media on local device, even if media backups are enabled.
    /// If false, keep only the past N days of media locally and rely on backups for the rest.
    func getShouldStoreAllMediaLocally(tx: DBReadTransaction) -> Bool

    /// See ``getShouldStoreAllMediaLocally``.
    func setShouldStoreAllMediaLocally(_ newValue: Bool, tx: DBWriteTransaction)

    /// "Enqueue" an attachment from a backup for download (using its reference).
    ///
    /// If the same attachment pointed to by the reference is already enqueued, updates it to the greater
    /// of the existing and new reference's timestamp.
    ///
    /// Doesn't actually trigger a download; callers must later call `dequeueAndClearTable` to insert
    /// rows into the normal AttachmentDownloadQueue, as this table serves only as an intermediary.
    func enqueue(_ reference: AttachmentReference, tx: DBWriteTransaction) throws

    /// Read the next highest priority downloads off the queue, up to count.
    /// Returns an empty array if nothing is left to download.
    func peek(count: UInt, tx: DBReadTransaction) throws -> [QueuedBackupAttachmentDownload]

    /// Remove the download from the queue. Should be called once downloaded (or permanently failed).
    func removeQueuedDownload(
        _ record: QueuedBackupAttachmentDownload,
        tx: DBWriteTransaction
    ) throws

    /// Remove all enqueued downloads from the table.
    func removeAll(tx: DBWriteTransaction) throws
}

public class BackupAttachmentDownloadStoreImpl: BackupAttachmentDownloadStore {

    private let kvStore: KeyValueStore

    public init() {
        self.kvStore = KeyValueStore(collection: "BackupAttachmentDownloadStoreImpl")
    }

    private let shouldStoreAllMediaLocallyKey = "shouldStoreAllMediaLocallyKey"

    public func getShouldStoreAllMediaLocally(tx: any DBReadTransaction) -> Bool {
        return kvStore.getBool(shouldStoreAllMediaLocallyKey, defaultValue: true, transaction: tx)
    }

    public func setShouldStoreAllMediaLocally(_ newValue: Bool, tx: any DBWriteTransaction) {
        kvStore.setBool(newValue, key: shouldStoreAllMediaLocallyKey, transaction: tx)
    }

    public func enqueue(_ reference: AttachmentReference, tx: any DBWriteTransaction) throws {
        let db = tx.databaseConnection
        let timestamp: UInt64? = {
            switch reference.owner {
            case .message(.bodyAttachment(let metadata)):
                return metadata.receivedAtTimestamp
            case .message(.contactAvatar(let metadata)):
                return metadata.receivedAtTimestamp
            case .message(.linkPreview(let metadata)):
                return metadata.receivedAtTimestamp
            case .message(.oversizeText(let metadata)):
                return metadata.receivedAtTimestamp
            case .message(.quotedReply(let metadata)):
                return metadata.receivedAtTimestamp
            case .message(.sticker(let metadata)):
                return metadata.receivedAtTimestamp
            case .storyMessage, .thread:
                return nil
            }
        }()

        let existingRecord = try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == reference.attachmentRowId)
            .fetchOne(db)

        if
            let existingRecord,
            existingRecord.timestamp ?? .max < timestamp ?? .max
        {
            // If we have an existing record with a smaller timestamp,
            // delete it in favor of the new row we are about to insert.
            // (nil timestamp counts as the largest timestamp)
            try existingRecord.delete(db)
        } else if existingRecord != nil {
            // Otherwise we had an existing record with a larger
            // timestamp, stop.
            return
        }

        var record = QueuedBackupAttachmentDownload(
            attachmentRowId: reference.attachmentRowId,
            timestamp: timestamp
        )
        try record.insert(db)
    }

    public func peek(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [QueuedBackupAttachmentDownload] {
        let db = tx.databaseConnection
        return try QueuedBackupAttachmentDownload
            // We want to dequeue in _reverse_ insertion order.
            .order([Column(QueuedBackupAttachmentDownload.CodingKeys.id).desc])
            .limit(Int(count))
            .fetchAll(db)
    }

    public func removeQueuedDownload(
        _ record: QueuedBackupAttachmentDownload,
        tx: DBWriteTransaction
    ) throws {
        let db = tx.databaseConnection
        try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.id) == record.id)
            .deleteAll(db)
    }

    public func removeAll(tx: DBWriteTransaction) throws {
        try QueuedBackupAttachmentDownload.deleteAll(tx.databaseConnection)
    }
}
