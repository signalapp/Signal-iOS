//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public struct AttachmentDownloadStore {

    private let dateProvider: DateProvider

    public init(
        dateProvider: @escaping DateProvider,
    ) {
        self.dateProvider = dateProvider
    }

    private typealias Record = QueuedAttachmentDownloadRecord

    public func fetchRecord(
        id: QueuedAttachmentDownloadRecord.IDType,
        tx: DBReadTransaction,
    ) -> QueuedAttachmentDownloadRecord? {
        return failIfThrows {
            try QueuedAttachmentDownloadRecord.fetchOne(tx.database, key: id)
        }
    }

    public func enqueuedDownload(
        for id: Attachment.IDType,
        tx: DBReadTransaction,
    ) -> QueuedAttachmentDownloadRecord? {
        let query = QueuedAttachmentDownloadRecord
            .filter(Column(.attachmentId) == id)

        return failIfThrows {
            try query.fetchOne(tx.database)
        }
    }

    /// Fetch the next N highest priority downloads off the queue in FIFO order.
    public func peek(
        count: UInt,
        tx: DBReadTransaction,
    ) -> [QueuedAttachmentDownloadRecord] {
        let query = QueuedAttachmentDownloadRecord
            .filter(Column(.minRetryTimestamp) == nil)
            .order([Column(.priority).desc, Column(.id).asc])
            .limit(Int(count))

        return failIfThrows {
            try query.fetchAll(tx.database)
        }
    }

    /// Return the lowest non-nil `minRetryTimestamp`.
    public func nextRetryTimestamp(tx: DBReadTransaction) -> UInt64? {
        let query = QueuedAttachmentDownloadRecord
            .filter(Column(.minRetryTimestamp) != nil)
            .select([min(Column(.minRetryTimestamp))], as: UInt64.self)

        return failIfThrows {
            try query.fetchOne(tx.database)
        }
    }

    /// Enqueues a target attachment (with a given source) for download at a given priority.
    ///
    /// If the attachment+source pair is already enqueued:
    /// * Does nothing if the existing one is at the same or higher priority
    /// * Replaces the existing one if the new one is at higher priority.
    ///
    /// Only allows 50 `default` priority attachments at a time; any more
    /// and it will remove existing ones from the queue (in FIFO order).
    ///
    /// Simply enqueues; wake up AttachmentDownloadManager to actually download off the queue.
    public func enqueueDownloadOfAttachment(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    ) {
        // Check for existing enqueued rows.
        let existingRowQuery = QueuedAttachmentDownloadRecord
            .filter(Column(.attachmentId) == attachmentId)
            .filter(Column(.sourceType) == source.rawValue)
        let existingRow = failIfThrows {
            try existingRowQuery.fetchOne(tx.database)
        }
        if var existingRow {
            updatePriorityIfNeeded(&existingRow, priority: priority, tx: tx)
            return
        }

        switch priority {
        case .default:
            // Only allow a max amount of default enqueued rows.
            let defaultPriorityEnqueuedCountQuery = QueuedAttachmentDownloadRecord
                .filter(Column(.priority) == priority.rawValue)
            let defaultPriorityEnqueuedCount = failIfThrows {
                try defaultPriorityEnqueuedCountQuery.fetchCount(tx.database)
            }

            if defaultPriorityEnqueuedCount >= Constants.maxEnqueuedCountDefaultPriority {
                // Remove the first ones sorted by insertion order.
                let excessDefaultPriorityDownloadsQuery = QueuedAttachmentDownloadRecord
                    .filter(Column(.priority) == priority.rawValue)
                    .order(Column(.id).asc)
                    .limit(1 + defaultPriorityEnqueuedCount - Constants.maxEnqueuedCountDefaultPriority)

                failIfThrows {
                    let excessDownloads = try excessDefaultPriorityDownloadsQuery.fetchAll(tx.database)
                    for download in excessDownloads {
                        try download.delete(tx.database)
                    }
                }
            }

        case .userInitiated, .localClone, .backupRestore:
            break
        }

        var newRecord = Record.forNewDownload(
            ofAttachmentWithId: attachmentId,
            priority: priority,
            sourceType: source,
        )
        failIfThrows {
            try newRecord.insert(tx.database)
        }
    }

    /// - SeeAlso ``markQueuedDownloadFailed(withId:minRetryTimestamp:tx:)``
    public func removeAttachmentFromQueue(
        withId attachmentId: Attachment.IDType,
        source: QueuedAttachmentDownloadRecord.SourceType,
        tx: DBWriteTransaction,
    ) {
        let query = QueuedAttachmentDownloadRecord
            .filter(Column(.attachmentId) == attachmentId)
            .filter(Column(.sourceType) == source.rawValue)

        failIfThrows {
            try query.deleteAll(tx.database)
        }
    }

    /// If the failure is permanent (no retry), use `removeAttachmentFromQueue` instead.
    public func markQueuedDownloadFailed(
        withId id: QueuedAttachmentDownloadRecord.IDType,
        minRetryTimestamp: UInt64,
        tx: DBWriteTransaction,
    ) {
        let query = QueuedAttachmentDownloadRecord
            .filter(key: id)

        failIfThrows {
            try query.updateAll(tx.database, [
                Column(.minRetryTimestamp).set(to: minRetryTimestamp),
                Column(.retryAttempts).set(to: Column(.retryAttempts) + 1),
            ])
        }
    }

    /// Update all downloads with`minRetryTimestamp` past the current timestamp,
    /// marking them retryable.
    public func updateRetryableDownloads(tx: DBWriteTransaction) {
        let query = QueuedAttachmentDownloadRecord
            .filter(Column(.minRetryTimestamp) != nil)
            .filter(Column(.minRetryTimestamp) <= dateProvider().ows_millisecondsSince1970)

        failIfThrows {
            try query.updateAll(tx.database, Column(.minRetryTimestamp).set(to: nil))
        }
    }

    // MARK: - Private

    /// If the current priority is lower than the provided priority, updates with the new priority and makes retryable.
    private func updatePriorityIfNeeded(
        _ record: inout QueuedAttachmentDownloadRecord,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    ) {
        if record.priority.rawValue < priority.rawValue {
            record.priority = priority
            record.minRetryTimestamp = nil
        } else if priority.rawValue >= AttachmentDownloadPriority.userInitiated.rawValue {
            // If we re-bump with user-initiated priority, mark it as needing retry.
            record.minRetryTimestamp = nil
        }

        failIfThrows {
            try record.update(tx.database)
        }
    }

    // MARK: Constants

    private enum Constants {
        static let maxEnqueuedCountDefaultPriority = 50
    }
}

extension Column {

    fileprivate init(_ codingKey: QueuedAttachmentDownloadRecord.CodingKeys) {
        self.init(codingKey.stringValue)
    }
}
