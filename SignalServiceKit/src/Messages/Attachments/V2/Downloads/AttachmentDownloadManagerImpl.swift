//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class AttachmentDownloadManagerImpl: AttachmentDownloadManager {

    public init() {}

    @discardableResult
    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        fatalError("Unimplemented")
    }

    @discardableResult
    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        fatalError("Unimplemented")
    }

    public func cancelDownload(for attachmentId: Attachment.IDType, tx: DBWriteTransaction) {
        fatalError("Unimplemented")
    }

    public func downloadProgress(for attachmentId: Attachment.IDType, tx: DBReadTransaction) -> CGFloat? {
        fatalError("Unimplemented")
    }

    // MARK: - Helpers

    func copyThumbnailForQuotedReplyIfNeeded(_ downloadedAttachment: AttachmentStream) {
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
        ///
        /// 3. As with any AttachmentReferences update, delete any now-orphaned attachments
        ///   3a. Note the passed-in attachment itself may be orphaned, if it got enqueued with no other owners and wasn't used
        ///      for the quoted reply.
        ///
        /// FYI nothing needs to be updated on the TSQuotedMessage or the parent message.
        fatalError("Unimplemented")
    }
}
