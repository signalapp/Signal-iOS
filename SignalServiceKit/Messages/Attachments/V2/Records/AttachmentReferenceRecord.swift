//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension AttachmentReference {

    enum FetchableRecordColumnFilter {
        /// The provided owner did not match the record type; don't fetch from this record's table.
        case nonMatchingOwnerType
        /// Filter to rows where `ownerRowIdColumn` is NULL.
        case nullOwnerRowId
        /// Filter to rows where `ownerRowIdColumn` equals the provided value.
        case ownerRowId(Int64)
        /// Filter to rows where `ownerRowIdColumn` equals the provided value AND typeColumn equals the provided value.
        case ownerTypeAndRowId(rowId: Int64, type: Int, typeColumn: Column)
    }
}

internal protocol FetchableAttachmentReferenceRecord: Codable, PersistableRecord, FetchableRecord, Equatable, UInt64SafeRecord {

    static var ownerRowIdColumn: Column { get }

    static var idInOwnerColumn: Column? { get }

    static var attachmentRowIdColumn: Column { get }

    static var orderInOwnerKey: KeyPath<Self, UInt32?>? { get }

    /// Filters to apply when querying the table for rows matching the provided row id.
    /// If returns `nonMatchingOwnerType`, the record's table should not be queried at all.
    static func columnFilters(for ownerId: AttachmentReference.OwnerId) -> AttachmentReference.FetchableRecordColumnFilter

    func asReference() throws -> AttachmentReference
}

extension FetchableAttachmentReferenceRecord {
    static var orderInOwnerKey: KeyPath<Self, UInt32?>? { nil }
}

extension AttachmentReference {

    static var recordTypes: [any FetchableAttachmentReferenceRecord.Type] {
        return [
            MessageAttachmentReferenceRecord.self,
            StoryMessageAttachmentReferenceRecord.self,
            ThreadAttachmentReferenceRecord.self
        ]
    }

    public struct MessageAttachmentReferenceRecord: FetchableAttachmentReferenceRecord {

        let ownerType: UInt32
        var ownerRowId: Int64
        let attachmentRowId: Int64
        let receivedAtTimestamp: UInt64
        let contentType: UInt32?
        let renderingFlag: UInt32
        let idInMessage: String?
        let orderInMessage: UInt32?
        let threadRowId: Int64
        let caption: String?
        let sourceFilename: String?
        let sourceUnencryptedByteCount: UInt32?
        let sourceMediaHeightPixels: UInt32?
        let sourceMediaWidthPixels: UInt32?
        let stickerPackId: Data?
        let stickerId: UInt32?
        let isViewOnce: Bool
        var ownerIsPastEditRevision: Bool

        // MARK: - Coding Keys

        public enum CodingKeys: String, CodingKey {
            case ownerType
            case ownerRowId
            case attachmentRowId
            case receivedAtTimestamp
            case contentType
            case renderingFlag
            case idInMessage
            case orderInMessage
            case threadRowId
            case caption
            case sourceFilename
            case sourceUnencryptedByteCount
            case sourceMediaHeightPixels
            case sourceMediaWidthPixels
            case stickerPackId
            case stickerId
            case isViewOnce
            case ownerIsPastEditRevision
        }

        // MARK: - PersistableRecord

        public static let databaseTableName: String = "MessageAttachmentReference"

        // MARK: - UInt64SafeRecord

        public static var uint64Fields: [KeyPath<Self, UInt64>] { [\.receivedAtTimestamp] }

        public static var uint64OptionalFields: [KeyPath<Self, UInt64?>] { [] }

        // MARK: FetchableAttachmentReferenceRecord

        static var ownerRowIdColumn: Column { Column(CodingKeys.ownerRowId) }

        static var idInOwnerColumn: Column? { Column(CodingKeys.idInMessage) }

        static var attachmentRowIdColumn: Column { Column(CodingKeys.attachmentRowId) }

        static var orderInOwnerKey: KeyPath<Self, UInt32?>? { \.orderInMessage }

