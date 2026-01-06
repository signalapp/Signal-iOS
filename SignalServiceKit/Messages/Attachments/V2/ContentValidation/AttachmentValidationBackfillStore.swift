//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class AttachmentValidationBackfillStore {

    private let kvStore = KeyValueStore(collection: "AttachmentValidationBackfillStore")

    public init() {}

    /// If returns true, AttachmentValidationBackfillMigrator should be run.
    public func needsToRun(tx: DBReadTransaction) -> Bool {
        if !backfillsThatNeedEnqueuing(tx: tx).isEmpty {
            return true
        }
        if !getNextAttachmentIdBatch(tx: tx).isEmpty {
            return true
        }
        return false
    }

    /// For every backfill we do a single pass to enqueue all attachments that pass the filters for re-validation.
    /// Returns the backfills for which we have not yet done this enqueing pass.
    /// If empty, no enqueuing is necessary.
    func backfillsThatNeedEnqueuing(tx: DBReadTransaction) -> [ValidationBackfill] {
        let knownBackfills = ValidationBackfill.allCases
        guard let lastEnqueuedBackfill = self.getLastEnqueuedBackfill(tx: tx) else {
            // If we've never done it at all, we need to enqueue all of them.
            return knownBackfills
        }

        return knownBackfills.filter { $0.rawValue > lastEnqueuedBackfill.rawValue }
    }

    func getLastEnqueuedBackfill(tx: DBReadTransaction) -> ValidationBackfill? {
        return (kvStore.getInt(Constants.enqueuedUpToBackfillKey, transaction: tx))
            .map(ValidationBackfill.init(rawValue:)) ?? nil
    }

    func setLastEnqueuedBackfill(_ newValue: ValidationBackfill, tx: DBWriteTransaction) {
        kvStore.setInt(newValue.rawValue, key: Constants.enqueuedUpToBackfillKey, transaction: tx)
    }

    func enqueue(attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        failIfThrows {
            try tx.database.execute(
                sql: "INSERT OR IGNORE INTO \(Constants.queueTableName) VALUES(?);",
                arguments: [attachmentId],
            )
        }
    }

    /// Get the next batch of attachment IDs to re-validate.
    /// If returns an empty array, there's nothing left to re-validate and we're done.
    func getNextAttachmentIdBatch(tx: DBReadTransaction) -> [Attachment.IDType] {
        return failIfThrows {
            return try Attachment.IDType.fetchAll(
                tx.database,
                sql: """
                SELECT \(Constants.queueIdColumn.name)
                FROM \(Constants.queueTableName)
                ORDER BY \(Constants.queueIdColumn.name) DESC
                LIMIT ?;
                """,
                arguments: [Constants.batchSize],
            )
        }
    }

    func dequeue(attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        failIfThrows {
            try tx.database.execute(
                sql: "DELETE FROM \(Constants.queueTableName) WHERE \(Constants.queueIdColumn.name) = ?;",
                arguments: [attachmentId],
            )
        }
    }

    private enum Constants {
        /// We re-validate this many eligible attachments in one go.
        /// Lower = more aggressively persist progress. Higher = more efficient but interruptions lose progress.
        static let batchSize = 5

        static let queueTableName = "AttachmentValidationBackfillQueue"
        static let queueIdColumn = Column("attachmentId")

        /// The value at this key is the max (raw value) ``ValidationBackfill`` we've finished enqueuing.
        static let enqueuedUpToBackfillKey = "enqueuedUpToBackfillKey"
    }
}
