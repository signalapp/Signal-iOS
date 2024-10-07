//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Attachment mutations needed for upload handling.
public protocol AttachmentUploadStore {

    /// Mark the attachment as having been uploaded to the transit tier.
    func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws

    /// Mark the attachment's transit tier upload as expired (wipe its transit tier info).
    func markTransitTierUploadExpired(
        attachment: Attachment,
        info: Attachment.TransitTierInfo,
        tx: DBWriteTransaction
    ) throws

    /// Mark the attachment as having been uploaded to the media tier.
    func markUploadedToMediaTier(
        attachment: Attachment,
        mediaTierInfo: Attachment.MediaTierInfo,
        tx: DBWriteTransaction
    ) throws

    /// Mark the attachment as deleted and/or not uploaded to media tier,
    /// wiping media tier info if set.
    func markMediaTierUploadExpired(
        attachment: Attachment,
        tx: DBWriteTransaction
    ) throws

    /// Mark the attachment thumbnail as having been uploaded to the media tier.
    func markThumbnailUploadedToMediaTier(
        attachment: Attachment,
        thumbnailMediaTierInfo: Attachment.ThumbnailMediaTierInfo,
        tx: DBWriteTransaction
    ) throws

    /// Mark the attachment's thumbnail as deleted and/or not uploaded to media tier,
    /// wiping media tier info if set.
    func markThumbnailMediaTierUploadExpired(
        attachment: Attachment,
        tx: DBWriteTransaction
    ) throws

    func upsert(
        record: AttachmentUploadRecord,
        tx: DBWriteTransaction
    ) throws

    func removeRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBWriteTransaction
    ) throws

    func fetchAttachmentUploadRecord(
        for attachmentId: Attachment.IDType,
        sourceType: AttachmentUploadRecord.SourceType,
        tx: DBReadTransaction
    ) throws -> AttachmentUploadRecord?
}
