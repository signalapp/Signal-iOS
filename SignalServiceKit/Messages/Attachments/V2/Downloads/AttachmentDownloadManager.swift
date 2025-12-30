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

    /// Key for a CGFloat progress value from 0 to 1
    public static var attachmentDownloadProgressKey: String { "attachmentDownloadProgressKey" }

    /// Label for ``AttachmentDownloadManager`` download progress source.
    public static var downloadProgressLabel: String { "download" }

    /// Key for a ``Attachment.IdType`` value.
    public static var attachmentDownloadAttachmentIDKey: String { "attachmentDownloadAttachmentIDKey" }

    public struct DownloadMetadata {
        public let mimeType: String
        public let cdnNumber: UInt32
        public let encryptionKey: Data
        public let source: Source

        public enum Source {
            case transitTier(cdnKey: String, integrityCheck: AttachmentIntegrityCheck, plaintextLength: UInt32?)
            case mediaTierFullsize(
                cdnReadCredential: MediaTierReadCredential,
                outerEncryptionMetadata: MediaTierEncryptionMetadata,
                integrityCheck: AttachmentIntegrityCheck,
                plaintextLength: UInt32?,
            )
            case mediaTierThumbnail(
                cdnReadCredential: MediaTierReadCredential,
                outerEncyptionMetadata: MediaTierEncryptionMetadata,
                innerEncryptionMetadata: MediaTierEncryptionMetadata,
            )
            case linkNSyncBackup(cdnKey: String)

            var asQueuedDownloadSource: QueuedAttachmentDownloadRecord.SourceType {
                switch self {
                case .transitTier:
                    return .transitTier
                case .mediaTierFullsize:
                    return .mediaTierFullsize
                case .mediaTierThumbnail:
                    return .mediaTierThumbnail
                case .linkNSyncBackup:
                    return .transitTier
                }
            }
        }

        public var integrityCheck: AttachmentIntegrityCheck? {
            switch source {
            case .transitTier(_, let integrityCheck, _):
                return integrityCheck
            case .mediaTierFullsize(_, _, let integrityCheck, _):
                return integrityCheck
            case .mediaTierThumbnail:
                // No integrityCheck for media tier thumbnails; they come from the local user.
                return nil
            case .linkNSyncBackup:
                // No integrityCheck for link'n'sync backups; they come from the local user.
                return nil
            }
        }

        public var plaintextLength: UInt32? {
            switch source {
            case .transitTier(_, _, let plaintextLength):
                return plaintextLength
            case .mediaTierFullsize(_, _, _, let plaintextLength):
                return plaintextLength
            case .mediaTierThumbnail:
                // Thumbnails don't include a length out of band.
                // They may be padded with 0s to hit bucket sizes, but
                // we take advantage of the fact that jpegs support
                // no-op trailing 0s (and all thumbnails are jpegs).
                return nil
            case .linkNSyncBackup:
                // Link'n'sync backups don't include a length out
                // of band because gzip ignores padding.
                return nil
            }
        }

        public init(
            mimeType: String,
            cdnNumber: UInt32,
            encryptionKey: Data,
            source: Source,
        ) {
            self.mimeType = mimeType
            self.cdnNumber = cdnNumber
            self.encryptionKey = encryptionKey
            self.source = source
        }
    }

    public enum Error: Swift.Error, Equatable {
        case expiredCredentials
        case blockedByActiveCall
        case blockedByPendingMessageRequest
        case blockedByAutoDownloadSettings
        case blockedByNetworkState
    }

    public struct CdnInfo {
        public let contentLength: UInt
        public let lastModified: Date
    }
}

public protocol AttachmentDownloadManager {

    func backupCdnInfo(
        metadata: BackupReadCredential,
    ) async throws -> BackupCdnInfo

    func downloadBackup(
        metadata: BackupReadCredential,
        progress: OWSProgressSink?,
    ) -> Promise<URL>

    func downloadTransientAttachment(
        metadata: AttachmentDownloads.DownloadMetadata,
        progress: OWSProgressSink?,
    ) -> Promise<URL>

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

    func enqueueDownloadOfAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
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

    public func downloadTransientAttachment(
        metadata: AttachmentDownloads.DownloadMetadata,
    ) -> Promise<URL> {
        return downloadTransientAttachment(
            metadata: metadata,
            progress: nil,
        )
    }

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

    public func downloadAttachment(
        id: Attachment.IDType,
        priority: AttachmentDownloadPriority,
        source: QueuedAttachmentDownloadRecord.SourceType,
    ) async throws {
        try await downloadAttachment(
            id: id,
            priority: priority,
            source: source,
            progress: nil,
        )
    }
}
