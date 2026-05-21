//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

/// This store holds a record of sticker packs that have been restored from
/// a backup, but whose full data has not been downloaded.
/// Post-restore, items listed here will be asynchronously passed to
/// StickerManager, downloaded, and persisted as usable StickerPack objects.
public struct BackupStickerPackDownloadStore {

    private typealias Record = QueuedBackupStickerPackDownload

    /// "Enqueue" a sticker pack from a backup for download.
    /// Doesn't actually trigger a download; this is delegated to the TaskQueueLoader
    /// in StickerManager
    public func enqueue(packId: Data, packKey: Data, tx: DBWriteTransaction) {
        failIfThrows {
            // If this record is already in the queue, don't insert a second copy
            if
                let _ = try QueuedAttachmentDownloadRecord
                    .filter(Column(Record.CodingKeys.packId) == packId)
                    .fetchOne(tx.database)
            {
                return
            }

            var record = Record(packId: packId, packKey: packKey)
            try record.insert(tx.database)
        }
    }

    /// Read rows off the queue one by one, calling the block for each.
    /// - Parameter block
    /// A block executed for each enumerated record. Returns `true` if
    /// enumeration should continue, and `false` otherwise.
    public func iterateAllEnqueued(
        tx: DBReadTransaction,
        block: (QueuedBackupStickerPackDownload) throws(CancellationError) -> Bool,
    ) throws(CancellationError) {
        var cursor = FailIfThrowsRecordCursor {
            try Record
                .order([Column(Record.CodingKeys.id).desc])
                .fetchCursor(tx.database)
        }

        while let record = cursor.next(), try block(record) {}
    }

    /// Return the top `count` rows of the download queue.
    public func peek(
        count: UInt,
        tx: DBReadTransaction,
    ) -> [QueuedBackupStickerPackDownload] {
        return failIfThrows {
            try Record
                .order([Column(Record.CodingKeys.id).asc])
                .limit(Int(count))
                .fetchAll(tx.database)
        }
    }

    /// Remove the record from the download queue.
    public func removeRecordFromQueue(
        record: QueuedBackupStickerPackDownload,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try Record
                .filter(Column(Record.CodingKeys.id) == record.id)
                .deleteAll(tx.database)
        }
    }
}
