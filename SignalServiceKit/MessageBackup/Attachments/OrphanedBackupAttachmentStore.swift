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

    /// Remove the task from the queue. Should be called once deleted on the cdn (or permanently failed).
    func remove(
        _ record: OrphanedBackupAttachment,
        tx: DBWriteTransaction
    ) throws

    /// Remove all records from the table.
    /// Called if e.g. a backup subscription expires or is cancelled.
    func removeAll(tx: DBWriteTransaction) throws
}

public class OrphanedBackupAttachmentStoreImpl: OrphanedBackupAttachmentStore {

    public init() {}

    public func insert(_ record: inout OrphanedBackupAttachment, tx: any DBWriteTransaction) throws {
        let db = tx.databaseConnection
        try record.insert(db)
    }

    public func peek(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [OrphanedBackupAttachment] {
        let db = tx.databaseConnection
        return try OrphanedBackupAttachment
            // We want to dequeue in insertion order.
            .order([Column(OrphanedBackupAttachment.CodingKeys.id).asc])
            .limit(Int(count))
            .fetchAll(db)
    }

    public func remove(
        _ record: OrphanedBackupAttachment,
        tx: DBWriteTransaction
    ) throws {
        let db = tx.databaseConnection
        try record.delete(db)
    }

    public func removeAll(tx: DBWriteTransaction) throws {
        let db = tx.databaseConnection
        try OrphanedBackupAttachment.deleteAll(db)
    }
}
