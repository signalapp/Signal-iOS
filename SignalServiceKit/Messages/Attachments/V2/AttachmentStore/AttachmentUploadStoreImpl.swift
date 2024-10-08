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
        var record = Attachment.Record(attachment: attachmentStream.attachment)
        record.transitCdnKey = transitTierInfo.cdnKey
        record.transitCdnNumber = transitTierInfo.cdnNumber
        record.transitEncryptionKey = transitTierInfo.encryptionKey
        record.transitUploadTimestamp = transitTierInfo.uploadTimestamp
        record.transitUnencryptedByteCount = transitTierInfo.unencryptedByteCount
        record.transitDigestSHA256Ciphertext = transitTierInfo.digestSHA256Ciphertext
        record.lastTransitDownloadAttemptTimestamp = transitTierInfo.lastDownloadAttemptTimestamp
        try record.update(tx.databaseConnection)
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

        var record = Attachment.Record(attachment: attachment)
        record.transitCdnKey = nil
        record.transitCdnNumber = nil
        record.transitEncryptionKey = nil
        record.transitUploadTimestamp = nil
        record.transitUnencryptedByteCount = nil
        record.transitDigestSHA256Ciphertext = nil
        record.lastTransitDownloadAttemptTimestamp = nil
        try record.update(tx.databaseConnection)
    }

    public func markUploadedToMediaTier(
        attachment: Attachment,
        mediaTierInfo: Attachment.MediaTierInfo,
        tx: DBWriteTransaction
    ) throws {
        var record = Attachment.Record(attachment: attachment)
        record.mediaTierCdnNumber = mediaTierInfo.cdnNumber
        record.mediaTierUploadEra = mediaTierInfo.uploadEra
        record.mediaTierUnencryptedByteCount = mediaTierInfo.unencryptedByteCount
        record.mediaTierDigestSHA256Ciphertext = mediaTierInfo.digestSHA256Ciphertext
        record.mediaTierIncrementalMac = mediaTierInfo.incrementalMacInfo?.mac
        record.mediaTierIncrementalMacChunkSize = mediaTierInfo.incrementalMacInfo?.chunkSize
        record.lastMediaTierDownloadAttemptTimestamp = mediaTierInfo.lastDownloadAttemptTimestamp
        try record.update(tx.databaseConnection)
    }

    public func markMediaTierUploadExpired(
        attachment: Attachment,
        tx: DBWriteTransaction
    ) throws {
        var record = Attachment.Record(attachment: attachment)
        record.mediaTierCdnNumber = nil
        record.mediaTierUploadEra = nil
        record.mediaTierUnencryptedByteCount = nil
        record.mediaTierDigestSHA256Ciphertext = nil
        record.mediaTierIncrementalMac = nil
        record.mediaTierIncrementalMacChunkSize = nil
        record.lastMediaTierDownloadAttemptTimestamp = nil
        try record.update(tx.databaseConnection)
    }

    public func markThumbnailUploadedToMediaTier(
        attachment: Attachment,
        thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo,
        tx: DBWriteTransaction
    ) throws {
        var record = Attachment.Record(attachment: attachment)
        record.thumbnailCdnNumber = thumbnailMediaTierInfo.cdnNumber
        record.thumbnailUploadEra = thumbnailMediaTierInfo.uploadEra
        record.lastThumbnailDownloadAttemptTimestamp = thumbnailMediaTierInfo.lastDownloadAttemptTimestamp
        try record.update(tx.databaseConnection)
    }

    public func markThumbnailMediaTierUploadExpired(
        attachment: Attachment,
        tx: DBWriteTransaction
    ) throws {
        var record = Attachment.Record(attachment: attachment)
        record.thumbnailCdnNumber = nil
        record.thumbnailUploadEra = nil
        record.lastThumbnailDownloadAttemptTimestamp = nil
        try record.update(tx.databaseConnection)
    }

    public func upsert(record: AttachmentUploadRecord, tx: DBWriteTransaction) throws {
        var newRecord = AttachmentUploadRecord(sourceType: record.sourceType, attachmentId: record.attachmentId)
        newRecord.sqliteId = record.sqliteId
        newRecord.uploadForm = record.uploadForm
        newRecord.uploadFormTimestamp = record.uploadFormTimestamp
        newRecord.localMetadata = record.localMetadata
        newRecord.uploadSessionUrl = record.uploadSessionUrl
        newRecord.attempt = record.attempt
        try newRecord.save(tx.databaseConnection)
    }

    public func removeRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: any DBWriteTransaction
    ) throws {
        try AttachmentUploadRecord
            .filter(Column(AttachmentUploadRecord.CodingKeys.attachmentId) == attachmentId)
            .filter(Column(AttachmentUploadRecord.CodingKeys.sourceType) == sourceType.rawValue)
            .deleteAll(tx.databaseConnection)
    }

    public func fetchAttachmentUploadRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBReadTransaction
    ) throws -> AttachmentUploadRecord? {
        return try AttachmentUploadRecord
            .filter(Column(AttachmentUploadRecord.CodingKeys.attachmentId) == attachmentId)
            .filter(Column(AttachmentUploadRecord.CodingKeys.sourceType) == sourceType.rawValue)
            .fetchOne(tx.databaseConnection)
    }
}
