//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension TSAttachmentMigration {

    struct V1Attachment: Codable, MutablePersistableRecord, FetchableRecord {
        static let databaseTableName: String = "model_TSAttachment"

        enum AttachmentType: Int, Codable, Equatable {
            case `default` = 0
            case voiceMessage = 1
            case borderless = 2
            case gif = 3
        }

        static let attachmentPointerSDSRecordType: UInt32 = 3
        static let attachmentStreamSDSRecordType: UInt32 = 18
        static let attachmentSDSRecordType: UInt32 = 6

        var id: Int64?
        var recordType: UInt32
        var uniqueId: String
        var albumMessageId: String?
        var attachmentType: V1Attachment.AttachmentType
        var blurHash: String?
        var byteCount: UInt32
        var caption: String?
        var contentType: String
        var encryptionKey: Data?
        var serverId: UInt64
        var sourceFilename: String?
        var cachedAudioDurationSeconds: Double?
        var cachedImageHeight: Double?
        var cachedImageWidth: Double?
        var creationTimestamp: Double?
        var digest: Data?
        var isUploaded: Bool?
        var isValidImageCached: Bool?
        var isValidVideoCached: Bool?
        var lazyRestoreFragmentId: String?
        var localRelativeFilePath: String?
        var mediaSize: Data?
        var pointerType: UInt?
        var state: UInt32?
        var uploadTimestamp: UInt64
        var cdnKey: String
        var cdnNumber: UInt32
        var isAnimatedCached: Bool?
        var attachmentSchemaVersion: UInt
        var videoDuration: Double?
        var clientUuid: String?

        var localFilePath: String? {
            guard let localRelativeFilePath else {
                 return nil
            }
            let rootPath = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: TSConstants.applicationGroup
            )!.path
            let attachmentsFolder = rootPath.appendingPathComponent("Attachments")
            return attachmentsFolder.appendingPathComponent(localRelativeFilePath)
        }

        var thumbnailsDirPath: String {
            let dirName = "\(uniqueId)-thumbnails"
            return OWSFileSystem.cachesDirectoryPath().appendingPathComponent(dirName)
        }

        var legacyThumbnailPath: String? {
            guard let localRelativeFilePath else {
                return nil
            }
            let filename = ((localRelativeFilePath as NSString).lastPathComponent as NSString).deletingPathExtension
            let containingDir = (localRelativeFilePath as NSString).deletingLastPathComponent
            let newFilename = filename.appending("-signal-ios-thumbnail")
            return containingDir.appendingPathComponent(newFilename).appendingFileExtension("jpg")
        }

        var uniqueIdAttachmentFolder: String {
            let rootPath = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: TSConstants.applicationGroup
            )!.path
            let attachmentsFolder = rootPath.appendingPathComponent("Attachments")
            return attachmentsFolder.appendingPathComponent(self.uniqueId)
        }

        func deleteFiles() throws {
            // Ignore failure cuz its a cache directory anyway.
            _ = OWSFileSystem.deleteFileIfExists(thumbnailsDirPath)

            if let legacyThumbnailPath {
                guard OWSFileSystem.deleteFileIfExists(legacyThumbnailPath) else {
                    throw OWSAssertionError("Failed to delete file")
                }
            }

            if let localFilePath {
                guard OWSFileSystem.deleteFileIfExists(localFilePath) else {
                    throw OWSAssertionError("Failed to delete file")
                }
            }

            guard OWSFileSystem.deleteFileIfExists(uniqueIdAttachmentFolder) else {
                throw OWSAssertionError("Failed to delete folder")
            }
        }

        func deleteMediaGalleryRecord(tx: GRDBWriteTransaction) throws {
            try tx.database.execute(
                sql: "DELETE FROM media_gallery_items WHERE attachmentId = ?",
                arguments: [self.id]
            )
        }
    }

    struct V1AttachmentReservedFileIds: Codable, MutablePersistableRecord, FetchableRecord {
        static let databaseTableName: String = "TSAttachmentMigration"

        var tsAttachmentUniqueId: String
        var interactionRowId: Int64?
        var storyMessageRowId: Int64?
        var reservedV2AttachmentPrimaryFileId: UUID
        var reservedV2AttachmentAudioWaveformFileId: UUID
        var reservedV2AttachmentVideoStillFrameFileId: UUID

        static var databaseUUIDEncodingStrategy: DatabaseUUIDEncodingStrategy = .deferredToUUID

        init(
            tsAttachmentUniqueId: String,
            interactionRowId: Int64?,
            storyMessageRowId: Int64?,
            reservedV2AttachmentPrimaryFileId: UUID,
            reservedV2AttachmentAudioWaveformFileId: UUID,
            reservedV2AttachmentVideoStillFrameFileId: UUID
        ) {
            self.tsAttachmentUniqueId = tsAttachmentUniqueId
            self.interactionRowId = interactionRowId
            self.storyMessageRowId = storyMessageRowId
            self.reservedV2AttachmentPrimaryFileId = reservedV2AttachmentPrimaryFileId
            self.reservedV2AttachmentAudioWaveformFileId = reservedV2AttachmentAudioWaveformFileId
            self.reservedV2AttachmentVideoStillFrameFileId = reservedV2AttachmentVideoStillFrameFileId
        }

        func cleanUpFiles() throws {
            for uuid in [
                self.reservedV2AttachmentPrimaryFileId,
                self.reservedV2AttachmentAudioWaveformFileId,
                self.reservedV2AttachmentVideoStillFrameFileId
            ] {
                let relPath = TSAttachmentMigration.V2Attachment.relativeFilePath(reservedUUID: uuid)
                let fileUrl = TSAttachmentMigration.V2Attachment.absoluteAttachmentFileURL(
                    relativeFilePath: relPath
                )
                try OWSFileSystem.deleteFileIfExists(url: fileUrl)
            }
        }
    }

    struct V2Attachment: Codable, MutablePersistableRecord, FetchableRecord {
        static let databaseTableName: String = "Attachment"

        enum ContentType: Int {
            case invalid = 0
            case file = 1
            case image = 2
            case video = 3
            case animatedImage = 4
            case audio = 5
        }

        var id: Int64?
        var blurHash: String?
        var sha256ContentHash: Data?
        var encryptedByteCount: UInt32?
        var unencryptedByteCount: UInt32?
        var mimeType: String
        var encryptionKey: Data
        var digestSHA256Ciphertext: Data?
        var contentType: UInt32?
        var transitCdnNumber: UInt32?
        var transitCdnKey: String?
        var transitUploadTimestamp: UInt64?
        var transitEncryptionKey: Data?
        var transitUnencryptedByteCount: UInt32?
        var transitDigestSHA256Ciphertext: Data?
        var lastTransitDownloadAttemptTimestamp: UInt64?
        var mediaName: String?
        var mediaTierCdnNumber: UInt32?
        var mediaTierUnencryptedByteCount: UInt32?
        var mediaTierUploadEra: String?
        var lastMediaTierDownloadAttemptTimestamp: UInt64?
        var thumbnailCdnNumber: UInt32?
        var thumbnailUploadEra: String?
        var lastThumbnailDownloadAttemptTimestamp: UInt64?
        var localRelativeFilePath: String?
        var localRelativeFilePathThumbnail: String?
        var cachedAudioDurationSeconds: Double?
        var cachedMediaHeightPixels: UInt32?
        var cachedMediaWidthPixels: UInt32?
        var cachedVideoDurationSeconds: Double?
        var audioWaveformRelativeFilePath: String?
        var videoStillFrameRelativeFilePath: String?
        var originalAttachmentIdForQuotedReply: Int64?

        init(
            id: Int64?,
            blurHash: String?,
            sha256ContentHash: Data?,
            encryptedByteCount: UInt32?,
            unencryptedByteCount: UInt32?,
            mimeType: String,
            encryptionKey: Data,
            digestSHA256Ciphertext: Data?,
            contentType: UInt32?,
            transitCdnNumber: UInt32?,
            transitCdnKey: String?,
            transitUploadTimestamp: UInt64?,
            transitEncryptionKey: Data?,
            transitUnencryptedByteCount: UInt32?,
            transitDigestSHA256Ciphertext: Data?,
            lastTransitDownloadAttemptTimestamp: UInt64?,
            mediaName: String?,
            mediaTierCdnNumber: UInt32?,
            mediaTierUnencryptedByteCount: UInt32?,
            mediaTierUploadEra: String?,
            lastMediaTierDownloadAttemptTimestamp: UInt64?,
            thumbnailCdnNumber: UInt32?,
            thumbnailUploadEra: String?,
            lastThumbnailDownloadAttemptTimestamp: UInt64?,
            localRelativeFilePath: String?,
            localRelativeFilePathThumbnail: String?,
            cachedAudioDurationSeconds: Double?,
            cachedMediaHeightPixels: UInt32?,
            cachedMediaWidthPixels: UInt32?,
            cachedVideoDurationSeconds: Double?,
            audioWaveformRelativeFilePath: String?,
            videoStillFrameRelativeFilePath: String?,
            originalAttachmentIdForQuotedReply: Int64?
        ) {
            self.id = id
            self.blurHash = blurHash
            self.sha256ContentHash = sha256ContentHash
            self.encryptedByteCount = encryptedByteCount
            self.unencryptedByteCount = unencryptedByteCount
            self.mimeType = mimeType
            self.encryptionKey = encryptionKey
            self.digestSHA256Ciphertext = digestSHA256Ciphertext
            self.contentType = contentType

            // We only set transit tier fields if they are all set.
            if
                let transitCdnNumber,
                transitCdnNumber != 0,
                let transitCdnKey = transitCdnKey?.nilIfEmpty,
                let transitEncryptionKey,
                !transitEncryptionKey.isEmpty,
                let transitUnencryptedByteCount,
                let transitDigestSHA256Ciphertext,
                !transitDigestSHA256Ciphertext.isEmpty
            {
                self.transitCdnNumber = transitCdnNumber
                self.transitCdnKey = transitCdnKey
                self.transitUploadTimestamp = transitUploadTimestamp ?? Date().ows_millisecondsSince1970
                self.transitEncryptionKey = transitEncryptionKey
                self.transitUnencryptedByteCount = transitUnencryptedByteCount
                self.transitDigestSHA256Ciphertext = transitDigestSHA256Ciphertext
            } else {
                self.transitCdnNumber = nil
                self.transitCdnKey = nil
                self.transitUploadTimestamp = nil
                self.transitEncryptionKey = nil
                self.transitUnencryptedByteCount = nil
                self.transitDigestSHA256Ciphertext = nil
            }
            self.lastTransitDownloadAttemptTimestamp = lastTransitDownloadAttemptTimestamp
            self.mediaName = mediaName
            self.mediaTierCdnNumber = mediaTierCdnNumber
            self.mediaTierUnencryptedByteCount = mediaTierUnencryptedByteCount
            self.mediaTierUploadEra = mediaTierUploadEra
            self.lastMediaTierDownloadAttemptTimestamp = lastMediaTierDownloadAttemptTimestamp
            self.thumbnailCdnNumber = thumbnailCdnNumber
            self.thumbnailUploadEra = thumbnailUploadEra
            self.lastThumbnailDownloadAttemptTimestamp = lastThumbnailDownloadAttemptTimestamp
            self.localRelativeFilePath = localRelativeFilePath
            self.localRelativeFilePathThumbnail = localRelativeFilePathThumbnail
            self.cachedAudioDurationSeconds = cachedAudioDurationSeconds
            self.cachedMediaHeightPixels = cachedMediaHeightPixels
            self.cachedMediaWidthPixels = cachedMediaWidthPixels
            self.cachedVideoDurationSeconds = cachedVideoDurationSeconds
            self.audioWaveformRelativeFilePath = audioWaveformRelativeFilePath
            self.videoStillFrameRelativeFilePath = videoStillFrameRelativeFilePath
            self.originalAttachmentIdForQuotedReply = originalAttachmentIdForQuotedReply
        }

        mutating func didInsert(with rowID: Int64, for column: String?) {
            self.id = rowID
        }

        static func relativeFilePath(reservedUUID: UUID) -> String {
            let id = reservedUUID.uuidString
            return "\(id.prefix(2))/\(id)"
        }

        static func absoluteAttachmentFileURL(relativeFilePath: String) -> URL {
            let rootUrl = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: TSConstants.applicationGroup
            )!
            let directory = rootUrl.appendingPathComponent("attachment_files")
            return directory.appendingPathComponent(relativeFilePath)
        }

        static func mediaName(digestSHA256Ciphertext: Data) -> String {
            return digestSHA256Ciphertext.hexadecimalString
        }
    }

    enum V2RenderingFlag: Int {
        case `default` = 0
        case voiceMessage = 1
        case borderless = 2
        case shouldLoop = 3
    }

    struct MessageAttachmentReference: Codable, PersistableRecord, FetchableRecord {
        static let databaseTableName: String = "MessageAttachmentReference"

        var ownerType: UInt32
        var ownerRowId: Int64
        var attachmentRowId: Int64
        var receivedAtTimestamp: UInt64
        var contentType: UInt32?
        var renderingFlag: UInt32
        var idInMessage: String?
        var orderInMessage: UInt32?
        var threadRowId: Int64
        var caption: String?
        var sourceFilename: String?
        var sourceUnencryptedByteCount: UInt32?
        var sourceMediaHeightPixels: UInt32?
        var sourceMediaWidthPixels: UInt32?
        var stickerPackId: Data?
        var stickerId: UInt32?
    }

    struct StoryMessageAttachmentReference: Codable, PersistableRecord, FetchableRecord {
        static let databaseTableName: String = "StoryMessageAttachmentReference"

        var ownerType: UInt32
        var ownerRowId: Int64
        var attachmentRowId: Int64
        var shouldLoop: Bool
        var caption: String?
        var captionBodyRanges: Data?
        var sourceFilename: String?
        var sourceUnencryptedByteCount: UInt32?
        var sourceMediaHeightPixels: UInt32?
        var sourceMediaWidthPixels: UInt32?
    }

    struct ThreadAttachmentReference: Codable, PersistableRecord, FetchableRecord {
        static let databaseTableName: String = "ThreadAttachmentReference"

        var ownerRowId: Int64?
        var attachmentRowId: Int64
        var creationTimestamp: UInt64
    }
}
