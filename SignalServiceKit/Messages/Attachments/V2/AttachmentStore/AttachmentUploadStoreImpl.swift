//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public class AttachmentUploadStoreImpl: AttachmentUploadStore {

    private let attachmentStore: AttachmentStore

    public init(
        attachmentStore: AttachmentStore
    ) {
        self.attachmentStore = attachmentStore
    }

    public func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        info transitTierInfo: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws {
        let params = Attachment.ConstructionParams.forUpdatingAsUploadedToTransitTier(
            attachment: attachmentStream,
            transitTierInfo: transitTierInfo
        )
        var record = Attachment.Record(params: params)
        record.sqliteId = attachmentStream.id
        try record.update(tx.database)
    }

    public func markTransitTierUploadExpired(
        attachment: Attachment,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws {
        // Refetch the attachment in case the passed in transit tier
        // info is obsolete.
        guard
            let refetchedAttachment = attachmentStore.fetch(id: attachment.id, tx: tx),
            refetchedAttachment.transitTierInfo?.cdnKey == info.cdnKey
        else {
            return
        }

        let params = Attachment.ConstructionParams.forRemovingTransitTierInfo(attachment: refetchedAttachment)
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        try record.update(tx.database)
    }

    public func markUploadedToMediaTier(
        attachment: Attachment,
        mediaTierInfo: Attachment.MediaTierInfo,
        mediaName: String,
        tx: DBWriteTransaction
    ) throws {
        let params = Attachment.ConstructionParams.forUpdatingAsUploadedToMediaTier(
            attachment: attachment,
            mediaTierInfo: mediaTierInfo,
            mediaName: mediaName
        )
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        try record.update(tx.database)
    }

    public func markMediaTierUploadExpired(
        attachment: Attachment,
        tx: DBWriteTransaction
    ) throws {
        let params = Attachment.ConstructionParams.forRemovingMediaTierInfo(attachment: attachment)
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        try record.update(tx.database)
    }

    public func markThumbnailUploadedToMediaTier(
        attachment: Attachment,
        thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo,
        mediaName: String,
        tx: DBWriteTransaction
    ) throws {
        let params = Attachment.ConstructionParams.forUpdatingAsUploadedThumbnailToMediaTier(
            attachment: attachment,
            thumbnailMediaTierInfo: thumbnailMediaTierInfo,
            mediaName: mediaName
        )
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        try record.update(tx.database)
    }

    public func markThumbnailMediaTierUploadExpired(
        attachment: Attachment,
        tx: DBWriteTransaction
    ) throws {
        let params = Attachment.ConstructionParams.forRemovingThumbnailMediaTierInfo(attachment: attachment)
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        try record.update(tx.database)
    }

    public func upsert(record: AttachmentUploadRecord, tx: DBWriteTransaction) throws {
        var newRecord = AttachmentUploadRecord(sourceType: record.sourceType, attachmentId: record.attachmentId)
        newRecord.sqliteId = record.sqliteId
        newRecord.uploadForm = record.uploadForm
        newRecord.uploadFormTimestamp = record.uploadFormTimestamp
        newRecord.localMetadata = record.localMetadata
        newRecord.uploadSessionUrl = record.uploadSessionUrl
        newRecord.attempt = record.attempt
        try newRecord.save(tx.database)
    }

    public func removeRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBWriteTransaction
    ) throws {
        try AttachmentUploadRecord
            .filter(Column(AttachmentUploadRecord.CodingKeys.attachmentId) == attachmentId)
            .filter(Column(AttachmentUploadRecord.CodingKeys.sourceType) == sourceType.rawValue)
            .deleteAll(tx.database)
    }

    public func fetchAttachmentUploadRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBReadTransaction
    ) throws -> AttachmentUploadRecord? {
        return try AttachmentUploadRecord
            .filter(Column(AttachmentUploadRecord.CodingKeys.attachmentId) == attachmentId)
            .filter(Column(AttachmentUploadRecord.CodingKeys.sourceType) == sourceType.rawValue)
            .fetchOne(tx.database)
    }
}
