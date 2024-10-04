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

    /// Remove the download from the queue. Should be called once deleted on the cdn (or permanently failed).
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
        let db = databaseConnection(tx)
        try record.insert(db)
    }

    public func peek(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [OrphanedBackupAttachment] {
        let db = databaseConnection(tx)
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
        let db = databaseConnection(tx)
        try record.delete(db)
    }

    public func removeAll(tx: DBWriteTransaction) throws {
        let db = databaseConnection(tx)
        try OrphanedBackupAttachment.deleteAll(db)
    }
}

#if TESTABLE_BUILD

open class OrphanedBackupAttachmentStoreMock: OrphanedBackupAttachmentStore {

    public init() {}

    public var records = [OrphanedBackupAttachment]()

    open func insert(_ record: inout OrphanedBackupAttachment, tx: any DBWriteTransaction) throws {
        if records.contains(where: {
            $0.mediaName == record.mediaName && $0.cdnNumber == record.cdnNumber
        }) {
            return
        }
        records.append(record)
    }

    open func peek(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [OrphanedBackupAttachment] {
        return Array(records.prefix(Int(count)))
    }

    open func remove(
        _ record: OrphanedBackupAttachment,
        tx: DBWriteTransaction
    ) throws {
        records.removeAll(where: { $0.id == record.id })
    }

    open func removeAll(tx: DBWriteTransaction) throws {
        records = []
    }
}

#endif
