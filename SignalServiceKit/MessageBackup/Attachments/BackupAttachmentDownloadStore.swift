//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol BackupAttachmentDownloadStore {

    /// If true, keep a copy of all media on local device, even if media backups are enabled.
    /// If false, keep only the past N days of media locally and rely on backups for the rest.
    func getShouldStoreAllMediaLocally(tx: DBReadTransaction) -> Bool

    /// See ``getShouldStoreAllMediaLocally``.
    func setShouldStoreAllMediaLocally(_ newValue: Bool, tx: DBWriteTransaction)

    /// "Enqueue" an attachment from a backup for download (using its reference).
    ///
    /// If the same attachment pointed to by the reference is already enqueued, updates it to the greater
    /// of the existing and new reference's timestamp.
    ///
    /// Doesn't actually trigger a download; callers must later call `dequeueAndClearTable` to insert
    /// rows into the normal AttachmentDownloadQueue, as this table serves only as an intermediary.
    func enqueue(_ reference: AttachmentReference, tx: DBWriteTransaction) throws

    /// Read rows off the queue one by one, calling the block for each, and then when finished delete
    /// every row in the table.
    func dequeueAndClearTable(tx: DBWriteTransaction, block: (QueuedBackupAttachmentDownload) throws -> Void) throws
}

public class BackupAttachmentDownloadStoreImpl: BackupAttachmentDownloadStore {

    private let kvStore: KeyValueStore

    public init(
        keyValueStoreFactory: KeyValueStoreFactory
    ) {
        self.kvStore = keyValueStoreFactory.keyValueStore(collection: "BackupAttachmentDownloadStoreImpl")
    }

    private let shouldStoreAllMediaLocallyKey = "shouldStoreAllMediaLocallyKey"

    public func getShouldStoreAllMediaLocally(tx: any DBReadTransaction) -> Bool {
        return kvStore.getBool(shouldStoreAllMediaLocallyKey, defaultValue: true, transaction: tx)
    }

    public func setShouldStoreAllMediaLocally(_ newValue: Bool, tx: any DBWriteTransaction) {
        kvStore.setBool(newValue, key: shouldStoreAllMediaLocallyKey, transaction: tx)
    }

    public func enqueue(_ reference: AttachmentReference, tx: any DBWriteTransaction) throws {
        let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database
        try enqueue(reference, tx: tx, db: db)
    }

    internal func enqueue(
        _ reference: AttachmentReference,
        tx: any DBWriteTransaction,
        db: GRDB.Database
    ) throws {
        let timestamp: UInt64? = {
            switch reference.owner {
            case .message(.bodyAttachment(let metadata)):
                return metadata.receivedAtTimestamp
            case .message(.contactAvatar(let metadata)):
                return metadata.receivedAtTimestamp
            case .message(.linkPreview(let metadata)):
                return metadata.receivedAtTimestamp
            case .message(.oversizeText(let metadata)):
                return metadata.receivedAtTimestamp
            case .message(.quotedReply(let metadata)):
                return metadata.receivedAtTimestamp
            case .message(.sticker(let metadata)):
                return metadata.receivedAtTimestamp
            case .storyMessage, .thread:
                return nil
            }
        }()

        let existingRecord = try QueuedBackupAttachmentDownload
            .filter(Column(QueuedBackupAttachmentDownload.CodingKeys.attachmentRowId) == reference.attachmentRowId)
            .fetchOne(db)

        if
            let existingRecord,
            existingRecord.timestamp ?? .max < timestamp ?? .max
        {
            // If we have an existing record with a smaller timestamp,
            // delete it in favor of the new row we are about to insert.
            // (nil timestamp counts as the largest timestamp)
            try existingRecord.delete(db)
        } else if existingRecord != nil {
            // Otherwise we had an existing record with a larger
            // timestamp, stop.
            return
        }

        var record = QueuedBackupAttachmentDownload(
            attachmentRowId: reference.attachmentRowId,
            timestamp: timestamp
        )
        try record.insert(db)
    }

    public func dequeueAndClearTable(
        tx: any DBWriteTransaction,
        block: (QueuedBackupAttachmentDownload) throws -> Void
    ) throws {
        let db = SDSDB.shimOnlyBridge(tx).unwrapGrdbWrite.database
        try self.dequeueAndClearTable(tx: tx, db: db, block: block)
    }

    internal func dequeueAndClearTable(
        tx: any DBWriteTransaction,
        db: Database,
        block: (QueuedBackupAttachmentDownload) throws -> Void
    ) throws {
        let cursor = try QueuedBackupAttachmentDownload
            // We want to dequeue in _reverse_ insertion order.
            .order([Column(QueuedBackupAttachmentDownload.CodingKeys.id).desc])
            .fetchCursor(db)

        while let record = try cursor.next() {
            try block(record)
        }

        try QueuedBackupAttachmentDownload.deleteAll(db)
    }
}

#if TESTABLE_BUILD

open class BackupAttachmentDownloadStoreMock: BackupAttachmentDownloadStore {

    public init() {}

    public var shouldStoreAllMediaLocally = true

    public func getShouldStoreAllMediaLocally(tx: any DBReadTransaction) -> Bool {
        return shouldStoreAllMediaLocally
    }

    public func setShouldStoreAllMediaLocally(_ newValue: Bool, tx: any DBWriteTransaction) {
        shouldStoreAllMediaLocally = newValue
    }

    open func enqueue(_ reference: AttachmentReference, tx: any DBWriteTransaction) throws {
        // Do nothing
    }

    open func dequeueAndClearTable(tx: any DBWriteTransaction, block: (QueuedBackupAttachmentDownload) throws -> Void) throws {
        // Do nothing
    }
}

#endif
