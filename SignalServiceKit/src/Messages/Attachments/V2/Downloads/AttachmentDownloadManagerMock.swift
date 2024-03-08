//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentDownloadManagerMock: AttachmentDownloadManager {

    public init() {}

    open func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        return .value(())
    }

    open func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) -> SignalCoreKit.Promise<Void> {
        return .value(())
    }

    open func cancelDownload(
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }

    open func downloadProgress(for attachmentId: Attachment.IDType, tx: DBReadTransaction) -> CGFloat? {
        return nil
    }
}

#endif
