//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public class BackupAttachmentUploadStore {

    public init() {}

    /// "Enqueue" an attachment from a backup for upload.
    ///
    /// If the same attachment is already enqueued, updates it to the greater of the old and new owner's timestamp.
    ///
    /// Doesn't actually trigger an upload; callers must later call `fetchNextUpload`, complete the upload of
    /// both the fullsize and thumbnail as needed, and then call `markUploadDone` once finished.
    /// Note that the upload operation can (and will) be separately durably enqueued in AttachmentUploadQueue,
    /// that's fine and doesn't change how this queue works.
    public func enqueue(
        _ attachment: AttachmentStream,
        owner: QueuedBackupAttachmentUpload.OwnerType,
        fullsize: Bool,
        tx: DBWriteTransaction,
        file: StaticString? = #file,
        function: StaticString? = #function,
        line: UInt? = #line,
    ) {
        if let file, let function, let line {
            Logger.info("Enqueuing \(attachment.id) fullsize? \(fullsize) from \(file) \(line): \(function)")
        }

        let db = tx.database

        let unencryptedSize: UInt32
        if fullsize {
            unencryptedSize = attachment.unencryptedByteCount
        } else {
            // We don't (easily) know the thumbnail size; just estimate as the max size
            // (which is small anyway) and run with it.
            unencryptedSize = AttachmentThumbnailQuality.backupThumbnailMaxSizeBytes
        }

        var newRecord = QueuedBackupAttachmentUpload(
            attachmentRowId: attachment.id,
            highestPriorityOwnerType: owner,
            isFullsize: fullsize,
            estimatedByteCount: UInt32(clamping: Cryptography.estimatedMediaTierCDNSize(
                unencryptedSize: UInt64(safeCast: unencryptedSize),
            ) ?? .max),
        )

        let existingRecordQuery = QueuedBackupAttachmentUpload
            .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) == attachment.id)
            .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.isFullsize) == fullsize)
        let existingRecord = failIfThrows {
            try existingRecordQuery.fetchOne(db)
        }

        if var existingRecord {
            // Only update if done or the new one has higher priority; otherwise leave untouched.
            let shouldUpdate = switch existingRecord.state {
            case .done: true
            case .ready: newRecord.highestPriorityOwnerType.isHigherPriority(than: existingRecord.highestPriorityOwnerType)
            }
            if shouldUpdate {
                existingRecord.highestPriorityOwnerType = newRecord.highestPriorityOwnerType
                existingRecord.state = newRecord.state
                failIfThrows {
                    try existingRecord.update(db)
                }
            }
        } else {
            // If there's no existing record, insert and we're done.
            failIfThrows {
                try newRecord.insert(db)
            }
        }
    }

    /// Read the next highest priority uploads off the queue, up to count.
    /// Returns an empty array if nothing is left to upload.
    /// Does NOT take into account minRetryTimestamp; callers are expected
    /// to handle results with timestamps greater than the current time.
    public func fetchNextUploads(
        count: UInt,
        isFullsize: Bool,
        tx: DBReadTransaction,
    ) throws -> [QueuedBackupAttachmentUpload] {
        // NULLS FIRST is unsupported in GRDB so we bridge to raw SQL;
        // we want thread wallpapers to go first (null timestamp) and then
        // descending order after that.
        return try QueuedBackupAttachmentUpload
            .fetchAll(
                tx.database,
                sql: """
                SELECT * FROM \(QueuedBackupAttachmentUpload.databaseTableName)
                WHERE
                  \(QueuedBackupAttachmentUpload.CodingKeys.state.rawValue) = ?
                  AND \(QueuedBackupAttachmentUpload.CodingKeys.isFullsize.rawValue) = ?
                ORDER BY
                    \(QueuedBackupAttachmentUpload.CodingKeys.maxOwnerTimestamp.rawValue) DESC NULLS FIRST
                LIMIT ?
                """,
                arguments: [QueuedBackupAttachmentUpload.State.ready.rawValue, isFullsize, count],
            )
    }

    public func getEnqueuedUpload(
        for attachmentId: Attachment.IDType,
        fullsize: Bool,
        tx: DBReadTransaction,
    ) throws -> QueuedBackupAttachmentUpload? {
        return try QueuedBackupAttachmentUpload
            .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) == attachmentId)
            .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.isFullsize) == fullsize)
            .fetchOne(tx.database)
    }

    /// Remove the upload from the queue. Should be called once uploaded (or permanently failed).
    ///
    /// - Important
    /// Once all `QueuedBackupAttachmentUpload` records are marked done, a SQL
    /// trigger (`__BackupAttachmentUploadQueue_au`) will wipe them all. This
    /// mitigates potential issues around long-completed upload records being
    /// counted towards future progress.
    ///
    /// - returns the removed record, if any.
    @discardableResult
    public func markUploadDone(
        for attachmentId: Attachment.IDType,
        fullsize: Bool,
        tx: DBWriteTransaction,
        file: StaticString? = #file,
        function: StaticString? = #function,
        line: UInt? = #line,
    ) throws -> QueuedBackupAttachmentUpload? {
        if let file, let function, let line {
            Logger.info("Marking \(attachmentId) done. fullsize? \(fullsize) from \(file) \(line): \(function)")
        }
        var record = try QueuedBackupAttachmentUpload
            .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.attachmentRowId) == attachmentId)
            .filter(Column(QueuedBackupAttachmentUpload.CodingKeys.isFullsize) == fullsize)
            .fetchOne(tx.database)
        record?.state = .done
        try record?.update(tx.database)
        return record
    }

    public func totalEstimatedFullsizeBytesToUpload(tx: DBReadTransaction) throws -> UInt64 {
        return try UInt64
            .fetchOne(
                tx.database,
                sql: """
                SELECT SUM(\(QueuedBackupAttachmentUpload.CodingKeys.estimatedByteCount.rawValue))
                FROM \(QueuedBackupAttachmentUpload.databaseTableName)
                WHERE
                  \(QueuedBackupAttachmentUpload.CodingKeys.state.rawValue) = ?
                  AND \(QueuedBackupAttachmentUpload.CodingKeys.isFullsize.rawValue) = ?
                """,
                arguments: [QueuedBackupAttachmentUpload.State.ready.rawValue, true],
            )
            ?? 0
    }
}

extension QueuedBackupAttachmentUpload.OwnerType {

    public func isHigherPriority(than other: QueuedBackupAttachmentUpload.OwnerType) -> Bool {
        switch (self, other) {

        // Thread wallpapers are higher priority, they always win.
        case (.threadWallpaper, _):
            return true

        case (.message(_), .threadWallpaper):
            return false

        case (.message(let selfTimestamp), .message(let otherTimestamp)):
            // Higher priority if more recent.
            return selfTimestamp > otherTimestamp
        }
    }
}
