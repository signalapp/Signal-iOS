//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class TSResourceDownloadManagerImpl: TSResourceDownloadManager {

    private let attachmentDownloadManager: AttachmentDownloadManager
    private let owsDownloads = OWSAttachmentDownloads()
    private let tsResourceStore: TSResourceStore

    public init(
        attachmentDownloadManager: AttachmentDownloadManager,
        tsResourceStore: TSResourceStore
    ) {
        self.attachmentDownloadManager = attachmentDownloadManager
        self.tsResourceStore = tsResourceStore
    }

    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        let resources = tsResourceStore.allAttachments(for: message, tx: tx)
        var hasLegacyRef = false
        var hasV2Ref = false
        resources.forEach {
            switch $0.concreteType {
            case .legacy:
                hasLegacyRef = true
            case .v2:
                hasV2Ref = true
            }
        }
        // They should all be one type or the other. No mixing allowed.
        owsAssertDebug(!(hasLegacyRef && hasV2Ref))
        if hasV2Ref && FeatureFlags.readV2Attachments {
            attachmentDownloadManager.enqueueDownloadOfAttachmentsForMessage(message, priority: priority, tx: tx)
        } else if hasLegacyRef {
            owsDownloads.enqueueDownloadOfAttachmentsForMessage(
                message,
                downloadBehavior: priority.owsDownloadBehavior,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        } else {
            Logger.info("Nothing to download!")
        }
    }

    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) {
        switch message.attachment {
        case .file:
            owsDownloads.enqueueDownloadOfAttachmentsForStoryMessage(
                message,
                downloadBehavior: priority.owsDownloadBehavior,
                transaction: SDSDB.shimOnlyBridge(tx)
            )
        case .text(let attachment):
            if attachment.preview?.usesV2AttachmentReference == true {
                attachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(message, priority: priority, tx: tx)
            } else if attachment.preview?.legacyImageAttachmentId != nil {
                owsDownloads.enqueueDownloadOfAttachmentsForStoryMessage(
                    message,
                    downloadBehavior: priority.owsDownloadBehavior,
                    transaction: SDSDB.shimOnlyBridge(tx)
                )
            } else {
                Logger.info("Nothing to download!")
            }
        case .foreignReferenceAttachment:
            attachmentDownloadManager.enqueueDownloadOfAttachmentsForStoryMessage(message, priority: priority, tx: tx)
        }
    }

    public func enqueueContactSyncDownload(
        attachmentPointer: TSAttachmentPointer
    ) async throws -> TSResourceStream {
        // TODO: deal with v2 contact sync downloads.

        // Dispatch to a background queue because the legacy code uses non-awaitable
        // db writes, and therefore cannot be on a Task queue.
        let (downloadPromise, downloadFuture) = Promise<TSAttachmentStream>.pending()
        DispatchQueue.sharedBackground.async { [owsDownloads] in
            downloadFuture.resolve(
                on: SyncScheduler(),
                with: owsDownloads.enqueueContactSyncDownload(attachmentPointer: attachmentPointer)
            )
        }
        return try await downloadPromise.awaitable()
    }

    public func enqueueDownloadOfAttachments(
        forStoryMessageId storyMessageId: String,
        downloadBehavior: AttachmentDownloadBehavior
    ) -> Promise<Void> {
        // TODO: remove this method
        return owsDownloads.enqueueDownloadOfAttachments(
            forStoryMessageId: storyMessageId,
            downloadBehavior: downloadBehavior
        )
    }

    public func cancelDownload(for attachmentId: TSResourceId, tx: DBWriteTransaction) {
        switch attachmentId {
        case .legacy(let uniqueId):
            owsDownloads.cancelDownload(attachmentId: uniqueId)
        case .v2(let rowId):
            attachmentDownloadManager.cancelDownload(for: rowId, tx: tx)
        }
    }

    public func downloadProgress(for attachmentId: TSResourceId, tx: DBReadTransaction) -> CGFloat? {
        switch attachmentId {
        case .legacy(let uniqueId):
            return owsDownloads.downloadProgress(forAttachmentId: uniqueId)
        case .v2(let rowId):
            return attachmentDownloadManager.downloadProgress(for: rowId, tx: tx)
        }
    }
}
