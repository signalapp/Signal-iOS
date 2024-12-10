//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentDownloadManagerMock: AttachmentDownloadManager {

    public init() {}

    public func downloadBackup(
        metadata: BackupReadCredential,
        progress: OWSProgressSink?
    ) -> Promise<URL> {
        return .pending().0
    }

    public func downloadTransientAttachment(
        metadata: AttachmentDownloads.DownloadMetadata,
        progress: OWSProgressSink?
    ) -> Promise<URL> {
        return .pending().0
    }

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

    open func enqueueDownloadOfAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
        tx: DBWriteTransaction
    ) {
        // Do nothing
    }

    open func downloadAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
        progress: OWSProgressSink?
    ) async throws {
        // Do nothing
    }

    open func beginDownloadingIfNecessary() {
        // Do nothing
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