        static func columnFilters(for ownerId: AttachmentReference.OwnerId) -> FetchableRecordColumnFilter {
            func ownerTypeAndRowId(_ messageRowId: Int64, _ ownerType: MessageOwnerTypeRaw) -> FetchableRecordColumnFilter {
                return .ownerTypeAndRowId(rowId: messageRowId, type: ownerType.rawValue, typeColumn: Column(CodingKeys.ownerType))
            }

            switch ownerId {
            case .messageBodyAttachment(let messageRowId):
                return ownerTypeAndRowId(messageRowId, .bodyAttachment)
            case .messageOversizeText(let messageRowId):
                return ownerTypeAndRowId(messageRowId, .oversizeText)
            case .messageLinkPreview(let messageRowId):
                return ownerTypeAndRowId(messageRowId, .linkPreview)
            case .quotedReplyAttachment(let messageRowId):
                return ownerTypeAndRowId(messageRowId, .quotedReplyAttachment)
            case .messageSticker(let messageRowId):
                return ownerTypeAndRowId(messageRowId, .sticker)
            case .messageContactAvatar(let messageRowId):
                return ownerTypeAndRowId(messageRowId, .contactAvatar)
            case
                    .storyMessageMedia,
                    .storyMessageLinkPreview,
                    .threadWallpaperImage,
                    .globalThreadWallpaperImage:
                return .nonMatchingOwnerType
            }
        }

        func asReference() throws -> AttachmentReference {
            return try AttachmentReference(record: self)
        }

        // MARK: - Initializers

        internal init(
            ownerType: UInt32,
            ownerRowId: Int64,
            attachmentRowId: Int64,
            receivedAtTimestamp: UInt64,
            contentType: UInt32?,
            renderingFlag: UInt32,
            idInMessage: String?,
            orderInMessage: UInt32?,
            threadRowId: Int64,
            caption: String?,
            sourceFilename: String?,
            sourceUnencryptedByteCount: UInt32?,
            sourceMediaHeightPixels: UInt32?,
            sourceMediaWidthPixels: UInt32?,
            stickerPackId: Data?,
            stickerId: UInt32?,
            isViewOnce: Bool,
            ownerIsPastEditRevision: Bool
        ) {
            self.ownerType = ownerType
            self.ownerRowId = ownerRowId
            self.attachmentRowId = attachmentRowId
            self.receivedAtTimestamp = receivedAtTimestamp
            self.contentType = contentType
            self.renderingFlag = renderingFlag
            self.idInMessage = idInMessage
            self.orderInMessage = orderInMessage
            self.threadRowId = threadRowId
            self.caption = caption
            self.sourceFilename = sourceFilename
            self.sourceUnencryptedByteCount = sourceUnencryptedByteCount
            self.sourceMediaHeightPixels = sourceMediaHeightPixels
            self.sourceMediaWidthPixels = sourceMediaWidthPixels
            self.stickerPackId = stickerPackId
            self.stickerId = stickerId
            self.isViewOnce = isViewOnce
            self.ownerIsPastEditRevision = ownerIsPastEditRevision
        }

        internal init(
            attachmentReference: AttachmentReference,
            messageSource: AttachmentReference.Owner.MessageSource
        ) {
            self.init(
                attachmentRowId: attachmentReference.attachmentRowId,
                sourceFilename: attachmentReference.sourceFilename,
                sourceUnencryptedByteCount: attachmentReference.sourceUnencryptedByteCount,
                sourceMediaSizePixels: attachmentReference.sourceMediaSizePixels,
                messageSource: messageSource
            )
        }

