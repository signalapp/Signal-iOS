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
        public let sha256ContentHash: Data?
        public let mediaName: String?
        public let mediaTierInfo: MediaTierInfo?
        public let thumbnailMediaTierInfo: ThumbnailMediaTierInfo?
        public let localRelativeFilePathThumbnail: String?
        public let originalAttachmentIdForQuotedReply: Attachment.IDType?
        public let lastFullscreenViewTimestamp: UInt64?

        private init(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            streamInfo: StreamInfo?,
            transitTierInfo: TransitTierInfo?,
            sha256ContentHash: Data?,
            mediaName: String?,
            mediaTierInfo: MediaTierInfo?,
            thumbnailMediaTierInfo: ThumbnailMediaTierInfo?,
            localRelativeFilePathThumbnail: String?,
            originalAttachmentIdForQuotedReply: Attachment.IDType?,
            lastFullscreenViewTimestamp: UInt64?,
        ) {
            self.blurHash = blurHash
            self.mimeType = mimeType
            self.encryptionKey = encryptionKey
            self.streamInfo = streamInfo
            self.transitTierInfo = transitTierInfo
            self.sha256ContentHash = sha256ContentHash
            self.mediaName = mediaName
            self.mediaTierInfo = mediaTierInfo
            self.thumbnailMediaTierInfo = thumbnailMediaTierInfo
            self.localRelativeFilePathThumbnail = localRelativeFilePathThumbnail
            self.originalAttachmentIdForQuotedReply = originalAttachmentIdForQuotedReply
            self.lastFullscreenViewTimestamp = lastFullscreenViewTimestamp
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
                sha256ContentHash: nil,
                mediaName: nil,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: nil,
                lastFullscreenViewTimestamp: nil,
            )
        }

        public static func fromStream(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            streamInfo: StreamInfo,
            sha256ContentHash: Data,
            mediaName: String
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: streamInfo,
                transitTierInfo: nil,
                sha256ContentHash: sha256ContentHash,
                mediaName: mediaName,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: nil,
                lastFullscreenViewTimestamp: nil,
            )
        }

        public static func fromBackup(
            blurHash: String?,
            mimeType: String,
            encryptionKey: Data,
            transitTierInfo: TransitTierInfo?,
            sha256ContentHash: Data?,
            mediaName: String?,
            mediaTierInfo: MediaTierInfo?,
            thumbnailMediaTierInfo: ThumbnailMediaTierInfo?
        ) -> ConstructionParams {
            owsPrecondition(
                (sha256ContentHash == nil) == (mediaName == nil),
                "Either both hash and mediaName set or neither set"
            )
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: nil,
                transitTierInfo: transitTierInfo,
                sha256ContentHash: sha256ContentHash,
                mediaName: mediaName,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: nil,
                lastFullscreenViewTimestamp: nil,
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
                sha256ContentHash: nil,
                mediaName: nil,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: nil,
                lastFullscreenViewTimestamp: nil,
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
                sha256ContentHash: nil,
                mediaName: nil,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: originalAttachment.id,
                lastFullscreenViewTimestamp: nil,
            )
        }

        public static func forUpdatingAsDownlodedFromTransitTier(
            attachment: Attachment,
            validatedMimeType: String,
            streamInfo: Attachment.StreamInfo,
            sha256ContentHash: Data,
            digestSHA256Ciphertext: Data,
            mediaName: String,
            lastFullscreenViewTimestamp: UInt64?,
        ) -> ConstructionParams {
            let transitTierInfo = attachment.transitTierInfo.map {
                return Attachment.TransitTierInfo(
                    cdnNumber: $0.cdnNumber,
                    cdnKey: $0.cdnKey,
                    uploadTimestamp: $0.uploadTimestamp,
                    encryptionKey: $0.encryptionKey,
                    unencryptedByteCount: $0.unencryptedByteCount,
                    // Whatever the integrity check was before, we now want it
                    // to be the ciphertext digest NOT the plaintext hash.
                    // We disallow reusing existing transit tier info when
                    // forwarding if it doesn't have a digest, as digest is
                    // required on the outgoing proto. So to allow forwarding
                    // (where otherwise applicable) set the digest here.
                    integrityCheck: .digestSHA256Ciphertext(digestSHA256Ciphertext),
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
                sha256ContentHash: sha256ContentHash,
                mediaName: mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: lastFullscreenViewTimestamp ?? attachment.lastFullscreenViewTimestamp,
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
                    integrityCheck: $0.integrityCheck,
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
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }

        public static func forUpdatingAsUploadedToTransitTier(
            attachment stream: AttachmentStream,
            transitTierInfo: TransitTierInfo
        ) -> ConstructionParams {
            let attachment = stream.attachment
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: transitTierInfo,
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }

        public static func forRemovingTransitTierInfo(
            attachment: Attachment
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: nil,
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }

        public static func forUpdatingAsUploadedToMediaTier(
            attachment: Attachment,
            mediaTierInfo: MediaTierInfo,
            mediaName: String
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: mediaName,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }

        public static func forRemovingMediaTierInfo(
            attachment: Attachment
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: nil,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }

        public static func forUpdatingAsUploadedThumbnailToMediaTier(
            attachment: Attachment,
            thumbnailMediaTierInfo: ThumbnailMediaTierInfo,
            mediaName: String
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }

        public static func forRemovingThumbnailMediaTierInfo(
            attachment: Attachment
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: nil,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }

        public static func forUpdatingAsDownlodedFromMediaTier(
            attachment: Attachment,
            validatedMimeType: String,
            streamInfo: Attachment.StreamInfo,
            sha256ContentHash: Data,
            mediaName: String,
            lastFullscreenViewTimestamp: UInt64?,
        ) -> ConstructionParams {
            let mediaTierInfo = attachment.mediaTierInfo.map {
                return Attachment.MediaTierInfo(
                    cdnNumber: $0.cdnNumber,
                    unencryptedByteCount: $0.unencryptedByteCount,
                    sha256ContentHash: $0.sha256ContentHash,
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
                sha256ContentHash: sha256ContentHash,
                mediaName: mediaName,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: lastFullscreenViewTimestamp ?? attachment.lastFullscreenViewTimestamp,
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
                    sha256ContentHash: $0.sha256ContentHash,
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
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }

        public static func forUpdatingAsDownlodedThumbnailFromMediaTier(
            attachment: Attachment,
            validatedMimeType: String,
            streamInfo: Attachment.StreamInfo
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
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: streamInfo.localRelativeFilePath,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
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
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
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
                    mediaName: $0.mediaName,
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
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }

        public static func forMerging(
            streamInfo: Attachment.StreamInfo,
            into attachment: Attachment,
            encryptionKey: Data,
            mimeType: String,
            mediaTierInfo: MediaTierInfo?,
            thumbnailMediaTierInfo: ThumbnailMediaTierInfo?
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: streamInfo,
                // We preserve the transit tier info even if the encrytion key
                // changes underneath because it has its own copy of encryption
                // key, digest, etc, and can therefore be encrypted differently
                // than the local copy.
                // We _would_ need to remove it if we changed the plaintext hash
                // of the underlying attachment, but that's not possible; we get
                // here by having a plaintext hash or mediaName collision, and
                // either of those mean the plaintext hash isn't changing (since
                // the plaintext hash is literally part of the mediaName).
                transitTierInfo: attachment.transitTierInfo,
                sha256ContentHash: streamInfo.sha256ContentHash,
                mediaName: streamInfo.mediaName,
                mediaTierInfo: mediaTierInfo,
                thumbnailMediaTierInfo: thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: nil,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }

        public static func forMarkingViewedFullscreen(
            attachment: Attachment,
            viewTimestamp: UInt64
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                transitTierInfo: attachment.transitTierInfo,
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: viewTimestamp,
            )
        }

        public static func forOffloadingFiles(
            attachment: Attachment
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                // Remove stream info
                streamInfo: nil,
                transitTierInfo: attachment.transitTierInfo,
                // Keep sha256ContentHash and medianame so we can download again
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }
    }
}
