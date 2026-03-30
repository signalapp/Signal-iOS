//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public class AttachmentUploadStore {

    public init() {
    }

    public func upsert(record: AttachmentUploadRecord, tx: DBWriteTransaction) {
        var newRecord = AttachmentUploadRecord(sourceType: record.sourceType, attachmentId: record.attachmentId)
        newRecord.sqliteId = record.sqliteId
        newRecord.uploadForm = record.uploadForm
        newRecord.uploadFormTimestamp = record.uploadFormTimestamp
        newRecord.localMetadata = record.localMetadata
        newRecord.uploadSessionUrl = record.uploadSessionUrl
        newRecord.attempt = record.attempt
        failIfThrows {
            try newRecord.save(tx.database)
        }
    }

    public func removeRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBWriteTransaction,
    ) {
        let query = AttachmentUploadRecord
            .filter(Column(AttachmentUploadRecord.CodingKeys.attachmentId) == attachmentId)
            .filter(Column(AttachmentUploadRecord.CodingKeys.sourceType) == sourceType.rawValue)

        failIfThrows {
            try query.deleteAll(tx.database)
        }
    }

    public func fetchAttachmentUploadRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBReadTransaction,
    ) -> AttachmentUploadRecord? {
        let query = AttachmentUploadRecord
            .filter(Column(AttachmentUploadRecord.CodingKeys.attachmentId) == attachmentId)
            .filter(Column(AttachmentUploadRecord.CodingKeys.sourceType) == sourceType.rawValue)

        return failIfThrows {
            try query.fetchOne(tx.database)
        }
    }
}
