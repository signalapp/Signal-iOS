//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// Wrapper around TSQuotedMessage that use v2 attachment thumbnails.
internal class QuotedMessageAttachmentHelperImpl: QuotedMessageAttachmentHelper {

    private let info: OWSAttachmentInfo

    init(_ info: OWSAttachmentInfo) {
        self.info = info
    }

    func thumbnailAttachmentMetadata(parentMessage: TSMessage, tx: SDSAnyReadTransaction) -> QuotedThumbnailAttachmentMetadata? {
        // TODO: fetch metadata directly from the AttachmentReferences table
        fatalError()
    }

    private func thumbnailAttachment(metadata: QuotedThumbnailAttachmentMetadata, tx: SDSAnyReadTransaction) -> TSAttachment? {
        // TODO: fetch attachment from the v2 Attachments table
        fatalError()
    }

    func displayableThumbnailAttachment(
        metadata: QuotedThumbnailAttachmentMetadata,
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> DisplayableQuotedThumbnailAttachment? {
        guard let attachment = self.thumbnailAttachment(metadata: metadata, tx: tx) else {
            return nil
        }

        let thumbnailImage: UIImage?
        let failedAttachmentPointer: TSAttachmentPointer?

        if let attachmentStream = attachment as? TSAttachmentStream {
            // If it is an attachment stream, it should already be pointing at the resized
            // thumbnail image.
            guard
                let imageData = attachmentStream.validStillImageData(),
                let image = UIImage(data: imageData)
            else {
                owsFailDebug("Invalid thumbnail image reference!")
                return nil
            }
            thumbnailImage = image
            failedAttachmentPointer = nil
        } else {
            // The attachment is undownloaded, show a blurhash.
            if let blurHash = attachment.blurHash {
                thumbnailImage = BlurHash.image(for: blurHash)
            } else {
                thumbnailImage = nil
            }
            // Set this as the "failed" pointer, which just means the user can
            // tap to download it.
            failedAttachmentPointer = attachment as? TSAttachmentPointer
        }

        return .init(
            attachmentType: metadata.attachmentType,
            thumbnailImage: thumbnailImage,
            failedAttachmentPointer: failedAttachmentPointer
        )
    }

    func attachmentPointerIdForDownloading(
        parentMessage: TSMessage,
        tx: SDSAnyReadTransaction
    ) -> String? {
        // TODO: fetch from the AttachmentReferences table, and check that the
        // contentType column is nil (undownloaded), if so return the id,
        // otherwise return nil
        fatalError()
    }

    func setDownloadedAttachmentStream(
        attachmentStream: TSAttachmentStream,
        parentMessage: TSMessage,
        tx: SDSAnyWriteTransaction
    ) {
        // TODO: implement this method
        fatalError()

        /// Here's what this method needs to do:
        /// 1. Figure out what attachment to actually use
        ///   1a. If the passed in stream is not an image or video, use it directly.
        ///   1b. If the passed in stream is a video, make a thumbnail still image copy and insert it
        ///   1c. If its an image, make a thumbnail copy and insert it. (if its small, can reuse the same attachment, no insertion)
        ///
        /// 2. Create the edge between the attachment and this link preview
        ///   2a. Find the row for this message in AttachmentReferences with quoted message thumnail ref type
        ///   2b. Validate that the contentType column is null (its undownloaded). If its downloaded, exit early.
        ///   2c. Update the attachmentId column for the row to the attachment from step 1. (possibly the same attachment)
        ///   2d. As with any AttachmentReferences update, delete any now-orphaned attachments
        ///
        /// 3. Needs new code structure: if we _didn't_ use the passed-in attachment in step 1, and it was inserted to disk,
        /// and nothing _else_ uses it, its orphaned and should be deleted.
        /// Either: 
        ///     a: the callsite, when done, needs to check for references and orphan the attachment if none were created.
        ///     b: the passed-in attachmentStream is uninserted (or _may_ be uninserted, and we have to check) and
        ///       this method needs to insert it if it uses it.
        ///
        /// FYI nothing needs to be updated on the TSQuotedMessage or the parent message.
    }

    func createThumbnailAndUpdateMessageIfNecessary(parentMessage: TSMessage, tx: SDSAnyWriteTransaction) -> TSAttachmentStream? {
        guard
            let metadata = self.thumbnailAttachmentMetadata(parentMessage: parentMessage, tx: tx),
            let attachment = self.thumbnailAttachment(metadata: metadata, tx: tx)
        else {
            return nil
        }
        // If its a stream, its the thumbnail, already resized and copied or whatever needed doing.
        return attachment as? TSAttachmentStream
    }
}
