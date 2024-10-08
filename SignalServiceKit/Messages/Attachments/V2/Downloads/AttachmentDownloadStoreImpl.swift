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
        return try Record.fetchOne(tx.databaseConnection, key: id)
    }

    public func enqueuedDownload(
        for id: Attachment.IDType,
        tx: DBReadTransaction
    ) throws -> QueuedAttachmentDownloadRecord? {
        return try Record
            .filter(Column(.attachmentId) == id)
            .fetchOne(tx.databaseConnection)
    }

    public func peek(
        count: UInt,
        tx: DBReadTransaction
    ) throws -> [QueuedAttachmentDownloadRecord] {
        try Record
            .filter(Column(.minRetryTimestamp) == nil)
            .order([Column(.priority).desc, Column(.id).asc])
            .limit(Int(count))
            .fetchAll(tx.databaseConnection)
    }

    public func nextRetryTimestamp(tx: any DBReadTransaction) throws -> UInt64? {
        try Record
            .filter(Column(.minRetryTimestamp) != nil)
            .select([min(Column(.minRetryTimestamp))], as: UInt64.self)
            .fetchOne(tx.databaseConnection)
    }

    public func enqueueDownloadOfAttachment(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) throws {
        // Check for existing enqueued rows.
        let existingRow = try Record
            .filter(Column(.attachmentId) == attachmentId)
            .filter(Column(.sourceType) == source.rawValue)
            .fetchOne(tx.databaseConnection)
        if var existingRow {
            try self.updatePriorityIfNeeded(&existingRow, priority: priority, tx: tx)
            return
        }

        switch priority {
        case .default:
            // Only allow a max amount of default enqueued rows.
            let defaultPriorityEnqueuedCount = try Record
                .filter(Column(.priority) == priority.rawValue)
                .fetchCount(tx.databaseConnection)

            if defaultPriorityEnqueuedCount >= Constants.maxEnqueuedCountDefaultPriority {
                // Remove the first ones sorted by insertion order.
                try Record
                    .filter(Column(.priority) == priority.rawValue)
                    .order(Column(.id).asc)
                    .limit(1 + defaultPriorityEnqueuedCount - Constants.maxEnqueuedCountDefaultPriority)
                    .fetchAll(tx.databaseConnection)
                    .forEach { try $0.delete(tx.databaseConnection) }
            }

        case .userInitiated, .localClone, .backupRestoreHigh, .backupRestoreLow:
            break
        }

        var newRecord = Record.forNewDownload(
            ofAttachmentWithId: attachmentId,
            priority: priority,
            sourceType: source
        )
        try newRecord.insert(tx.databaseConnection)
    }

    public func removeAttachmentFromQueue(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        tx: DBWriteTransaction
    ) throws {
        try Record
            .filter(Column(.attachmentId) == attachmentId)
            .filter(Column(.sourceType) == source.rawValue)
            .deleteAll(tx.databaseConnection)
    }

    public func markQueuedDownloadFailed(
        withId id: QueuedAttachmentDownloadRecord.IDType,
        minRetryTimestamp: UInt64,
        tx: DBWriteTransaction
    ) throws {
        try Record
            .filter(key: id)
            .updateAll(tx.databaseConnection, [
                Column(.minRetryTimestamp).set(to: minRetryTimestamp),
                Column(.retryAttempts).set(to: Column(.retryAttempts) + 1)
            ])
    }

    public func updateRetryableDownloads(tx: DBWriteTransaction) throws {
        try Record
            .filter(Column(.minRetryTimestamp) != nil)
            .filter(Column(.minRetryTimestamp) <= dateProvider().ows_millisecondsSince1970)
            .updateAll(tx.databaseConnection, Column(.minRetryTimestamp).set(to: nil))
    }

    // MARK: - Private

    /// If the current priority is lower than the provided priority, updates with the new priority and makes retryable.
    private func updatePriorityIfNeeded(
        _ record: inout Record,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) throws {
        if record.priority.rawValue < priority.rawValue {
            record.priority = priority
            record.minRetryTimestamp = nil
            try record.update(tx.databaseConnection)
        } else if priority.rawValue >= AttachmentDownloadPriority.userInitiated.rawValue {
            // If we re-bump with user-initiated priority, mark it as needing retry.
            record.minRetryTimestamp = nil
            try record.update(tx.databaseConnection)
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
