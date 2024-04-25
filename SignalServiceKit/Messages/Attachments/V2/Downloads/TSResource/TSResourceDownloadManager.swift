//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum TSResourceDownloads {

    public static let attachmentDownloadProgressNotification = Notification.Name("TSResourceDownloadProgressNotification")

    /// Key for a CGFloat progress value from 0 to 1
    public static var attachmentDownloadProgressKey: String { "tsResourceDownloadProgressKey" }

    /// Key for a ``TSResourceId`` value.
    public static var attachmentDownloadAttachmentIDKey: String { "tsResourceDownloadAttachmentIDKey" }
}

public protocol TSResourceDownloadManager {

    @discardableResult
    func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) -> Promise<Void>

    @discardableResult
    func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction
    ) -> Promise<Void>

    func cancelDownload(for attachmentId: TSResourceId, tx: DBWriteTransaction)

    func downloadProgress(for attachmentId: TSResourceId, tx: DBReadTransaction) -> CGFloat?
}

extension TSResourceDownloadManager {

    @discardableResult
    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        return enqueueDownloadOfAttachmentsForMessage(message, priority: .default, tx: tx)
    }

    @discardableResult
    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        tx: DBWriteTransaction
    ) -> Promise<Void> {
        return enqueueDownloadOfAttachmentsForStoryMessage(message, priority: .default, tx: tx)
    }
}
