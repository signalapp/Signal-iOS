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

    public struct DownloadMetadata: Equatable {
        public let mimeType: String
        public let cdnNumber: UInt32
        public let cdnKey: String
        public let encryptionKey: Data
        public let digest: Data
        public let plaintextLength: UInt32?

        public init(
            mimeType: String,
            cdnNumber: UInt32,
            cdnKey: String,
            encryptionKey: Data,
            digest: Data,
            plaintextLength: UInt32?
        ) {
            self.mimeType = mimeType
            self.cdnNumber = cdnNumber
            self.cdnKey = cdnKey
            self.encryptionKey = encryptionKey
            self.digest = digest
            self.plaintextLength = plaintextLength
        }
    }
}

public protocol AttachmentDownloadManager {

    func downloadBackup(
        metadata: MessageBackupRemoteInfo,
        authHeaders: [String: String]
    ) -> Promise<URL>

    func downloadTransientAttachment(
        metadata: AttachmentDownloads.DownloadMetadata
    ) -> Promise<URL>

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

    func enqueueDownloadOfAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
        tx: DBWriteTransaction
    )

    /// Starts downloading off the persisted queue, if there's anything to download
    /// and if not already downloading the max number of parallel downloads at once.
    func beginDownloadingIfNecessary()

    func cancelDownload(for attachmentId: Attachment.IDType, tx: DBWriteTransaction)

    func downloadProgress(for attachmentId: Attachment.IDType, tx: DBReadTransaction) -> CGFloat?
}

extension AttachmentDownloadManager {

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
