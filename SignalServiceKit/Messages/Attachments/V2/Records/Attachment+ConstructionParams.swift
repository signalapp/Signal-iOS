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
        public let latestTransitTierInfo: TransitTierInfo?
        public let originalTransitTierInfo: TransitTierInfo?
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
            latestTransitTierInfo: TransitTierInfo?,
            originalTransitTierInfo: TransitTierInfo?,
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
            self.latestTransitTierInfo = latestTransitTierInfo
            self.originalTransitTierInfo = originalTransitTierInfo
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
            latestTransitTierInfo: TransitTierInfo,
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: nil,
                latestTransitTierInfo: latestTransitTierInfo,
                originalTransitTierInfo: {
                    if latestTransitTierInfo.encryptionKey == encryptionKey {
                        return latestTransitTierInfo
                    } else {
                        return nil
                    }
                }(),
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
            mediaName: String,
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: streamInfo,
                latestTransitTierInfo: nil,
                originalTransitTierInfo: nil,
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
            latestTransitTierInfo: TransitTierInfo?,
            sha256ContentHash: Data?,
            mediaName: String?,
            mediaTierInfo: MediaTierInfo?,
            thumbnailMediaTierInfo: ThumbnailMediaTierInfo?,
        ) -> ConstructionParams {
            owsPrecondition(
                (sha256ContentHash == nil) == (mediaName == nil),
                "Either both hash and mediaName set or neither set",
            )
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: nil,
                latestTransitTierInfo: latestTransitTierInfo,
                originalTransitTierInfo: {
                    if latestTransitTierInfo?.encryptionKey == encryptionKey {
                        return latestTransitTierInfo
                    } else {
                        return nil
                    }
                }(),
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
            mimeType: String,
        ) -> ConstructionParams {
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                // We don't have any cdn info from which to download, so what
                // encryption key we use is irrelevant. Just generate a new one.
                encryptionKey: AttachmentKey.generate().combinedKey,
                streamInfo: nil,
                latestTransitTierInfo: nil,
                originalTransitTierInfo: nil,
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
            thumbnailTransitTierInfo: TransitTierInfo?,
        ) -> ConstructionParams {
            return .init(
                blurHash: thumbnailBlurHash,
                mimeType: thumbnailMimeType,
                encryptionKey: thumbnailEncryptionKey,
                streamInfo: nil,
                latestTransitTierInfo: thumbnailTransitTierInfo,
                originalTransitTierInfo: {
                    if thumbnailTransitTierInfo?.encryptionKey == thumbnailEncryptionKey {
                        return thumbnailTransitTierInfo
                    } else {
                        return nil
                    }
                }(),
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
            let latestTransitTierInfo: Attachment.TransitTierInfo?
            if
                let existingTransitTierInfo = attachment.latestTransitTierInfo,
                existingTransitTierInfo.encryptionKey == attachment.encryptionKey
            {
                latestTransitTierInfo = Attachment.TransitTierInfo(
                    cdnNumber: existingTransitTierInfo.cdnNumber,
                    cdnKey: existingTransitTierInfo.cdnKey,
                    uploadTimestamp: existingTransitTierInfo.uploadTimestamp,
                    encryptionKey: existingTransitTierInfo.encryptionKey,
                    unencryptedByteCount: existingTransitTierInfo.unencryptedByteCount,
                    // Whatever the integrity check was before, we now want it
                    // to be the ciphertext digest NOT the plaintext hash.
                    // We disallow reusing existing transit tier info when
                    // forwarding if it doesn't have a digest, as digest is
                    // required on the outgoing proto. So to allow forwarding
                    // (where otherwise applicable) set the digest here.
                    integrityCheck: .digestSHA256Ciphertext(digestSHA256Ciphertext),
                    incrementalMacInfo: existingTransitTierInfo.incrementalMacInfo,
                    // Wipe the last download attempt time; its now succeeded.
                    lastDownloadAttemptTimestamp: nil,
                )
            } else if
                let existingTransitTierInfo = attachment.latestTransitTierInfo,
                case .digestSHA256Ciphertext = existingTransitTierInfo.integrityCheck
            {
                latestTransitTierInfo = existingTransitTierInfo
            } else {
                latestTransitTierInfo = nil
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: validatedMimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: streamInfo,
                latestTransitTierInfo: latestTransitTierInfo,
                // Original info is unaffected by a download
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            timestamp: UInt64,
        ) -> ConstructionParams {
            let latestTransitTierInfo = attachment.latestTransitTierInfo.map {
                return Attachment.TransitTierInfo(
                    cdnNumber: $0.cdnNumber,
                    cdnKey: $0.cdnKey,
                    uploadTimestamp: $0.uploadTimestamp,
                    encryptionKey: $0.encryptionKey,
                    unencryptedByteCount: $0.unencryptedByteCount,
                    integrityCheck: $0.integrityCheck,
                    incrementalMacInfo: $0.incrementalMacInfo,
                    lastDownloadAttemptTimestamp: timestamp,
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: latestTransitTierInfo,
                // We don't bother updating last download attempt on the original info
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            latestTransitTierInfo: TransitTierInfo,
            originalTransitTierInfo: TransitTierInfo?,
        ) -> ConstructionParams {
            let attachment = stream.attachment
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: latestTransitTierInfo,
                originalTransitTierInfo: originalTransitTierInfo,
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
            from attachment: Attachment,
            removeLatestTransitTierInfo: Bool,
            removeOriginalTransitTierInfo: Bool,
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: removeLatestTransitTierInfo ? nil : attachment.latestTransitTierInfo,
                originalTransitTierInfo: removeOriginalTransitTierInfo ? nil : attachment.originalTransitTierInfo,
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
            mediaName: String,
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: attachment.latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            attachment: Attachment,
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: attachment.latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            mediaName: String,
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: attachment.latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            attachment: Attachment,
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: attachment.latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
                    lastDownloadAttemptTimestamp: nil,
                )
            }
            let latestTransitTierInfo: Attachment.TransitTierInfo?
            if
                let existingTransitTierInfo = attachment.latestTransitTierInfo,
                existingTransitTierInfo.encryptionKey == attachment.encryptionKey
            {
                latestTransitTierInfo = Attachment.TransitTierInfo(
                    cdnNumber: existingTransitTierInfo.cdnNumber,
                    cdnKey: existingTransitTierInfo.cdnKey,
                    uploadTimestamp: existingTransitTierInfo.uploadTimestamp,
                    encryptionKey: existingTransitTierInfo.encryptionKey,
                    unencryptedByteCount: existingTransitTierInfo.unencryptedByteCount,
                    // Whatever the integrity check was before, we now want it
                    // to be the ciphertext digest NOT the plaintext hash.
                    // We disallow reusing existing transit tier info when
                    // forwarding if it doesn't have a digest, as digest is
                    // required on the outgoing proto. So to allow forwarding
                    // (where otherwise applicable) set the digest here.
                    integrityCheck: .digestSHA256Ciphertext(streamInfo.digestSHA256Ciphertext),
                    incrementalMacInfo: existingTransitTierInfo.incrementalMacInfo,
                    // Wipe the last download attempt time; its now succeeded.
                    lastDownloadAttemptTimestamp: nil,
                )
            } else if
                let existingTransitTierInfo = attachment.latestTransitTierInfo,
                case .digestSHA256Ciphertext = existingTransitTierInfo.integrityCheck
            {
                latestTransitTierInfo = existingTransitTierInfo
            } else {
                latestTransitTierInfo = nil
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: validatedMimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: streamInfo,
                latestTransitTierInfo: latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            timestamp: UInt64,
        ) -> ConstructionParams {
            let mediaTierInfo = attachment.mediaTierInfo.map {
                return Attachment.MediaTierInfo(
                    cdnNumber: $0.cdnNumber,
                    unencryptedByteCount: $0.unencryptedByteCount,
                    sha256ContentHash: $0.sha256ContentHash,
                    incrementalMacInfo: $0.incrementalMacInfo,
                    uploadEra: $0.uploadEra,
                    lastDownloadAttemptTimestamp: timestamp,
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: attachment.latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            streamInfo: Attachment.StreamInfo,
        ) -> ConstructionParams {
            let thumbnailMediaTierInfo = attachment.thumbnailMediaTierInfo.map {
                return Attachment.ThumbnailMediaTierInfo(
                    cdnNumber: $0.cdnNumber,
                    uploadEra: $0.uploadEra,
                    // Wipe the last download attempt time; its now succeeded.
                    lastDownloadAttemptTimestamp: nil,
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: attachment.latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            timestamp: UInt64,
        ) -> ConstructionParams {
            let thumbnailMediaTierInfo = attachment.thumbnailMediaTierInfo.map {
                return Attachment.ThumbnailMediaTierInfo(
                    cdnNumber: $0.cdnNumber,
                    uploadEra: $0.uploadEra,
                    lastDownloadAttemptTimestamp: timestamp,
                )
            }
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: attachment.latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            blurHash: String?,
        ) -> ConstructionParams {
            let streamInfo = attachment.streamInfo.map {
                return Attachment.StreamInfo(
                    sha256ContentHash: $0.sha256ContentHash,
                    mediaName: $0.mediaName,
                    encryptedByteCount: $0.encryptedByteCount,
                    unencryptedByteCount: $0.unencryptedByteCount,
                    contentType: contentType,
                    digestSHA256Ciphertext: $0.digestSHA256Ciphertext,
                    localRelativeFilePath: $0.localRelativeFilePath,
                )
            }
            return .init(
                blurHash: blurHash,
                mimeType: mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: streamInfo,
                latestTransitTierInfo: attachment.latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            latestTransitTierInfo: TransitTierInfo?,
            originalTransitTierInfo: TransitTierInfo?,
            mediaTierInfo: MediaTierInfo?,
            thumbnailMediaTierInfo: ThumbnailMediaTierInfo?,
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: mimeType,
                encryptionKey: encryptionKey,
                streamInfo: streamInfo,
                latestTransitTierInfo: latestTransitTierInfo,
                originalTransitTierInfo: originalTransitTierInfo,
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
            viewTimestamp: UInt64,
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                streamInfo: attachment.streamInfo,
                latestTransitTierInfo: attachment.latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
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
            attachment: Attachment,
            localRelativeFilePathThumbnail: String?,
        ) -> ConstructionParams {
            return .init(
                blurHash: attachment.blurHash,
                mimeType: attachment.mimeType,
                encryptionKey: attachment.encryptionKey,
                // Remove stream info
                streamInfo: nil,
                latestTransitTierInfo: attachment.latestTransitTierInfo,
                originalTransitTierInfo: attachment.originalTransitTierInfo,
                // Keep sha256ContentHash and medianame so we can download again
                sha256ContentHash: attachment.sha256ContentHash,
                mediaName: attachment.mediaName,
                mediaTierInfo: attachment.mediaTierInfo,
                thumbnailMediaTierInfo: attachment.thumbnailMediaTierInfo,
                localRelativeFilePathThumbnail: localRelativeFilePathThumbnail ?? attachment.localRelativeFilePathThumbnail,
                originalAttachmentIdForQuotedReply: attachment.originalAttachmentIdForQuotedReply,
                lastFullscreenViewTimestamp: attachment.lastFullscreenViewTimestamp,
            )
        }
    }
}
