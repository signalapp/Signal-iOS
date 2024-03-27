//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AttachmentDownloads {

    public static let attachmentDownloadProgressNotification = Notification.Name("AttachmentDownloadProgressNotification")

    /// Key for a CGFloat progress value from 0 to 1
    public static var attachmentDownloadProgressKey: String { "attachmentDownloadProgressKey" }

    /// Key for a ``Attachment.IdType`` value.
    public static var attachmentDownloadAttachmentIDKey: String { "attachmentDownloadAttachmentIDKey" }
}

public protocol AttachmentDownloadManager {

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

    func cancelDownload(for attachmentId: Attachment.IDType, tx: DBWriteTransaction)

    func downloadProgress(for attachmentId: Attachment.IDType, tx: DBReadTransaction) -> CGFloat?
}

extension AttachmentDownloadManager {

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
