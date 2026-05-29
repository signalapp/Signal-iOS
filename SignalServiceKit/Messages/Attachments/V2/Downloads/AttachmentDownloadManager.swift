//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public enum AttachmentDownloads {

    /// There's two sources of truth for calculating download progress,
    /// OWSProgress handles partial progress and AttachmentDownloadManager.downloadAttachment
    /// handles errors and success. To avoid double counting progress updates
    /// we keep a set of completed downloads and ignore progress
    /// updates if the download has already completed. However, we still send the
    /// attachmentDownloadProgressNotification in this case.
    public static let attachmentDownloadProgressNotification = Notification.Name("AttachmentDownloadProgressNotification")

    /// Notification that the current attempt to download has stopped.  This could be due to ineligibility, cancellation, or other errors.
    /// The download may  restart based on the type of error, or user interaction, which would result
    /// in `attachmentDownloadProgressNotification` notifications being sent once download progress begins again.
    public static let attachmentDownloadStoppedNotification = Notification.Name("attachmentDownloadStoppedNotification")

    /// Key for a CGFloat progress value from 0 to 1
    public static var attachmentDownloadProgressKey: String { "attachmentDownloadProgressKey" }

    /// Label for ``AttachmentDownloadManager`` download progress source.
    public static var downloadProgressLabel: String { "download" }

    /// Key for a ``Attachment.IdType`` value.
    public static var attachmentDownloadAttachmentIDKey: String { "attachmentDownloadAttachmentIDKey" }

    public struct DownloadMetadata {
        public let cdnNumber: UInt32
        public let source: Source

        public enum Source {
            case transitTier(cdnKey: String)
            case mediaTier(type: MediaTierType, cdnReadCredential: MediaTierReadCredential, mediaId: Data)

            public enum MediaTierType {
                case fullsize
                case thumbnail
            }

            var asQueuedDownloadSource: QueuedAttachmentDownloadRecord.SourceType {
                switch self {
                case .transitTier:
                    return .transitTier
                case .mediaTier(type: .fullsize, _, _):
                    return .mediaTierFullsize
                case .mediaTier(type: .thumbnail, _, _):
                    return .mediaTierThumbnail
                }
            }
        }

        public init(
            cdnNumber: UInt32,
            source: Source,
        ) {
            self.cdnNumber = cdnNumber
            self.source = source
        }
    }

    public enum Error: Swift.Error {
        case expiredCredentials
        case blockedByActiveCall
        case blockedByPendingMessageRequest
        case blockedByAutoDownloadSettings
        case blockedByNetworkState
    }

    public struct CdnInfo {
        public let contentLength: UInt64
        public let lastModified: Date

        public init(contentLength: UInt64, lastModified: Date) {
            self.contentLength = contentLength
            self.lastModified = lastModified
        }

        init(_ headers: HttpHeaders) throws {
            guard
                let contentLengthRaw = headers["Content-Length"],
                let contentLengthBytes = UInt64(contentLengthRaw)
            else {
                throw OWSGenericError("Missing content length from cdn")
            }
            self.contentLength = contentLengthBytes

            guard
                let lastModifiedRaw = headers["Last-Modified"],
                let lastModifiedDate = Date.ows_parseFromHTTPDateString(lastModifiedRaw)
            else {
                throw OWSGenericError("Missing last modified from cdn")
            }
            self.lastModified = lastModifiedDate
        }
    }
}

public protocol AttachmentDownloadManager {

    func backupCdnInfo(
        metadata: BackupReadCredential,
    ) async throws -> BackupCdnInfo

    func downloadBackup(
        metadata: BackupReadCredential,
        progress: OWSProgressSink?,
    ) async throws -> URL

    func downloadEncryptedTransientAttachment(
        downloadMetadata: AttachmentDownloads.DownloadMetadata,
        expectedDownloadSize: UInt64?,
        progress: OWSProgressSink?,
    ) async throws -> URL

    func downloadTransientAttachment(
        downloadMetadata: AttachmentDownloads.DownloadMetadata,
        decryptionMetadata: DecryptionMetadata,
        expectedDownloadSize: UInt64?,
        progress: OWSProgressSink?,
    ) async throws -> URL

    func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    )

    func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    )

    func enqueueDownloadOfReferencedAttachment(
        referencedAttachment: ReferencedAttachment,
        priority: AttachmentDownloadPriority,
        tx: DBWriteTransaction,
    ) throws(AttachmentDownloads.Error)

    func downloadReferencedAttachment(
        referencedAttachment: ReferencedAttachment,
        priority: AttachmentDownloadPriority,
        progress: OWSProgressSink?,
    ) async throws

    func enqueueCopyOfLocalAttachment(
        id: Attachment.IDType,
        tx: DBWriteTransaction,
    )

    /// There's two sources of truth for calculating download progress,
    /// OWSProgress handles partial progress and this method returning (or throwing)
    /// handles errors and success. To avoid double counting progress updates
    /// we keep a set of completed downloads and ignore progress
    /// updates if the download has already completed. However, we still send the
    /// attachmentDownloadProgressNotification in this case.
    func downloadAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
        progress: OWSProgressSink?,
    ) async throws

    /// Starts downloading off the persisted queue, if there's anything to download
    /// and if not already downloading the max number of parallel downloads at once.
    func beginDownloadingIfNecessary()

    func cancelDownload(for attachmentId: Attachment.IDType, tx: DBWriteTransaction)
}

extension AttachmentDownloadManager {

    public func enqueueDownloadOfAttachmentsForMessage(
        _ message: TSMessage,
        tx: DBWriteTransaction,
    ) {
        enqueueDownloadOfAttachmentsForMessage(message, priority: .default, tx: tx)
    }

    public func enqueueDownloadOfAttachmentsForStoryMessage(
        _ message: StoryMessage,
        tx: DBWriteTransaction,
    ) {
        enqueueDownloadOfAttachmentsForStoryMessage(message, priority: .default, tx: tx)
    }

}
