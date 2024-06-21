//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class TSResourceDownloadManagerMock: TSResourceDownloadManager {

    public init() {}

    open func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }

    open func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }

    open func cancelDownload(for attachmentId: TSResourceId, tx: DBWriteTransaction) {
        // Do nothing
    }

    open func downloadProgress(for attachmentId: TSResourceId, tx: DBReadTransaction) -> CGFloat? {
        return nil
    }
}

#endif