        internal init(
            attachmentRowId: Attachment.IDType,
            sourceFilename: String?,
            sourceUnencryptedByteCount: UInt32?,
            sourceMediaSizePixels: CGSize?,
            messageSource: AttachmentReference.Owner.MessageSource
        ) {
            self.ownerType = UInt32(messageSource.rawMessageOwnerType.rawValue)
            self.attachmentRowId = attachmentRowId
            self.sourceFilename = sourceFilename
            self.sourceUnencryptedByteCount = sourceUnencryptedByteCount
            if let sourceMediaSizePixels = sourceMediaSizePixels {
                self.sourceMediaHeightPixels = UInt32(exactly: sourceMediaSizePixels.height.rounded())
                self.sourceMediaWidthPixels = UInt32(exactly: sourceMediaSizePixels.width.rounded())
            } else {
                self.sourceMediaHeightPixels = nil
                self.sourceMediaWidthPixels = nil
            }

            switch messageSource {
            case .bodyAttachment(let metadata):
                self.ownerRowId = metadata.messageRowId
                self.receivedAtTimestamp = metadata.receivedAtTimestamp
                self.contentType = metadata.contentType.map { UInt32($0.rawValue) }
                self.renderingFlag = UInt32(metadata.renderingFlag.rawValue)
                self.idInMessage = metadata.idInOwner?.uuidString
                self.orderInMessage = metadata.orderInOwner
                self.threadRowId = metadata.threadRowId
                self.caption = metadata.caption
                self.stickerPackId = nil
                self.stickerId = nil
                self.isViewOnce = metadata.isViewOnce
                self.ownerIsPastEditRevision = metadata.isPastEditRevision
            case .oversizeText(let metadata):
                self.ownerRowId = metadata.messageRowId
                self.receivedAtTimestamp = metadata.receivedAtTimestamp
                self.contentType = metadata.contentType.map { UInt32($0.rawValue) }
                self.renderingFlag = UInt32(AttachmentReference.RenderingFlag.default.rawValue)
                self.idInMessage = nil
                self.orderInMessage = nil
                self.threadRowId = metadata.threadRowId
                self.caption = nil
                self.stickerPackId = nil
                self.stickerId = nil
                // Oversize text cannot be view once
                self.isViewOnce = false
                self.ownerIsPastEditRevision = metadata.isPastEditRevision
            case .linkPreview(let metadata):
                self.ownerRowId = metadata.messageRowId
                self.receivedAtTimestamp = metadata.receivedAtTimestamp
                self.contentType = metadata.contentType.map { UInt32($0.rawValue) }
                self.renderingFlag = UInt32(AttachmentReference.RenderingFlag.default.rawValue)
                self.idInMessage = nil
                self.orderInMessage = nil
                self.threadRowId = metadata.threadRowId
                self.caption = nil
                self.stickerPackId = nil
                self.stickerId = nil
                // Link previews cannot be view once
                self.isViewOnce = false
                self.ownerIsPastEditRevision = metadata.isPastEditRevision
            case .quotedReply(let metadata):
                self.ownerRowId = metadata.messageRowId
                self.receivedAtTimestamp = metadata.receivedAtTimestamp
                self.contentType = metadata.contentType.map { UInt32($0.rawValue) }
                self.renderingFlag = UInt32(metadata.renderingFlag.rawValue)
                self.idInMessage = nil
                self.orderInMessage = nil
                self.threadRowId = metadata.threadRowId
                self.caption = nil
                self.stickerPackId = nil
                self.stickerId = nil
                // Quoted reply thumbnails cannot be view once
                self.isViewOnce = false
                self.ownerIsPastEditRevision = metadata.isPastEditRevision
            case .sticker(let metadata):
                self.ownerRowId = metadata.messageRowId
                self.receivedAtTimestamp = metadata.receivedAtTimestamp
                self.contentType = metadata.contentType.map { UInt32($0.rawValue) }
                self.renderingFlag = UInt32(AttachmentReference.RenderingFlag.default.rawValue)
                self.idInMessage = nil
                self.orderInMessage = nil
                self.threadRowId = metadata.threadRowId
                self.caption = nil
                self.stickerPackId = metadata.stickerPackId
                self.stickerId = metadata.stickerId
                // Stickers cannot be view once
                self.isViewOnce = false
                self.ownerIsPastEditRevision = metadata.isPastEditRevision
            case .contactAvatar(let metadata):
                self.ownerRowId = metadata.messageRowId
                self.receivedAtTimestamp = metadata.receivedAtTimestamp
                self.contentType = metadata.contentType.map { UInt32($0.rawValue) }
                self.renderingFlag = UInt32(AttachmentReference.RenderingFlag.default.rawValue)
                self.idInMessage = nil
                self.orderInMessage = nil
                self.threadRowId = metadata.threadRowId
                self.caption = nil
                self.stickerPackId = nil
                self.stickerId = nil
                // Contact avatars cannot be view once
                self.isViewOnce = false
                self.ownerIsPastEditRevision = metadata.isPastEditRevision
            }
        }
    }

    public struct StoryMessageAttachmentReferenceRecord: FetchableAttachmentReferenceRecord {

