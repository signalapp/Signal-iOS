//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentStoreImpl: AttachmentStore {

    public init() {}

    public func fetchReferences(
        owners: [AttachmentReference.OwnerId],
        tx: DBReadTransaction
    ) -> [AttachmentReference] {
        fatalError("Unimplemented")
    }

    public func fetch(ids: [Attachment.IDType], tx: DBReadTransaction) -> [Attachment] {
        fatalError("Unimplemented")
    }

    public func enumerateAllReferences(
        toAttachmentId: Attachment.IDType,
        tx: DBReadTransaction,
        block: (AttachmentReference) -> Void
    ) {
        fatalError("Unimplemented")
    }

    // MARK: - Writes

    public func addOwner(
        duplicating ownerReference: AttachmentReference,
        withNewOwner newOwner: AttachmentReference.OwnerId,
        tx: DBWriteTransaction
    ) throws{
        // New reference should have the same root type, just a different id.
        let hasMatchingType: Bool = {
            switch (ownerReference.owner.id, newOwner) {
            case
                (.messageBodyAttachment, .messageBodyAttachment),
                (.messageLinkPreview, .messageLinkPreview),
                (.messageSticker, .messageSticker),
                (.messageOversizeText, .messageOversizeText),
                (.messageContactAvatar, .messageContactAvatar),
                (.quotedReplyAttachment, .quotedReplyAttachment),
                (.storyMessageMedia, .storyMessageMedia),
                (.storyMessageLinkPreview, .storyMessageLinkPreview),
                (.threadWallpaperImage, .threadWallpaperImage),
                (.globalThreadWallpaperImage, .globalThreadWallpaperImage):
                return true
            case
                (.messageBodyAttachment, _),
                (.messageLinkPreview, _),
                (.messageSticker, _),
                (.messageOversizeText, _),
                (.messageContactAvatar, _),
                (.quotedReplyAttachment, _),
                (.storyMessageMedia, _),
                (.storyMessageLinkPreview, _),
                (.threadWallpaperImage, _),
                (.globalThreadWallpaperImage, _):
                return false
            }
        }()
        guard hasMatchingType else {
            throw OWSAssertionError("Owner reference types don't match!")
        }
        fatalError("Unimplemented")
    }

    public func update(
        _ reference: AttachmentReference,
        withReceivedAtTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }

    public func removeOwner(
        _ owner: AttachmentReference.OwnerId,
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }

    public func insert(
        _ attachment: Attachment,
        reference: AttachmentReference,
        tx: DBWriteTransaction
    ) {
        fatalError("Unimplemented")
    }
}

extension AttachmentStoreImpl: AttachmentUploadStore {

    public func markUploadedToTransitTier(
        attachmentStream: AttachmentStream,
        encryptionKey: Data,
        encryptedByteLength: UInt32,
        digest: Data,
        cdnKey: String,
        cdnNumber: UInt32,
        uploadTimestamp: UInt64,
        tx: DBWriteTransaction
    ) {
        let transitTierInfo = Attachment.TransitTierInfo(
            cdnNumber: cdnNumber,
            cdnKey: cdnKey,
            uploadTimestamp: uploadTimestamp,
            encryptionKey: encryptionKey,
            encryptedByteCount: encryptedByteLength,
            encryptedFileSha256Digest: digest,
            lastDownloadAttemptTimestamp: nil
        )
        fatalError("Unimplemented")
    }
}
