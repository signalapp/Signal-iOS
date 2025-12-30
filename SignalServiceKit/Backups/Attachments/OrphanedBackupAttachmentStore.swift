//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol OrphanedBackupAttachmentStore {

    func insert(_ record: inout OrphanedBackupAttachment, tx: DBWriteTransaction) throws

    /// Read the next highest priority (FIFO) records off the table, up to count.
    /// Returns an empty array if the table is empty.
    func peek(count: UInt, tx: DBReadTransaction) throws -> [OrphanedBackupAttachment]

    func hasPendingDelete(forMediaId mediaId: Data, tx: DBReadTransaction) throws -> Bool

    func enumerateMediaNamesPendingDelete(tx: DBReadTransaction, block: (String, _ stop: inout Bool) -> Void) throws

    /// Remove any tasks for deleting a fullsize media tier upload with
    /// the given media name and/or derived media id.
    func removeThumbnail(
        fullsizeMediaName: String,
        thumbnailMediaId: Data,
        tx: DBWriteTransaction,
    ) throws

    /// Remove any tasks for deleting a fullsize media tier upload with
    /// the given media name (fullsize, not the thumbnail media name)
    /// and/or derived thumbnail media id.
    func removeFullsize(
        mediaName: String,
        fullsizeMediaId: Data,
        tx: DBWriteTransaction,
    ) throws

    /// Remove the task from the queue. Should be called once deleted on the cdn (or permanently failed).
    func remove(
        _ record: OrphanedBackupAttachment,
        tx: DBWriteTransaction,
    ) throws

    /// Remove all records from the table.
    /// Called if e.g. a backup subscription expires or is cancelled.
    func removeAll(tx: DBWriteTransaction) throws
}

public class OrphanedBackupAttachmentStoreImpl: OrphanedBackupAttachmentStore {

    public init() {}

    public func insert(_ record: inout OrphanedBackupAttachment, tx: DBWriteTransaction) throws {
        let db = tx.database
        try record.insert(db)
    }

    public func peek(
        count: UInt,
        tx: DBReadTransaction,
    ) throws -> [OrphanedBackupAttachment] {
        let db = tx.database
        return try OrphanedBackupAttachment
            // We want to dequeue in insertion order.
            .order([Column(OrphanedBackupAttachment.CodingKeys.id).asc])
            .limit(Int(count))
            .fetchAll(db)
    }

    public func hasPendingDelete(forMediaId mediaId: Data, tx: DBReadTransaction) throws -> Bool {
        return try OrphanedBackupAttachment
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == mediaId)
            .isEmpty(tx.database)
            .negated
    }

    public func enumerateMediaNamesPendingDelete(tx: DBReadTransaction, block: (String, _ stop: inout Bool) -> Void) throws {
        let cursor = try OrphanedBackupAttachment
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == nil)
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaName) != nil)
            .fetchCursor(tx.database)

        var stop = false
        while !stop {
            guard let next = try cursor.next()?.mediaName else {
                return
            }
            block(next, &stop)
        }
    }

    public func removeThumbnail(
        fullsizeMediaName: String,
        thumbnailMediaId: Data,
        tx: DBWriteTransaction,
    ) throws {
        try OrphanedBackupAttachment
            // Records for thumbnails are enqueued with the fullsize's media name
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaName) == fullsizeMediaName)
            .filter(Column(OrphanedBackupAttachment.CodingKeys.type)
                == OrphanedBackupAttachment.SizeType.thumbnail.rawValue)
            .deleteAll(tx.database)
        try OrphanedBackupAttachment
            // No need to filter by type; matching the mediaId is sufficient
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == thumbnailMediaId)
            .deleteAll(tx.database)
    }

    public func removeFullsize(
        mediaName: String,
        fullsizeMediaId: Data,
        tx: DBWriteTransaction,
    ) throws {
        try OrphanedBackupAttachment
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaName) == mediaName)
            .filter(Column(OrphanedBackupAttachment.CodingKeys.type)
                == OrphanedBackupAttachment.SizeType.fullsize.rawValue)
            .deleteAll(tx.database)
        try OrphanedBackupAttachment
            // No need to filter by type; matching the mediaId is sufficient
            .filter(Column(OrphanedBackupAttachment.CodingKeys.mediaId) == fullsizeMediaId)
            .deleteAll(tx.database)
    }

    public func remove(
        _ record: OrphanedBackupAttachment,
        tx: DBWriteTransaction,
    ) throws {
        let db = tx.database
        try record.delete(db)
    }

    public func removeAll(tx: DBWriteTransaction) throws {
        let db = tx.database
        try OrphanedBackupAttachment.deleteAll(db)
    }
}
