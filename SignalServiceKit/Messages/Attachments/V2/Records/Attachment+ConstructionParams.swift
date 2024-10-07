//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension Attachment {

    /// Collection of parameters for building Attachments.
    ///
    /// Identical to ``Attachment`` except it doesn't have the id (sqlite row id).
    /// Since prior to insertion we don't _have_ a row id, callers can't provide an Attachment
    /// instance for insertion. Instead they provide one of these, from which we can create
    /// an Attachment (actually an Attachment.Record) for insertion, and afterwards get
    /// back the fully fledged Attachment with id included.
    public struct ConstructionParams {
        public let blurHash: String?
        public let mimeType: String
        public let encryptionKey: Data
        public var streamInfo: StreamInfo?
        public let transitTierInfo: TransitTierInfo?
        public let mediaName: String?
        public let mediaTierInfo: MediaTierInfo?
        public let thumbnailMediaTierInfo: ThumbnailMediaTierInfo?
        public let localRelativeFilePathThumbnail: String?
        public let originalAttachmentIdForQuotedReply: Attachment.IDType?

        private init(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            streamInfo: StreamInfo?,
            transitTierInfo: TransitTierInfo?,
            mediaName: String?,
            mediaTierInfo: MediaTierInfo?,
            thumbnailMediaTierInfo: ThumbnailMediaTierInfo?,
            localRelativeFilePathThumbnail: String?,
            originalAttachmentIdForQuotedReply: Attachment.IDType?
        ) {
            self.blurHash = blurHash
            self.mimeType = mimeType
            self.encryptionKey = encryptionKey
            self.streamInfo = streamInfo
            self.transitTierInfo = transitTierInfo
            self.mediaName = mediaName
            self.mediaTierInfo = mediaTierInfo
            self.thumbnailMediaTierInfo = thumbnailMediaTierInfo
            self.localRelativeFilePathThumbnail = localRelativeFilePathThumbnail
            self.originalAttachmentIdForQuotedReply = originalAttachmentIdForQuotedReply
        }

        public static func fromPointer(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            transitTierInfo: TransitTierInfo
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: nil,
                transitTierInfo: transitTierInfo,
                mediaName: nil,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: nil
            )
        }

        public static func fromStream(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            streamInfo: StreamInfo,
            mediaName: String
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: streamInfo,
                transitTierInfo: nil,
                mediaName: mediaName,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: nil
            )
        }

        public static func fromBackup(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            transitTierInfo: TransitTierInfo?,
            mediaName: String,
            mediaTierInfo: MediaTierInfo?,
            thumbnailMediaTierInfo: ThumbnailMediaTierInfo?
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: nil,
                transitTierInfo: transitTierInfo,
                mediaName: mediaName,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: nil
            )
        }

        public static func forInvalidBackupAttachment(
            blurHash: String?,
            mimeType: String
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                // We don't have any cdn info from which to download, so what
                // encryption key we use is irrelevant. Just generate a new one.
                encryptionKey: Cryptography.randomAttachmentEncryptionKey(),
                streamInfo: nil,
                transitTierInfo: nil,
                mediaName: nil,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: nil
            )
        }

        public static func forQuotedReplyThumbnailPointer(
            originalAttachment: Attachment,
            thumbnailBlurHash: String?,
            thumbnailMimeType: String,
            thumbnailEncryptionKey: Data,
            thumbnailTransitTierInfo: TransitTierInfo?
        ) -> ConstructionParams {
            return .init(
                blurHash: thumbnailBlurHash,
                mimeType: thumbnailMimeType,
                encryptionKey: thumbnailEncryptionKey,
                streamInfo: nil,
                transitTierInfo: thumbnailTransitTierInfo,
                mediaName: nil,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: originalAttachment.id
            )
        }

        public static func forUpdatingAsDownlodedFromTransitTier(
            attachment: Attachment,
            validatedMimeType: String,
            streamInfo: Attachment.StreamInfo,
            mediaName: String
        ) -> ConstructionParams {
            let transitTierInfo = attachment.transitTierInfo.map {
                return Attachment.TransitTierInfo(
                    cdnNumber: $0.cdnNumber,
                    cdnKey: $0.cdnKey,
                    uploadTimestamp: $0.uploadTimestamp,
                    encryptionKey: $0.encryptionKey,
                    unencryptedByteCount: $0.unencryptedByteCount,
                    digestSHA256Ciphertext: $0.digestSHA256Ciphertext,
                    incrementalMacInfo: $0.incrementalMacInfo,
                    // Wipe the last download attempt time; its now succeeded.
                    lastDownloadAttemptTimestamp: nil
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: validatedMimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: streamInfo,
                transitTierInfo: transitTierInfo,
                mediaName: mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply
            )
        }

        public static func forUpdatingAsFailedDownlodFromTransitTier(
            attachment: Attachment,
            timestamp: UInt64
        ) -> ConstructionParams {
            let transitTierInfo = attachment.transitTierInfo.map {
                return Attachment.TransitTierInfo(
                    cdnNumber: $0.cdnNumber,
                    cdnKey: $0.cdnKey,
                    uploadTimestamp: $0.uploadTimestamp,
                    encryptionKey: $0.encryptionKey,
                    unencryptedByteCount: $0.unencryptedByteCount,
                    digestSHA256Ciphertext: $0.digestSHA256Ciphertext,
                    incrementalMacInfo: $0.incrementalMacInfo,
                    lastDownloadAttemptTimestamp: timestamp
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: transitTierInfo,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply
            )
        }

        public static func forUpdatingAsDownlodedFromMediaTier(
            attachment: Attachment,
            validatedMimeType: String,
            streamInfo: Attachment.StreamInfo,
            mediaName: String
        ) -> ConstructionParams {
            let mediaTierInfo = attachment.mediaTierInfo.map {
                return Attachment.MediaTierInfo(
                    cdnNumber: $0.cdnNumber,
                    unencryptedByteCount: $0.unencryptedByteCount,
                    digestSHA256Ciphertext: $0.digestSHA256Ciphertext,
                    incrementalMacInfo: $0.incrementalMacInfo,
                    uploadEra: $0.uploadEra,
                    // Wipe the last download attempt time; its now succeeded.
                    lastDownloadAttemptTimestamp: nil
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: validatedMimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                mediaName: mediaName,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply
            )
        }

        public static func forUpdatingAsFailedDownlodFromMediaTier(
            attachment: Attachment,
            timestamp: UInt64
        ) -> ConstructionParams {
            let mediaTierInfo = attachment.mediaTierInfo.map {
                return Attachment.MediaTierInfo(
                    cdnNumber: $0.cdnNumber,
                    unencryptedByteCount: $0.unencryptedByteCount,
                    digestSHA256Ciphertext: $0.digestSHA256Ciphertext,
                    incrementalMacInfo: $0.incrementalMacInfo,
                    uploadEra: $0.uploadEra,
                    lastDownloadAttemptTimestamp: timestamp
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                mediaName: attachment.mediaName,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply
            )
        }

        public static func forUpdatingAsDownlodedThumbnailFromMediaTier(
            attachment: Attachment,
            validatedMimeType: String,
            streamInfo: Attachment.StreamInfo,
            mediaName: String
        ) -> ConstructionParams {
            let thumbnailMediaTierInfo = attachment.thumbnailMediaTierInfo.map {
                return Attachment.ThumbnailMediaTierInfo(
                    cdnNumber: $0.cdnNumber,
                    uploadEra: $0.uploadEra,
                    // Wipe the last download attempt time; its now succeeded.
                    lastDownloadAttemptTimestamp: nil
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: streamInfo.localRelativeFilePath,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply
            )
        }

        public static func forUpdatingAsFailedThumbnailDownlodFromMediaTier(
            attachment: Attachment,
            timestamp: UInt64
        ) -> ConstructionParams {
            let thumbnailMediaTierInfo = attachment.thumbnailMediaTierInfo.map {
                return Attachment.ThumbnailMediaTierInfo(
                    cdnNumber: $0.cdnNumber,
                    uploadEra: $0.uploadEra,
                    lastDownloadAttemptTimestamp: timestamp
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply
            )
        }

        public static func forUpdatingWithRevalidatedContentType(
            attachment: Attachment,
            contentType: Attachment.ContentType,
            mimeType: String,
            blurHash: String?
        ) -> ConstructionParams {
            let streamInfo = attachment.streamInfo.map {
                return Attachment.StreamInfo(
                    sha256ContentHash: $0.sha256ContentHash,
                    encryptedByteCount: $0.encryptedByteCount,
                    unencryptedByteCount: $0.unencryptedByteCount,
                    contentType: contentType,
                    digestSHA256Ciphertext: $0.digestSHA256Ciphertext,
                    localRelativeFilePath: $0.localRelativeFilePath
                )
            }
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply
            )
        }

        public static func forMerging(
            streamInfo: Attachment.StreamInfo,
            into attachment: Attachment,
            mimeType: String
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply
            )
        }
    }
}
