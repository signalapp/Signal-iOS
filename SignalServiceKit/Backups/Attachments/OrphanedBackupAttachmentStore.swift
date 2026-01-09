//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public class OrphanedBackupAttachmentStore {

    public init() {}

    public func insert(
        _ record: inout OrphanedBackupAttachment,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try record.insert(tx.database)
        }
    }

    /// Read the next highest priority (FIFO) records off the table, up to count.
    /// Returns an empty array if the table is empty.
    public func peek(
        count: UInt,
        tx: DBReadTransaction,
    ) -> [OrphanedBackupAttachment] {
        let query = OrphanedBackupAttachment
            // We want to dequeue in insertion order.
            .order([Column(OrphanedBackupAttachment.CodingKeys.id).asc])
            .limit(Int(count))

        return failIfThrows {
            try query.fetchAll(tx.database)
        }
    }

    public func hasPendingDelete(
        forMediaId mediaId: Data,
        tx: DBReadTransaction,
    ) -> Bool {
        let query = OrphanedBackupAttachment
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == mediaId)

        return failIfThrows {
            try !query.isEmpty(tx.database)
        }
    }

    public func enumerateMediaNamesPendingDelete(
        tx: DBReadTransaction,
        block: (String, inout Bool) -> Void,
    ) {
        let query = OrphanedBackupAttachment
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == nil)
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaName) != nil)

        failIfThrows {
            let cursor = try query.fetchCursor(tx.database)

            var stop = false
            while
                !stop,
                let next = try cursor.next()?.mediaName
            {
                block(next, &stop)
            }
        }
    }

    /// Remove any tasks for deleting a fullsize media tier upload with
    /// the given media name and/or derived media id.
    public func removeThumbnail(
        fullsizeMediaName: String,
        thumbnailMediaId: Data,
        tx: DBWriteTransaction,
    ) {
        let mediaNameQuery = OrphanedBackupAttachment
            // Records for thumbnails are enqueued with the fullsize's media name
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaName) == fullsizeMediaName)
            .filter(Column(OrphanedBackupAttachment.CodingKeys.type)
                == OrphanedBackupAttachment.SizeType.thumbnail.rawValue)

        let mediaIdQuery = OrphanedBackupAttachment
            // No need to filter by type; matching the mediaId is sufficient
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == thumbnailMediaId)

        failIfThrows {
            try mediaNameQuery.deleteAll(tx.database)
            try mediaIdQuery.deleteAll(tx.database)
        }
    }

    /// Remove any tasks for deleting a fullsize media tier upload with
    /// the given media name (fullsize, not the thumbnail media name)
    /// and/or derived thumbnail media id.
    public func removeFullsize(
        mediaName: String,
        fullsizeMediaId: Data,
        tx: DBWriteTransaction,
    ) {
        let mediaNameQuery = OrphanedBackupAttachment
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaName) == mediaName)
            .filter(Column(OrphanedBackupAttachment.CodingKeys.type)
                == OrphanedBackupAttachment.SizeType.fullsize.rawValue)
        let mediaIdQuery = OrphanedBackupAttachment
            // No need to filter by type; matching the mediaId is sufficient
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == fullsizeMediaId)

        failIfThrows {
            try mediaNameQuery.deleteAll(tx.database)
            try mediaIdQuery.deleteAll(tx.database)
        }
    }

    /// Remove the task from the queue. Should be called once deleted on the cdn (or permanently failed).
    public func remove(
        _ record: OrphanedBackupAttachment,
        tx: DBWriteTransaction,
    ) {
        failIfThrows {
            try record.delete(tx.database)
        }
    }
}
