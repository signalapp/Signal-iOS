//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// This store holds a record of sticker packs that have been restored from
/// a backup, but whose full data has not been downloaded.
/// Post-restore, items listed here will be asynchronously passed to
/// StickerManager, downloaded, and persisted as usable StickerPack objects.
public protocol BackupStickerPackDownloadStore {

    /// "Enqueue" a sticker pack from a backup for download.
    /// Doesn't actually trigger a download; this is delegated to the TaskQueueLoader
    /// in StickerManager
    func enqueue(
        packId: Data,
        packKey: Data,
        tx: DBWriteTransaction
    ) throws

    /// Read rows off the queue one by one, calling the block for each.
    func iterateAllEnqueued(
        tx: DBReadTransaction,
        block: (QueuedBackupStickerPackDownload
    ) throws -> Void) throws

    /// Return the top `count` rows of the download queue.
    func peek(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [QueuedBackupStickerPackDownload]

    /// Remove the record from the download queue.
    func removeRecordFromQueue(
        record: QueuedBackupStickerPackDownload,
        tx: DBWriteTransaction
    ) throws
}

public class BackupStickerPackDownloadStoreImpl: BackupStickerPackDownloadStore {

    public typealias Record = QueuedBackupStickerPackDownload

    public func enqueue(packId: Data, packKey: Data, tx: DBWriteTransaction) throws {
        let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database
        try enqueue(packId: packId, packKey: packKey, db: db)
    }

    internal func enqueue(packId: Data, packKey: Data, db: Database) throws {
        var record = Record(packId: packId, packKey: packKey)

        // If this record is already in the queue, don't insert a second copy
        if let _ = try QueuedAttachmentDownloadRecord
            .filter(Column(Record.CodingKeys.packId) == packId)
            .fetchOne(db)
        {
            return
        }

        try record.insert(db)
    }

    public func iterateAllEnqueued(
        tx: DBReadTransaction,
        block: (QueuedBackupStickerPackDownload) throws -> Void
    ) throws {
        let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database
        try iterateAllEnqueued(db: db, block: block)
    }

    internal func iterateAllEnqueued(
        db: Database,
        block: (QueuedBackupStickerPackDownload) throws -> Void
    ) throws {
         let cursor = try Record
            .order([Column(Record.CodingKeys.id).desc])
            .fetchCursor(db)

        while let record = try cursor.next() {
            try block(record)
        }
    }

    public func peek(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [QueuedBackupStickerPackDownload] {
        let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbRead.database
        return try peek(count: count, db: db)
    }

    internal func peek(
        count: UInt,
        db: Database
    ) throws -> [QueuedBackupStickerPackDownload] {
        try Record
            .order([Column(Record.CodingKeys.id).asc])
            .limit(Int(count))
            .fetchAll(db)
    }

    public func removeRecordFromQueue(
        record: QueuedBackupStickerPackDownload,
        tx: DBWriteTransaction
    ) throws {
        let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database
        try removeRecordFromQueue(record: record, db: db)
    }

    internal func removeRecordFromQueue(
        record: QueuedBackupStickerPackDownload,
        db: Database
    ) throws {
        try Record
            .filter(Column(Record.CodingKeys.id) == record.id)
            .deleteAll(db)
    }
}
