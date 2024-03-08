//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol TSResourceDownloadManager {

    func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    )

    func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    )

    // TODO: contact syncs won't be V2 Attachments, because they
    // have no owner (their parent message isn't saved to the db).
    // Rethink this method signature.
    func enqueueContactSyncDownload(
        attachmentPointer: TSAttachmentPointer
    ) async throws -> TSResourceStream

    // TODO: generalize download observation and remove this
    func enqueueDownloadOfAttachments(
        forStoryMessageId storyMessageId: String,
        downloadBehavior: AttachmentDownloadBehavior
    ) -> Promise<Void>

    func cancelDownload(for attachmentId: TSResourceId, tx: DBWriteTransaction)

    func downloadProgress(for attachmentId: TSResourceId, tx: DBReadTransaction) -> CGFloat?
}

extension TSResourceDownloadManager {

    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        tx: DBWriteTransaction
    ) {
        enqueueDownloadOfAttachmentsForMessage(message, priority: .default, tx: tx)
    }

    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        tx: DBWriteTransaction
    ) {
        enqueueDownloadOfAttachmentsForStoryMessage(message, priority: .default, tx: tx)
    }
}
