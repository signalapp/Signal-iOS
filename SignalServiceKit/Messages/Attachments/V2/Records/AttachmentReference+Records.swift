//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import GRDB

extension AttachmentReference {

    public struct MessageAttachmentReferenceRecord: Codable, PersistableRecord, FetchableRecord, Equatable {
        public enum OwnerType: UInt32, CaseIterable {
            case bodyAttachment = 0
            case oversizeText = 1
            case linkPreview = 2
            case quotedReplyAttachment = 3
            case sticker = 4
            case contactAvatar = 5
        }

        let ownerTypeRaw: UInt32
        var ownerRowId: Int64
        let attachmentRowId: Int64
        @DBUInt64
        var receivedAtTimestamp: UInt64
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
            case ownerTypeRaw = "ownerType"
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

        // MARK: - Columns

        enum Columns {
            static let ownerType = Column(CodingKeys.ownerTypeRaw)
            static let ownerRowId = Column(CodingKeys.ownerRowId)
            static let orderInMessage = Column(CodingKeys.orderInMessage)
            static let attachmentRowId = Column(CodingKeys.attachmentRowId)
            static let idInMessage = Column(CodingKeys.idInMessage)
        }

        // MARK: - PersistableRecord

        public static let databaseTableName: String = "MessageAttachmentReference"

        // MARK: - Initializers

        init(
            attachmentReference: AttachmentReference,
            messageSource: AttachmentReference.Owner.MessageSource,
        ) {
            self.init(
                attachmentRowId: attachmentReference.attachmentRowId,
                sourceFilename: attachmentReference.sourceFilename,
                sourceUnencryptedByteCount: attachmentReference.sourceUnencryptedByteCount,
                sourceMediaSizePixels: attachmentReference.sourceMediaSizePixels,
                messageSource: messageSource,
            )
        }

        init(
            attachmentRowId: Attachment.IDType,
            sourceFilename: String?,
            sourceUnencryptedByteCount: UInt32?,
            sourceMediaSizePixels: CGSize?,
            messageSource: AttachmentReference.Owner.MessageSource,
        ) {
            self.ownerTypeRaw = messageSource.persistedOwnerType.rawValue
            self.attachmentRowId = attachmentRowId
            self.sourceFilename = sourceFilename
            self.sourceUnencryptedByteCount = sourceUnencryptedByteCount
            if let sourceMediaSizePixels {
                self.sourceMediaHeightPixels = UInt32(exactly: sourceMediaSizePixels.height.rounded())
                self.sourceMediaWidthPixels = UInt32(exactly: sourceMediaSizePixels.width.rounded())
            } else {
                self.sourceMediaHeightPixels = nil
                self.sourceMediaWidthPixels = nil
            }

            switch messageSource {
            case .bodyAttachment(let metadata):
                self.ownerRowId = metadata.messageRowId
                self._receivedAtTimestamp = DBUInt64(wrappedValue: metadata.receivedAtTimestamp)
                self.contentType = metadata.contentType.map { UInt32($0.rawValue) }
                self.renderingFlag = UInt32(metadata.renderingFlag.rawValue)
                self.idInMessage = metadata.idInOwner?.uuidString
                self.orderInMessage = metadata.orderInMessage
                self.threadRowId = metadata.threadRowId
                self.caption = metadata.caption
                self.stickerPackId = nil
                self.stickerId = nil
                self.isViewOnce = metadata.isViewOnce
                self.ownerIsPastEditRevision = metadata.isPastEditRevision
            case .oversizeText(let metadata):
                self.ownerRowId = metadata.messageRowId
                self._receivedAtTimestamp = DBUInt64(wrappedValue: metadata.receivedAtTimestamp)
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
                self._receivedAtTimestamp = DBUInt64(wrappedValue: metadata.receivedAtTimestamp)
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
                self._receivedAtTimestamp = DBUInt64(wrappedValue: metadata.receivedAtTimestamp)
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
                self._receivedAtTimestamp = DBUInt64(wrappedValue: metadata.receivedAtTimestamp)
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
                self._receivedAtTimestamp = DBUInt64(wrappedValue: metadata.receivedAtTimestamp)
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

    public struct StoryMessageAttachmentReferenceRecord: Codable, PersistableRecord, FetchableRecord, Equatable {
        public enum OwnerType: UInt32, CaseIterable {
            case media = 0
            case linkPreview = 1
        }

        let ownerTypeRaw: UInt32
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
            case ownerTypeRaw = "ownerType"
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

        // MARK: - Columns

        enum Columns {
            static let ownerType = Column(CodingKeys.ownerTypeRaw)
            static let ownerRowId = Column(CodingKeys.ownerRowId)
            static let attachmentRowId = Column(CodingKeys.attachmentRowId)
        }

        // MARK: - PersistableRecord

        public static let databaseTableName: String = "StoryMessageAttachmentReference"

        // MARK: - Initializers

        init(
            attachmentReference: AttachmentReference,
            storyMessageSource: AttachmentReference.Owner.StoryMessageSource,
        ) throws {
            try self.init(
                attachmentRowId: attachmentReference.attachmentRowId,
                sourceFilename: attachmentReference.sourceFilename,
                sourceUnencryptedByteCount: attachmentReference.sourceUnencryptedByteCount,
                sourceMediaSizePixels: attachmentReference.sourceMediaSizePixels,
                storyMessageSource: storyMessageSource,
            )
        }

        init(
            attachmentRowId: Attachment.IDType,
            sourceFilename: String?,
            sourceUnencryptedByteCount: UInt32?,
            sourceMediaSizePixels: CGSize?,
            storyMessageSource: AttachmentReference.Owner.StoryMessageSource,
        ) throws {
            self.ownerTypeRaw = storyMessageSource.persistedOwnerType.rawValue
            self.attachmentRowId = attachmentRowId
            self.sourceFilename = sourceFilename
            self.sourceUnencryptedByteCount = sourceUnencryptedByteCount
            if let sourceMediaSizePixels {
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

    public struct ThreadAttachmentReferenceRecord: Codable, PersistableRecord, FetchableRecord, Equatable {
        var ownerRowId: Int64?
        let attachmentRowId: Int64
        @DBUInt64
        var creationTimestamp: UInt64

        // MARK: - Coding Keys

        public enum CodingKeys: String, CodingKey {
            case ownerRowId
            case attachmentRowId
            case creationTimestamp
        }

        // MARK: - Columns

        enum Columns {
            static let ownerRowId = Column(CodingKeys.ownerRowId)
            static let attachmentRowId = Column(CodingKeys.attachmentRowId)
        }

        // MARK: - PersistableRecord

        public static let databaseTableName: String = "ThreadAttachmentReference"

        // MARK: - Initializers

        init(
            attachmentRowId: Attachment.IDType,
            threadSource: AttachmentReference.Owner.ThreadSource,
        ) {
            self.attachmentRowId = attachmentRowId
            switch threadSource {
            case .threadWallpaperImage(let metadata):
                self.ownerRowId = metadata.threadRowId
                self._creationTimestamp = DBUInt64(wrappedValue: metadata.creationTimestamp)
            case .globalThreadWallpaperImage(let creationTimestamp):
                self.ownerRowId = nil
                self._creationTimestamp = DBUInt64(wrappedValue: creationTimestamp)
            }
        }
    }
}
