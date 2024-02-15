//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wrapper around TSQuotedMessage for legacy instances (those that use TSAttachment).
/// Once TSAttachment is deprecated and removed, this class can be deleted.
internal class LegacyQuotedMessageAttachmentHelper: QuotedMessageAttachmentHelper {

    private let info: OWSAttachmentInfo?

    init(_ info: OWSAttachmentInfo?) {
        self.info = info
    }

    func thumbnailAttachmentMetadata(
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> QuotedThumbnailAttachmentMetadata? {
        guard let info else {
            return nil
        }
        return .init(
            attachmentReferenceType: info.attachmentType,
            attachmentId: info.rawAttachmentId,
            mimeType: info.contentType,
            sourceFilename: info.sourceFilename,
            // for legacy TSAttachments, this lives on the attachment object
            // so we don't fetch it at this point.
            attachmentType: nil
        )
    }

    func displayableThumbnailAttachment(
        metadata: QuotedThumbnailAttachmentMetadata,
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> DisplayableQuotedThumbnailAttachment? {
        let thumbnailImage: UIImage?
        let failedAttachmentPointer: TSAttachmentPointer?

        let attachment = self.fetchQuotedMessageThumbnailCopyingIfNeeded(
            parentMessage: parentMessage,
            tx: tx
        )

        if let attachmentStream = attachment as? TSAttachmentStream {
            thumbnailImage = attachmentStream.thumbnailImageSmallSync()
            failedAttachmentPointer = nil
        } else if !metadata.attachmentReferenceType.isThumbnailOwned {
            // If the quoted message isn't owning the thumbnail attachment, it's going to be referencing
            // some other attachment (e.g. undownloaded media). In this case, let's just use the blur hash
            if let blurHash = attachment?.blurHash {
                thumbnailImage = BlurHash.image(for: blurHash)
            } else {
                thumbnailImage = nil
            }
            failedAttachmentPointer = nil
        } else if let attachmentPointer = attachment as? TSAttachmentPointer {
            // If the quoted message has ownership of the thumbnail, but it hasn't been downloaded yet,
            // we should surface this in the view.
            thumbnailImage = nil
            failedAttachmentPointer = attachmentPointer
        } else {
            thumbnailImage = nil
            failedAttachmentPointer = nil
        }
        // We don't use the attachmentType on the metadata; this class doesn't set that
        // because it lives on the TSAttachment.
        let attachmentType: TSAttachmentType? = attachment?.attachmentType(
            forContainingMessage: parentMessage,
            transaction: tx
        )

        return .init(
            attachmentType: attachmentType,
            thumbnailImage: thumbnailImage,
            failedAttachmentPointer: failedAttachmentPointer
        )
    }

    func attachmentPointerIdForDownloading(
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> OWSAttachmentDownloads.AttachmentId? {

        guard let info else {
            return nil
        }

        // We only want to kick off a thumbnail fetching job if:
        // - The thumbnail attachment is owned by the quoted message content (so it's solely responsible for fetching)
        // - It's an unfetched pointer
        guard info.attachmentType.isThumbnailOwned else {
            return nil
        }

        let attachmentPointer = TSAttachmentPointer.anyFetchAttachmentPointer(uniqueId: info.rawAttachmentId, transaction: tx)
        return attachmentPointer?.uniqueId
    }

    func setDownloadedAttachmentStream(
        attachmentStream: TSAttachmentStream,
        parentMessage: TSMessage,
        tx: SDSAnyWriteTransaction
    ) {
        parentMessage.anyUpdateMessage(transaction: tx) { refetchedMessage in
            guard let quotedMessage = refetchedMessage.quotedMessage else {
                return
            }
            // We update the same reference the message has, so when this closure exits and the
            // message is rewritten to disk it will be rewritten with the updated quotedMessage.
            quotedMessage.setLegacyThumbnailAttachmentStream(attachmentStream)
        }
    }

    private func fetchQuotedMessageThumbnailCopyingIfNeeded(
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> TSAttachment? {
        guard let info else {
            return nil
        }

        guard let attachment = TSAttachment.anyFetch(uniqueId: info.rawAttachmentId, transaction: tx) else {
            return nil
        }
        // We should clone the attachment if it's been downloaded but our quotedMessage doesn't have its own copy.
        let needsClone = attachment is TSAttachmentStream && !info.attachmentType.isThumbnailOwned

        guard needsClone else {
            return attachment
        }

        // OH GOD THIS IS HORRIBLE keeping this now because this code will be deprecated/deleted soon.
        // If we happen to be handed a write transaction, we can perform the clone synchronously
        // Otherwise, just hand the caller what we have. We'll clone it async.
        if let writeTx = tx as? SDSAnyWriteTransaction {
            return Self.refetchMessageAndCreateThumbnailIfNeeded(
                originalParentMessageInstance: parentMessage,
                tx: writeTx
            )
        } else {
            NSObject.databaseStorage.asyncWrite { writeTx in
                _ = Self.refetchMessageAndCreateThumbnailIfNeeded(
                    originalParentMessageInstance: parentMessage,
                    tx: writeTx
                )
            }
            return attachment
        }
    }

    func createThumbnailAndUpdateMessageIfNecessary(
        parentMessage: TSMessage,
        tx: SDSAnyWriteTransaction
    ) -> TSAttachmentStream? {
        return Self.refetchMessageAndCreateThumbnailIfNeeded(
            originalParentMessageInstance: parentMessage,
            tx: tx
        )
    }

    /// Very important that this method is static; we call it from an async write so we need to reload everything,
    /// including the OWSAttachmentInfo, and not used the same instance with the same cached value.
    private static func refetchMessageAndCreateThumbnailIfNeeded(
        originalParentMessageInstance: TSMessage,
        tx: SDSAnyWriteTransaction
    ) -> TSAttachmentStream? {
        // This block _could_ run async, so we need to be careful to re-fetch the message
        // and its quotedMessage in case the values on disk have changed.
        guard
            let refetchedMessage = TSMessage.anyFetchMessage(uniqueId: originalParentMessageInstance.uniqueId, transaction: tx),
            let quotedMessage = refetchedMessage.quotedMessage
        else {
            return nil
        }

        guard let helper = quotedMessage.attachmentHelper() as? LegacyQuotedMessageAttachmentHelper else {
            owsFailDebug("Helper type changed mid flight!")
            return nil
        }

        guard let info = helper.info else {
            return nil
        }

        // We want to clone the existing attachment to a new attachment if necessary. This means:
        // - Fetching the attachment and making sure it's an attachment stream
        // - If we already own the attachment, we've already cloned it!
        // - Otherwise, we should copy the attachment stream to a new attachment
        // - Updating the message's state to now point to the new attachment
        guard
            let attachmentStream = TSAttachmentStream.anyFetchAttachmentStream(
                uniqueId: info.rawAttachmentId,
                transaction: tx
            )
        else {
            // No stream, nothing to clone. exit early.
            return nil
        }

        if info.attachmentType.isThumbnailOwned {
            // We already own it, nothing to do!
            return attachmentStream
        }

        // Do this outside the anyUpdateMessage block because that can get executed more than once.
        Logger.info("Cloning attachment to thumbnail")
        guard let thumbnailClone = attachmentStream.cloneAsThumbnail() else {
            Logger.error("Unable to clone")
            return nil
        }
        thumbnailClone.anyInsert(transaction: tx)

        originalParentMessageInstance.anyUpdateMessage(transaction: tx) { message in
            // We update the same reference the message has, so when this closure exits and the
            // message is rewritten to disk it will be rewritten with the updated quotedMessage.
            quotedMessage.setLegacyThumbnailAttachmentStream(thumbnailClone)
        }
        return thumbnailClone
    }
}

fileprivate extension OWSAttachmentInfoReference {

    var isThumbnailOwned: Bool {
        switch self {
        case .untrustedPointer, .thumbnail:
            return true
        case .original, .originalForSend, .unset:
            return false
        case .V2:
            owsFailDebug("Should not have a v2 pointer in this class!")
            return true
        @unknown default:
            return false
        }
    }
}