        let ownerType: UInt32
        let ownerRowId: Int64
        let attachmentRowId: Int64
        let shouldLoop: Bool
        let caption: String?
        let captionBodyRanges: Data?
        let sourceFilename: String?
        let sourceUnencryptedByteCount: UInt32?
        let sourceMediaHeightPixels: UInt32?
        let sourceMediaWidthPixels: UInt32?

        // MARK: - Coding Keys

        public enum CodingKeys: String, CodingKey {
            case ownerType
            case ownerRowId
            case attachmentRowId
            case shouldLoop
            case caption
            case captionBodyRanges
            case sourceFilename
            case sourceUnencryptedByteCount
            case sourceMediaHeightPixels
            case sourceMediaWidthPixels
        }

        // MARK: - PersistableRecord

        public static let databaseTableName: String = "StoryMessageAttachmentReference"

        // MARK: - UInt64SafeRecord

        public static var uint64Fields: [KeyPath<Self, UInt64>] { [] }

        public static var uint64OptionalFields: [KeyPath<Self, UInt64?>] { [] }

        // MARK: FetchableAttachmentReferenceRecord

        static var ownerRowIdColumn: Column { Column(CodingKeys.ownerRowId) }

        static var idInOwnerColumn: Column? { nil }

        static var attachmentRowIdColumn: Column { Column(CodingKeys.attachmentRowId) }

        static func columnFilters(for ownerId: AttachmentReference.OwnerId) -> FetchableRecordColumnFilter {
            func ownerTypeAndRowId(_ storyMessageRowId: Int64, _ ownerType: StoryMessageOwnerTypeRaw) -> FetchableRecordColumnFilter {
                return .ownerTypeAndRowId(rowId: storyMessageRowId, type: ownerType.rawValue, typeColumn: Column(CodingKeys.ownerType))
            }

            switch ownerId {
            case .storyMessageMedia(let storyMessageRowId):
                return ownerTypeAndRowId(storyMessageRowId, .media)
            case .storyMessageLinkPreview(let storyMessageRowId):
                return ownerTypeAndRowId(storyMessageRowId, .linkPreview)
            case
                    .messageBodyAttachment,
                    .messageOversizeText,
                    .messageLinkPreview,
                    .quotedReplyAttachment,
                    .messageSticker,
                    .messageContactAvatar,
                    .threadWallpaperImage,
                    .globalThreadWallpaperImage:
                return .nonMatchingOwnerType
            }
        }

        func asReference() throws -> AttachmentReference {
            return try AttachmentReference(record: self)
        }

        // MARK: - Initializers

        internal init(
            ownerType: UInt32,
            ownerRowId: Int64,
            attachmentRowId: Int64,
            shouldLoop: Bool,
            caption: String?,
            captionBodyRanges: Data?,
            sourceFilename: String?,
            sourceUnencryptedByteCount: UInt32?,
            sourceMediaHeightPixels: UInt32?,
            sourceMediaWidthPixels: UInt32?
        ) {
            self.ownerType = ownerType
            self.ownerRowId = ownerRowId
            self.attachmentRowId = attachmentRowId
            self.shouldLoop = shouldLoop
            self.caption = caption
            self.captionBodyRanges = captionBodyRanges
            self.sourceFilename = sourceFilename
            self.sourceUnencryptedByteCount = sourceUnencryptedByteCount
            self.sourceMediaHeightPixels = sourceMediaHeightPixels
            self.sourceMediaWidthPixels = sourceMediaWidthPixels
        }

        internal init(
            attachmentReference: AttachmentReference,
            storyMessageSource: AttachmentReference.Owner.StoryMessageSource
        ) throws {
            try self.init(
                attachmentRowId: attachmentReference.attachmentRowId,
                sourceFilename: attachmentReference.sourceFilename,
                sourceUnencryptedByteCount: attachmentReference.sourceUnencryptedByteCount,
                sourceMediaSizePixels: attachmentReference.sourceMediaSizePixels,
                storyMessageSource: storyMessageSource
            )
        }

