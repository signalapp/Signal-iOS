//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB

public class AttachmentUploadStore {

    private let attachmentStore: AttachmentStore

    public init(
        attachmentStore: AttachmentStore,
    ) {
        self.attachmentStore = attachmentStore
    }

    public func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        info transitTierInfo: Attachment.TransitTierInfo,
        tx: DBWriteTransaction,
    ) {
        let latestTransitTierInfo = transitTierInfo

        // After we upload, we set the original transit tier info if the
        // upload's encryption key matches the primary attachment key.
        // Also check digest; we never expect this check to fail (how would we
        // have reused an encryption key but changed the IV?) but it is easy
        // to check and is one less assumption made by this code.
        // Otherwise keep the existing originalTransitTierInfo, including if it is nil.
        let originalTransitTierInfo: Attachment.TransitTierInfo?
        if transitTierInfo.encryptionKey == attachmentStream.attachment.encryptionKey {
            switch transitTierInfo.integrityCheck {
            case .digestSHA256Ciphertext(let digest):
                if digest == attachmentStream.encryptedFileSha256Digest {
                    originalTransitTierInfo = latestTransitTierInfo
                } else {
                    owsFailDebug("How are we reusing encryption key but have a different digest?")
                    originalTransitTierInfo = attachmentStream.attachment.originalTransitTierInfo
                }
            case .sha256ContentHash:
                owsFailDebug("Using plaintext hash for just-uploaded attachment integrity check; unable to verify digest")
                originalTransitTierInfo = attachmentStream.attachment.originalTransitTierInfo
            }
        } else {
            originalTransitTierInfo = attachmentStream.attachment.originalTransitTierInfo
        }

        let params = Attachment.ConstructionParams.forUpdatingAsUploadedToTransitTier(
            attachment: attachmentStream,
            latestTransitTierInfo: latestTransitTierInfo,
            originalTransitTierInfo: originalTransitTierInfo,
        )
        var record = Attachment.Record(params: params)
        record.sqliteId = attachmentStream.id
        failIfThrows {
            try record.update(tx.database)
        }
    }

    public func markTransitTierUploadExpired(
        attachment: Attachment,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction,
    ) {
        // Refetch the attachment in case the passed in transit tier
        // info is obsolete.
        guard
            let refetchedAttachment = attachmentStore.fetch(id: attachment.id, tx: tx)
        else {
            return
        }

        // Remove each if the cdn key matches; that's good enough to identify the upload that expired.
        let removeLatestTransitTierInfo = refetchedAttachment.latestTransitTierInfo?.cdnKey == info.cdnKey
        let removeOriginalTransitTierInfo = refetchedAttachment.originalTransitTierInfo?.cdnKey == info.cdnKey

        guard removeLatestTransitTierInfo || removeOriginalTransitTierInfo else {
            // No mutations
            return
        }

        let params = Attachment.ConstructionParams.forRemovingTransitTierInfo(
            from: refetchedAttachment,
            removeLatestTransitTierInfo: removeLatestTransitTierInfo,
            removeOriginalTransitTierInfo: removeOriginalTransitTierInfo,
        )
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        failIfThrows {
            try record.update(tx.database)
        }
    }

    public func markUploadedToMediaTier(
        attachment: Attachment,
        mediaTierInfo: Attachment.MediaTierInfo,
        mediaName: String,
        tx: DBWriteTransaction,
    ) {
        let params = Attachment.ConstructionParams.forUpdatingAsUploadedToMediaTier(
            attachment: attachment,
            mediaTierInfo: mediaTierInfo,
            mediaName: mediaName,
        )
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        failIfThrows {
            try record.update(tx.database)
        }
    }

    public func markMediaTierUploadExpired(
        attachment: Attachment,
        tx: DBWriteTransaction,
    ) {
        let params = Attachment.ConstructionParams.forRemovingMediaTierInfo(attachment: attachment)
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        failIfThrows {
            try record.update(tx.database)
        }
    }

    public func markThumbnailUploadedToMediaTier(
        attachment: Attachment,
        thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo,
        mediaName: String,
        tx: DBWriteTransaction,
    ) {
        let params = Attachment.ConstructionParams.forUpdatingAsUploadedThumbnailToMediaTier(
            attachment: attachment,
            thumbnailMediaTierInfo: thumbnailMediaTierInfo,
            mediaName: mediaName,
        )
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        failIfThrows {
            try record.update(tx.database)
        }
    }

    public func markThumbnailMediaTierUploadExpired(
        attachment: Attachment,
        tx: DBWriteTransaction,
    ) {
        let params = Attachment.ConstructionParams.forRemovingThumbnailMediaTierInfo(attachment: attachment)
        var record = Attachment.Record(params: params)
        record.sqliteId = attachment.id
        failIfThrows {
            try record.update(tx.database)
        }
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
