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
