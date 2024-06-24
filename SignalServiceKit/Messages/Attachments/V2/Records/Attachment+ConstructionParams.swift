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
                    // Wipe the last download attempt time; its now succeeded.
                    lastDownloadAttemptTimestamp: nil
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
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
    }
}