        internal init(
            attachmentRowId: Attachment.IDType,
            sourceFilename: String?,
            sourceUnencryptedByteCount: UInt32?,
            sourceMediaSizePixels: CGSize?,
            storyMessageSource: AttachmentReference.Owner.StoryMessageSource
        ) throws {
            self.ownerType = UInt32(storyMessageSource.rawStoryMessageOwnerType.rawValue)
            self.attachmentRowId = attachmentRowId
            self.sourceFilename = sourceFilename
            self.sourceUnencryptedByteCount = sourceUnencryptedByteCount
            if let sourceMediaSizePixels = sourceMediaSizePixels {
                self.sourceMediaHeightPixels = UInt32(exactly: sourceMediaSizePixels.height.rounded())
                self.sourceMediaWidthPixels = UInt32(exactly: sourceMediaSizePixels.width.rounded())
            } else {
                self.sourceMediaHeightPixels = nil
                self.sourceMediaWidthPixels = nil
            }

            switch storyMessageSource {
            case .media(let metadata):
                self.shouldLoop = metadata.shouldLoop
                self.ownerRowId = metadata.storyMessageRowId

                if let caption = metadata.caption {
                    self.caption = caption.text
                    let styles: [NSRangedValue<MessageBodyRanges.CollapsedStyle>] = caption.collapsedStyles
                    self.captionBodyRanges = try JSONEncoder().encode(styles)
                } else {
                    self.caption = nil
                    self.captionBodyRanges = nil
                }
            case .textStoryLinkPreview(let metadata):
                self.ownerRowId = metadata.storyMessageRowId
                self.shouldLoop = false
                self.caption = nil
                self.captionBodyRanges = nil
            }
        }
    }

    public struct ThreadAttachmentReferenceRecord: FetchableAttachmentReferenceRecord {

        var ownerRowId: Int64?
        let attachmentRowId: Int64
        let creationTimestamp: UInt64

        // MARK: - Coding Keys

        public enum CodingKeys: String, CodingKey {
            case ownerRowId
            case attachmentRowId
            case creationTimestamp
        }

        // MARK: - PersistableRecord

        public static let databaseTableName: String = "ThreadAttachmentReference"

        // MARK: - UInt64SafeRecord

        public static var uint64Fields: [KeyPath<Self, UInt64>] { [\.creationTimestamp] }

        public static var uint64OptionalFields: [KeyPath<Self, UInt64?>] { [] }

        // MARK: FetchableAttachmentReferenceRecord

        static var ownerRowIdColumn: Column { Column(CodingKeys.ownerRowId) }

        static var idInOwnerColumn: Column? { nil }

        static var attachmentRowIdColumn: Column { Column(CodingKeys.attachmentRowId) }

        static func columnFilters(for ownerId: AttachmentReference.OwnerId) -> FetchableRecordColumnFilter {

            switch ownerId {
            case .threadWallpaperImage(let threadRowId):
                return .ownerRowId(threadRowId)
            case .globalThreadWallpaperImage:
                return .nullOwnerRowId
            case
                    .messageBodyAttachment,
                    .messageOversizeText,
                    .messageLinkPreview,
                    .quotedReplyAttachment,
                    .messageSticker,
                    .messageContactAvatar,
                    .storyMessageMedia,
                    .storyMessageLinkPreview:
                return .nonMatchingOwnerType
            }
        }

        func asReference() throws -> AttachmentReference {
            return try AttachmentReference(record: self)
        }

        // MARK: - Initializers

        internal init(
            ownerRowId: Int64?,
            attachmentRowId: Int64,
            creationTimestamp: UInt64
        ) {
            self.ownerRowId = ownerRowId
            self.attachmentRowId = attachmentRowId
            self.creationTimestamp = creationTimestamp
        }

        internal init(
            attachmentReference: AttachmentReference,
            threadSource: AttachmentReference.Owner.ThreadSource
        ) {
            self.init(
                attachmentRowId: attachmentReference.attachmentRowId,
                threadSource: threadSource
            )
        }

        internal init(
            attachmentRowId: Attachment.IDType,
            threadSource: AttachmentReference.Owner.ThreadSource
        ) {
            self.attachmentRowId = attachmentRowId
            switch threadSource {
            case .threadWallpaperImage(let metadata):
                self.ownerRowId = metadata.threadRowId
                self.creationTimestamp = metadata.creationTimestamp
            case .globalThreadWallpaperImage(let creationTimestamp):
                self.ownerRowId = nil
                self.creationTimestamp = creationTimestamp
            }
        }
    }
}
