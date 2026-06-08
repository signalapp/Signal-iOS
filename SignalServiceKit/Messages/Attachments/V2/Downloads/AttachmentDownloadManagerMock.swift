//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class AttachmentDownloadManagerMock: AttachmentDownloadManager {

    public init() {}

    public func backupCdnInfo(metadata: BackupReadCredential) async throws -> BackupCdnInfo {
        return BackupCdnInfo(
            fileInfo: AttachmentDownloads.CdnInfo(contentLength: 0, lastModified: Date()),
            metadataHeader: BackupNonce.MetadataHeader(data: Data()),
        )
    }

    public func downloadBackup(
        metadata: BackupReadCredential,
        progress: OWSProgressSink?,
    ) async throws -> URL {
        try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
        fatalError()
    }

    public func downloadEncryptedTransientAttachment(
        downloadMetadata: AttachmentDownloads.DownloadMetadata,
        expectedDownloadSize: UInt64?,
        progress: (any OWSProgressSink)?,
    ) async throws -> URL {
        try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
        fatalError()
    }

    public func downloadTransientAttachment(
        downloadMetadata: AttachmentDownloads.DownloadMetadata,
        decryptionMetadata: DecryptionMetadata,
        expectedDownloadSize: UInt64?,
        progress: OWSProgressSink?,
    ) async throws -> URL {
        try! await Task.sleep(nanoseconds: TimeInterval.infinity.clampedNanoseconds)
        fatalError()
    }

    open func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        useThumbnails: Bool,
        tx: DBWriteTransaction,
    ) {
        // Do nothing
    }

    open func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    ) {
        // Do nothing
    }

    open func enqueueCopyOfLocalAttachment(
        id: Attachment.IDType,
        tx: DBWriteTransaction,
    ) {
        // Do nothing
    }

    open func enqueueDownloadOfReferencedAttachment(
        referencedAttachment: ReferencedAttachment,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    ) {
        // Do nothing
    }

    public func downloadReferencedAttachment(
        referencedAttachment: ReferencedAttachment,
        priority: AttachmentDownloadPriority,
        progress: (any OWSProgressSink)?,
    ) async throws {
        // Do nothing
    }

    open func downloadAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
        progress: OWSProgressSink?,
    ) async throws {
        // Do nothing
    }

    open func beginDownloadingIfNecessary() {
        // Do nothing
    }

    open func cancelDownload(
        for attachmentId: Attachment.IDType,
        tx: DBWriteTransaction,
    ) {
        // Do nothing
    }

    open func downloadProgress(for attachmentId: Attachment.IDType, tx: DBReadTransaction) -> CGFloat? {
        return nil
    }
}

#endif
