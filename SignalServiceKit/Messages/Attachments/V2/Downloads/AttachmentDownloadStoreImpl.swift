//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class AttachmentDownloadStoreImpl: AttachmentDownloadStore {

    private let dateProvider: DateProvider

    public init(
        dateProvider: @escaping DateProvider
    ) {
        self.dateProvider = dateProvider
    }

    public typealias Record = QueuedAttachmentDownloadRecord

    public func fetchRecord(
        id: QueuedAttachmentDownloadRecord.IDType,
        tx: DBReadTransaction
    ) throws -> QueuedAttachmentDownloadRecord? {
        return try fetchRecord(id: id, db: tx.db)
    }

    internal func fetchRecord(
        id: QueuedAttachmentDownloadRecord.IDType,
        db: Database
    ) throws -> QueuedAttachmentDownloadRecord? {
        return try Record.fetchOne(db, key: id)
    }

    public func isAttachmentEnqueuedForDownload(
        id: Attachment.IDType,
        tx: DBReadTransaction
    ) throws -> Bool {
        return try isAttachmentEnqueuedForDownload(id: id, db: tx.db)
    }

    internal func isAttachmentEnqueuedForDownload(
        id: Attachment.IDType,
        db: Database
    ) throws -> Bool {
        return try Record
            .filter(Column(.attachmentId) == id)
            .isEmpty(db)
            .negated
    }

    public func peek(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [QueuedAttachmentDownloadRecord] {
        try peek(count: count, db: tx.db)
    }

    internal func peek(
        count: UInt,
        db: Database
    ) throws -> [QueuedAttachmentDownloadRecord] {
        try Record
            .filter(Column(.minRetryTimestamp) == nil)
            .order([Column(.priority).desc, Column(.id).asc])
            .limit(Int(count))
            .fetchAll(db)
    }

    public func nextRetryTimestamp(tx: any DBReadTransaction) throws -> UInt64? {
        try nextRetryTimestamp(db: tx.db)
    }

    internal func nextRetryTimestamp(db: Database) throws -> UInt64? {
        try Record
            .filter(Column(.minRetryTimestamp) != nil)
            .select([min(Column(.minRetryTimestamp))], as: UInt64.self)
            .fetchOne(db)
    }

    public func enqueueDownloadOfAttachment(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) throws {
        try enqueueDownloadOfAttachment(
            withId: attachmentId,
            source: source,
            priority: priority,
            db: tx.db
        )
    }

    internal func enqueueDownloadOfAttachment(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        priority: AttachmentDownloadPriority,
        db: Database
    ) throws {
        // Check for existing enqueued rows.
        let existingRow = try Record
            .filter(Column(.attachmentId) == attachmentId)
            .filter(Column(.sourceType) == source.rawValue)
            .fetchOne(db)
        if var existingRow {
            try self.updatePriorityIfNeeded(&existingRow, priority: priority, db: db)
            return
        }

        switch priority {
        case .default:
            // Only allow a max amount of default enqueued rows.
            let defaultPriorityEnqueuedCount = try Record
                .filter(Column(.priority) == priority.rawValue)
                .fetchCount(db)

            if defaultPriorityEnqueuedCount >= Constants.maxEnqueuedCountDefaultPriority {
                // Remove the first ones sorted by insertion order.
                try Record
                    .filter(Column(.priority) == priority.rawValue)
                    .order(Column(.id).asc)
                    .limit(1 + defaultPriorityEnqueuedCount - Constants.maxEnqueuedCountDefaultPriority)
                    .fetchAll(db)
                    .forEach { try $0.delete(db) }
            }

        case .userInitiated, .localClone:
            break
        }

        var newRecord = Record.forNewDownload(
            ofAttachmentWithId: attachmentId,
            priority: priority,
            sourceType: source
        )
        try newRecord.insert(db)
    }

    public func removeAttachmentFromQueue(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        tx: DBWriteTransaction
    ) throws {
        try removeAttachmentFromQueue(withId: attachmentId, source: source, db: tx.db)
    }

    internal func removeAttachmentFromQueue(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        db: Database
    ) throws {
        try Record
            .filter(Column(.attachmentId) == attachmentId)
            .filter(Column(.sourceType) == source.rawValue)
            .deleteAll(db)
    }

    public func markQueuedDownloadFailed(
        withId id: QueuedAttachmentDownloadRecord.IDType,
        minRetryTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        try markQueuedDownloadFailed(withId: id, minRetryTimestamp: minRetryTimestamp, db: tx.db)
    }

    internal func markQueuedDownloadFailed(
        withId id: QueuedAttachmentDownloadRecord.IDType,
        minRetryTimestamp: UInt64,
        db: Database
    ) throws {
        try Record
            .filter(key: id)
            .updateAll(db, [
                Column(.minRetryTimestamp).set(to: minRetryTimestamp),
                Column(.retryAttempts).set(to: Column(.retryAttempts) + 1)
            ])
    }

    public func updateRetryableDownloads(tx: DBWriteTransaction) throws {
        try updateRetryableDownloads(db: tx.db)
    }

    internal func updateRetryableDownloads(db: Database) throws {
        try Record
            .filter(Column(.minRetryTimestamp) != nil)
            .filter(Column(.minRetryTimestamp) <= dateProvider().ows_millisecondsSince1970)
            .updateAll(db, Column(.minRetryTimestamp).set(to: nil))
    }

    // MARK: - Private

    /// If the current priority is lower than the provided priority, updates with the new priority and makes retryable.
    private func updatePriorityIfNeeded(
        _ record: inout Record,
        priority: AttachmentDownloadPriority,
        db: Database
    ) throws {
        if record.priority.rawValue < priority.rawValue {
            record.priority = priority
            record.minRetryTimestamp = nil
            try record.update(db)
        } else if priority.rawValue >= AttachmentDownloadPriority.userInitiated.rawValue {
            // If we re-bump with user-initiated priority, mark it as needing retry.
            record.minRetryTimestamp = nil
            try record.update(db)
        }
    }

    // MARK: Constants

    private enum Constants {
        static let maxEnqueuedCountDefaultPriority = 50
    }
}

fileprivate extension DBReadTransaction {

    var db: Database { SDSDB.shimOnlyBridge(self).unwrapGrdbRead.database }
}

fileprivate extension DBWriteTransaction {

    var db: Database { SDSDB.shimOnlyBridge(self).unwrapGrdbWrite.database }
}

extension Column {

    fileprivate init(_ codingKey: QueuedAttachmentDownloadRecord.CodingKeys) {
        self.init(codingKey.stringValue)
    }
}
