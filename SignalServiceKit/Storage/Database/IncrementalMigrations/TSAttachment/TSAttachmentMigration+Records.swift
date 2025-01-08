//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension TSAttachmentMigration {

    /// These are the "live" models this migration depends on.
    /// We point to the same Swift class/struct model as the live app on the
    /// assumption that they will need to always be backwards compatible regardless,
    /// so using them here (which requires backwards compatibility) adds no new burden.
    ///
    /// If you are writing a migration to remove these models or update them in a
    /// non-backwards compatible way, that migration likely needs to make copies of
    /// the pre-migration models so that it knows how to read them before migrating them.
    /// This migration should be updated to point at those new copies.
    enum LiveModels {
        typealias MessageBodyRanges = SignalServiceKit.MessageBodyRanges
        typealias SignalServiceAddress = SignalServiceKit.SignalServiceAddress
        typealias StyleOnlyMessageBody = SignalServiceKit.StyleOnlyMessageBody
    }

    struct V1Attachment: Codable, MutablePersistableRecord, FetchableRecord {
        static let databaseTableName: String = "model_TSAttachment"

        enum AttachmentType: Int, Codable, Equatable {
            case `default` = 0
            case voiceMessage = 1
            case borderless = 2
            case gif = 3

            var asRenderingFlag: TSAttachmentMigration.V2RenderingFlag {
                switch self {
                case .default:
                    return .default
                case .voiceMessage:
                    return .voiceMessage
                case .borderless:
                    return .borderless
                case .gif:
                    return .shouldLoop
                }
            }
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

        func sourceMediaSizePixels() throws -> (height: UInt32, width: UInt32)? {
            guard let encoded = mediaSize else {
                return nil
            }
            guard
                let decoded = try NSKeyedUnarchiver
                    .unarchiveTopLevelObjectWithData(encoded) as? CGSize
            else {
                throw OWSAssertionError("Invalid media size")
            }
            guard
                let height = UInt32(exactly: decoded.height),
                let width = UInt32(exactly: decoded.width)
            else {
                return nil
            }
            return (height, width)
        }

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

        func cleanUpFiles() {
            for uuid in [
                self.reservedV2AttachmentPrimaryFileId,
                self.reservedV2AttachmentAudioWaveformFileId,
                self.reservedV2AttachmentVideoStillFrameFileId
            ] {
                let relPath = TSAttachmentMigration.V2Attachment.relativeFilePath(reservedUUID: uuid)
                let fileUrl = TSAttachmentMigration.V2Attachment.absoluteAttachmentFileURL(
                    relativeFilePath: relPath
                )
                do {
                    try OWSFileSystem.deleteFileIfExists(url: fileUrl)
                } catch {
                    owsFail("Unable to clean up reserved files")
                }
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
            id: Int64? = nil,
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
            localRelativeFilePath: String?,
            cachedAudioDurationSeconds: Double?,
            cachedMediaHeightPixels: UInt32?,
            cachedMediaWidthPixels: UInt32?,
            cachedVideoDurationSeconds: Double?,
            audioWaveformRelativeFilePath: String?,
            videoStillFrameRelativeFilePath: String?
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
            self.mediaName = digestSHA256Ciphertext.map {
                TSAttachmentMigration.V2Attachment.mediaName(
                    digestSHA256Ciphertext: $0
                )
            }
            // Media tier and thumbnail upload info was unsupported in TSAttachment
            // and therefore will always be nil in this migration.
            self.mediaTierCdnNumber = nil
            self.mediaTierUnencryptedByteCount = nil
            self.mediaTierUploadEra = nil
            self.lastMediaTierDownloadAttemptTimestamp = nil
            self.thumbnailCdnNumber = nil
            self.thumbnailUploadEra = nil
            self.lastThumbnailDownloadAttemptTimestamp = nil
            self.localRelativeFilePath = localRelativeFilePath
            self.localRelativeFilePathThumbnail = nil
            self.cachedAudioDurationSeconds = cachedAudioDurationSeconds
            self.cachedMediaHeightPixels = cachedMediaHeightPixels
            self.cachedMediaWidthPixels = cachedMediaWidthPixels
            self.cachedVideoDurationSeconds = cachedVideoDurationSeconds
            self.audioWaveformRelativeFilePath = audioWaveformRelativeFilePath
            self.videoStillFrameRelativeFilePath = videoStillFrameRelativeFilePath
            // In the migration we never reference a quote original since the original
            // is likely unmigrated when we migrate the quoted reply.
            self.originalAttachmentIdForQuotedReply = nil
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

    enum V2MessageAttachmentOwnerType: Int {
        case bodyAttachment = 0
        case oversizeText = 1
        case linkPreview = 2
        case quotedReplyAttachment = 3
        case sticker = 4
        case contactAvatar = 5
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
        var isViewOnce: Bool
        var ownerIsPastEditRevision: Bool
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

    // MARK: - MTLModels

    private static let nsCodingMappings: [String: AnyClass] = [
        "SignalServiceKit.OWSLinkPreview": TSAttachmentMigration.OWSLinkPreview.self,
        "StickerInfo": TSAttachmentMigration.StickerInfo.self,
        "SignalServiceKit.MessageSticker": TSAttachmentMigration.MessageSticker.self,
        "OWSContact": TSAttachmentMigration.OWSContact.self,
        "OWSContactAddress": TSAttachmentMigration.OWSContactAddress.self,
        "OWSContactEmail": TSAttachmentMigration.OWSContactEmail.self,
        "OWSContactName": TSAttachmentMigration.OWSContactName.self,
        "OWSContactPhoneNumber": TSAttachmentMigration.OWSContactPhoneNumber.self,
        "OWSAttachmentInfo": TSAttachmentMigration.OWSAttachmentInfo.self,
        "TSQuotedMessage": TSAttachmentMigration.TSQuotedMessage.self,
        "SignalServiceKit.MessageBodyRanges": LiveModels.MessageBodyRanges.self,
        "SignalServiceKit.SignalServiceAddress": LiveModels.SignalServiceAddress.self,
    ]

    static func prepareNSCodingMappings(archiver: NSKeyedArchiver) {
        Self.nsCodingMappings.forEach { originalClassName, migrationClass in
            archiver.setClassName(originalClassName, for: migrationClass)
        }
    }

    static func prepareNSCodingMappings(unarchiver: NSKeyedUnarchiver) {
        Self.nsCodingMappings.forEach { originalClassName, migrationClass in
            unarchiver.setClass(migrationClass, forClassName: originalClassName)
        }
    }

    static func cleanUpNSCodingMappings(archiver: NSKeyedArchiver) {
        Self.nsCodingMappings.forEach { originalClassName, migrationClass in
            archiver.setClassName(nil, for: migrationClass)
        }
    }

    static func cleanUpNSCodingMappings(unarchiver: NSKeyedUnarchiver) {
        Self.nsCodingMappings.forEach { originalClassName, migrationClass in
            unarchiver.setClass(nil, forClassName: originalClassName)
        }
    }

    @objcMembers
    class OWSLinkPreview: MTLModel, Codable {
        var urlString: String?
        var title: String?
        var imageAttachmentId: String?
        var usesV2AttachmentReferenceValue: NSNumber?
        var previewDescription: String?
        var date: Date?

        override init() { super.init() }

        required init!(coder: NSCoder) { super.init(coder: coder) }

        required init(dictionary dictionaryValue: [String: Any]!) throws {
            try super.init(dictionary: dictionaryValue)
        }

        enum CodingKeys: String, CodingKey {
            case urlString
            case title
            case usesV2AttachmentReferenceValue
            case imageAttachmentId
            case previewDescription
            case date
        }

        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            urlString = try container.decodeIfPresent(String.self, forKey: .urlString)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            let usesV2AttachmentReferenceValue = try container.decodeIfPresent(Int.self, forKey: .usesV2AttachmentReferenceValue)
            self.usesV2AttachmentReferenceValue = usesV2AttachmentReferenceValue.map(NSNumber.init(integerLiteral:))
            imageAttachmentId = try container.decodeIfPresent(String.self, forKey: .imageAttachmentId)
            previewDescription = try container.decodeIfPresent(String.self, forKey: .previewDescription)
            date = try container.decodeIfPresent(Date.self, forKey: .date)
            super.init()
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(urlString, forKey: .urlString)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(usesV2AttachmentReferenceValue?.intValue, forKey: .usesV2AttachmentReferenceValue)
            try container.encodeIfPresent(imageAttachmentId, forKey: .imageAttachmentId)
            try container.encodeIfPresent(previewDescription, forKey: .previewDescription)
            try container.encodeIfPresent(date, forKey: .date)
        }
    }

    @objcMembers
    class StickerInfo: MTLModel {
        var packId: Data = Randomness.generateRandomBytes(16)
        var packKey: Data = Randomness.generateRandomBytes(32)
        var stickerId: UInt32 = 0

        override init() { super.init() }

        required init!(coder: NSCoder!) { super.init(coder: coder) }

        required init(dictionary: [String: Any]!) throws {
            try super.init(dictionary: dictionary)
        }
    }

    @objcMembers
    class MessageSticker: MTLModel {
        var info = TSAttachmentMigration.StickerInfo()
        var attachmentId: String?
        var emoji: String?

        override init() { super.init() }

        required init!(coder: NSCoder) { super.init(coder: coder) }

        required init(dictionary dictionaryValue: [String: Any]!) throws {
            try super.init(dictionary: dictionaryValue)
        }
    }

    @objcMembers
    public class OWSContactName: MTLModel {
        var givenName: String?
        var familyName: String?
        var namePrefix: String?
        var nameSuffix: String?
        var middleName: String?
        var nickname: String?
        var organizationName: String?

        override init() { super.init() }

        required init!(coder: NSCoder!) { super.init(coder: coder) }

        required init(dictionary dictionaryValue: [String: Any]!) throws {
            try super.init(dictionary: dictionaryValue)
        }
    }

    @objcMembers
    class OWSContactPhoneNumber: MTLModel {
        @objc
        enum `Type`: Int {
            case home = 1
            case mobile
            case work
            case custom
        }

        var phoneType: `Type` = .home
        var label: String?
        var phoneNumber: String = ""

        override init() { super.init() }

        required init!(coder: NSCoder!) { super.init(coder: coder) }

        required init(dictionary dictionaryValue: [String: Any]!) throws {
            try super.init(dictionary: dictionaryValue)
        }
    }

    @objcMembers
    class OWSContactEmail: MTLModel {
        @objc
        enum `Type`: Int {
            case home = 1
            case mobile
            case work
            case custom
        }

        var emailType: `Type` = .home
        var label: String?
        var email: String = ""

        override init() { super.init() }

        required init!(coder: NSCoder!) { super.init(coder: coder) }

        required init(dictionary dictionaryValue: [String: Any]!) throws {
            try super.init(dictionary: dictionaryValue)
        }
    }

    @objcMembers
    class OWSContactAddress: MTLModel {
        @objc
        enum `Type`: Int {
            case home = 1
            case work
            case custom
        }

        var addressType: `Type` = .home
        var label: String?
        var street: String?
        var pobox: String?
        var neighborhood: String?
        var city: String?
        var region: String?
        var postcode: String?
        var country: String?

        override init() { super.init() }

        required init!(coder: NSCoder!) { super.init(coder: coder) }

        required init(dictionary dictionaryValue: [String: Any]!) throws {
            try super.init(dictionary: dictionaryValue)
        }
    }

    @objcMembers
    class OWSContact: MTLModel {
        var name: TSAttachmentMigration.OWSContactName
        var phoneNumbers: [TSAttachmentMigration.OWSContactPhoneNumber] = []
        var emails: [TSAttachmentMigration.OWSContactEmail] = []
        var addresses: [TSAttachmentMigration.OWSContactAddress] = []
        var avatarAttachmentId: String?

        override init() {
            self.name = TSAttachmentMigration.OWSContactName()
            super.init()
        }

        required init!(coder: NSCoder!) {
            self.name = TSAttachmentMigration.OWSContactName()
            super.init(coder: coder)
        }

        required init(dictionary dictionaryValue: [String: Any]!) throws {
            self.name = TSAttachmentMigration.OWSContactName()
            try super.init(dictionary: dictionaryValue)
        }
    }

    @objc
    enum OWSAttachmentInfoReference: Int, Codable {
        case unset = 0
        case originalForSend = 1
        case original = 2
        case thumbnail = 3
        case untrustedPointer = 4
        case v2 = 5
    }

    @objcMembers
    class OWSAttachmentInfo: MTLModel, NSSecureCoding {
        var schemaVersion: UInt = 1
        var attachmentType: TSAttachmentMigration.OWSAttachmentInfoReference = .unset
        var rawAttachmentId: String = ""
        var contentType: String?
        var sourceFilename: String?

        static var supportsSecureCoding: Bool = false

        init(
            schemaVersion: UInt = 1,
            attachmentType: TSAttachmentMigration.OWSAttachmentInfoReference,
            rawAttachmentId: String,
            contentType: String?,
            sourceFilename: String?
        ) {
            self.schemaVersion = schemaVersion
            self.attachmentType = attachmentType
            self.rawAttachmentId = rawAttachmentId
            self.contentType = contentType
            self.sourceFilename = sourceFilename
            super.init()
        }

        override init() { super.init() }

        required init!(coder: NSCoder!) {
            super.init(coder: coder)

            if schemaVersion == 0 {
                let oldStreamId = coder.decodeObject(of: NSString.self, forKey: "thumbnailAttachmentStreamId")
                let oldPointerId = coder.decodeObject(of: NSString.self, forKey: "thumbnailAttachmentPointerId")
                let oldSourceAttachmentId = coder.decodeObject(of: NSString.self, forKey: "attachmentId")

                // Before, we maintained each of these IDs in parallel, though in practice only one in use at a time.
                // Migration codifies this behavior.
                if let oldStreamId, oldPointerId == oldStreamId {
                    attachmentType = .thumbnail
                    rawAttachmentId = oldStreamId as String
                } else if let oldPointerId {
                    attachmentType = .untrustedPointer
                    rawAttachmentId = oldPointerId as String
                } else if let oldStreamId {
                    attachmentType = .thumbnail
                    rawAttachmentId = oldStreamId as String
                } else if let oldSourceAttachmentId {
                    attachmentType = .originalForSend
                    rawAttachmentId = oldSourceAttachmentId as String
                } else {
                    attachmentType = .unset
                    rawAttachmentId = ""
                }
            }
            self.schemaVersion = 1
        }

        required init(dictionary dictionaryValue: [String: Any]!) throws {
            try super.init(dictionary: dictionaryValue)
        }
    }

    @objc
    enum TSQuotedMessageContentSource: Int, Codable {
        case unknown = 0
        case local = 1
        case remote = 2
        case story = 3
    }

    @objcMembers
    class TSQuotedMessage: MTLModel {
        var timestamp: UInt64 = 0
        var authorAddress: LiveModels.SignalServiceAddress?
        var bodySource: TSAttachmentMigration.TSQuotedMessageContentSource = .unknown
        var body: String?
        var bodyRanges: LiveModels.MessageBodyRanges?
        var quotedAttachment: TSAttachmentMigration.OWSAttachmentInfo?
        var isGiftBadge: Bool = false

        override init() { super.init() }

        required init!(coder: NSCoder!) {
            super.init(coder: coder)

            if authorAddress == nil, let phoneNumber = coder.decodeObject(of: NSString.self, forKey: "authorId") {
                authorAddress = LiveModels.SignalServiceAddress.legacyAddress(aciString: nil, phoneNumber: phoneNumber as String)
            }

            if
                quotedAttachment == nil,
                let array = coder.decodeObject(of: NSArray.self, forKey: "quotedAttachments"),
                let first = array.firstObject as? TSAttachmentMigration.OWSAttachmentInfo
            {
                quotedAttachment = first
            } else if
                quotedAttachment == nil,
                let quotedAttachment = coder.decodeObject(of: TSAttachmentMigration.OWSAttachmentInfo.self, forKey: "quotedAttachments")
            {
                self.quotedAttachment = quotedAttachment
            }
        }

        required init(dictionary dictionaryValue: [String: Any]!) throws {
            try super.init(dictionary: dictionaryValue)
        }
    }

    // MARK: - Styles

    struct NSRangedValue<T> {
        let range: NSRange
        let value: T
    }

    struct Style: OptionSet, Codable {
        let rawValue: Int

        init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    enum SingleStyle: Int, Codable {
        case bold = 1
        case italic = 2
        case spoiler = 4
        case strikethrough = 8
        case monospace = 16
    }

    struct MergedSingleStyle: Equatable, Codable {
        let style: TSAttachmentMigration.SingleStyle
        let mergedRange: NSRange
        let id: Int
    }

    struct CollapsedStyle: Equatable, Codable {
        let style: TSAttachmentMigration.Style
        let originals: [TSAttachmentMigration.SingleStyle: TSAttachmentMigration.MergedSingleStyle]
    }

    // MARK: - Stories

    enum SerializedStoryMessageAttachment: Codable {
        case file(attachmentId: String)
        case text(attachment: TSAttachmentMigration.TextAttachment)
        case fileV2(TSAttachmentMigration.StoryMessageFileAttachment)
        case foreignReferenceAttachment
    }

    struct StoryMessageFileAttachment: Codable {
        let attachmentId: String
        let captionStyles: [TSAttachmentMigration.NSRangedValue<TSAttachmentMigration.CollapsedStyle>]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            self.attachmentId = try container.decode(String.self, forKey: .attachmentId)

            do {
                // A year prior to this migration being written, captionStyles contained raw Styles
                // instead of collapsed styles. Stories expire in 24 hours. Byt the time of this
                // migration any story with the non-collapsed style is expired; technically though
                // this migration runs before StoryManager deletes expired stories. So we need to not
                // fail, but its ok to drop the caption styles since its about to be deleted anyway.
                self.captionStyles = try container.decode([TSAttachmentMigration.NSRangedValue<TSAttachmentMigration.CollapsedStyle>].self, forKey: .captionStyles)
            } catch {
                self.captionStyles = []
            }
        }
    }

    struct TextAttachment: Codable, Equatable {

        enum TextStyle: Int, Codable, Equatable {
            case regular = 0
            case bold = 1
            case serif = 2
            case script = 3
            case condensed = 4
        }

        enum RawBackground: Codable, Equatable {
            case color(hex: UInt32)
            case gradient(raw: Self.RawGradient)

            struct RawGradient: Codable, Equatable {
                let colors: [UInt32]
                let positions: [Float]
                let angle: UInt32
            }
        }

        let body: LiveModels.StyleOnlyMessageBody?
        let textStyle: Self.TextStyle
        var preview: TSAttachmentMigration.OWSLinkPreview?
        let textForegroundColorHex: UInt32?
        let textBackgroundColorHex: UInt32?
        let rawBackground: Self.RawBackground

        enum CodingKeys: String, CodingKey {
            case body = "text"
            case textStyle
            case textForegroundColorHex
            case textBackgroundColorHex
            case rawBackground
            case preview
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            do {
                // Backwards compability; this used to contain just a raw string,
                // which we now interpret as a style-less string.
                if let rawText = try container.decodeIfPresent(String.self, forKey: .body) {
                    self.body = LiveModels.StyleOnlyMessageBody(plaintext: rawText)
                } else {
                    self.body = nil
                }
            } catch {
                self.body = try container.decodeIfPresent(LiveModels.StyleOnlyMessageBody.self, forKey: .body)
            }

            self.textStyle = try container.decode(Self.TextStyle.self, forKey: .textStyle)
            self.textForegroundColorHex = try container.decodeIfPresent(UInt32.self, forKey: .textForegroundColorHex)
            self.textBackgroundColorHex = try container.decodeIfPresent(UInt32.self, forKey: .textBackgroundColorHex)
            self.rawBackground = try container.decode(Self.RawBackground.self, forKey: .rawBackground)
            self.preview = try container.decodeIfPresent(TSAttachmentMigration.OWSLinkPreview.self, forKey: .preview)
        }
    }
}

extension TSAttachmentMigration.NSRangedValue: Codable where T: Codable {}
