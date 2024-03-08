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
}
