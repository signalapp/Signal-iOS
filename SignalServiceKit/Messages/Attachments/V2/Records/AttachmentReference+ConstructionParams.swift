//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension AttachmentReference {

    /// A builder for the "owner" metadata of the attachment, with the bare minimum per-type
    /// metadata required for construction.
    ///
    /// This type is used by external constructors to indicate what _kind_ of owner they want
    /// separately from the sources of other fields. For example; I might have a proto representing
    /// an attachment pointer, and I want to specify pointer + an owner of type .messageBodyAttachment
    /// but AttachmentReference.Owner has fields already on the pointer proto.
    ///
    /// This type is just those fields that would not be on the source proto (or stream, or whatever)
    /// but must instead be uniquely specified per type.
    public enum OwnerBuilder: Equatable {
        case messageBodyAttachment(MessageBodyAttachmentBuilder)

        case messageOversizeText(messageRowId: Int64)
        case messageLinkPreview(messageRowId: Int64)
        /// Note that the row id is for the parent message containing the quoted reply,
        /// not the original message being quoted.
        case quotedReplyAttachment(MessageQuotedReplyAttachmentBuilder)
        case messageSticker(MessageStickerBuilder)
        case messageContactAvatar(messageRowId: Int64)
        case storyMessageMedia(StoryMediaBuilder)
        case storyMessageLinkPreview(storyMessageRowId: Int64)
        case threadWallpaperImage(threadRowId: Int64)
        case globalThreadWallpaperImage

        public struct MessageBodyAttachmentBuilder: Equatable {
            public let messageRowId: Int64
            public let renderingFlag: AttachmentReference.RenderingFlag

            /// Note: index/orderInOwner is inferred from the order of the provided array at creation time.

            /// Note: at time of writing message captions are unused; not taken as input here.

            public init(
                messageRowId: Int64,
                renderingFlag: AttachmentReference.RenderingFlag
            ) {
                self.messageRowId = messageRowId
                self.renderingFlag = renderingFlag
            }
        }

        public struct MessageQuotedReplyAttachmentBuilder: Equatable {
            public let messageRowId: Int64
            public let renderingFlag: AttachmentReference.RenderingFlag

            public init(
                messageRowId: Int64,
                renderingFlag: AttachmentReference.RenderingFlag
            ) {
                self.messageRowId = messageRowId
                self.renderingFlag = renderingFlag
            }
        }

        public struct MessageStickerBuilder: Equatable {
            public let messageRowId: Int64
            public let stickerPackId: Data
            public let stickerId: UInt32

            public init(
                messageRowId: Int64,
                stickerPackId: Data,
                stickerId: UInt32
            ) {
                self.messageRowId = messageRowId
                self.stickerPackId = stickerPackId
                self.stickerId = stickerId
            }
        }

        public struct StoryMediaBuilder: Equatable {
            public let storyMessageRowId: Int64
            public let caption: StyleOnlyMessageBody?
            public let shouldLoop: Bool

            public init(
                storyMessageRowId: Int64,
                caption: StyleOnlyMessageBody?,
                shouldLoop: Bool
            ) {
                self.storyMessageRowId = storyMessageRowId
                self.caption = caption
                self.shouldLoop = shouldLoop
            }
        }
    }

    /// Collection of parameters for building AttachmentReferences.
    ///
    /// Identical to ``AttachmentReference`` except it doesn't have the attachment row id.
    ///
    /// Callers construct Attachments and their references together in one shot, so at the time they do so
    /// they don't yet have an inserted Attachment with an assigned sqlite row id, and can't construct
    /// an AttachmentReference as a result.
    /// Instead they provide one of these, from which we can create an AttachmentReference record for insertion,
    /// and afterwards get back the fully fledged AttachmentReference with id included.
    public struct ConstructionParams {
        public let owner: Owner
        public let sourceFilename: String?
        public let sourceUnencryptedByteCount: UInt32?
        public let sourceMediaSizePixels: CGSize?

        public init(
            owner: Owner,
            sourceFilename: String?,
            sourceUnencryptedByteCount: UInt32?,
            sourceMediaSizePixels: CGSize?
        ) {
            self.owner = owner
            self.sourceFilename = sourceFilename
            self.sourceUnencryptedByteCount = sourceUnencryptedByteCount
            self.sourceMediaSizePixels = sourceMediaSizePixels
        }

        internal func buildRecord(attachmentRowId: Attachment.IDType) throws -> any PersistableRecord {
            switch owner {
            case .message(let messageSource):
                return MessageAttachmentReferenceRecord(
                    attachmentRowId: attachmentRowId,
                    sourceFilename: sourceFilename,
                    sourceUnencryptedByteCount: sourceUnencryptedByteCount,
                    sourceMediaSizePixels: sourceMediaSizePixels,
                    messageSource: messageSource
                )
            case .storyMessage(let storyMessageSource):
                return try StoryMessageAttachmentReferenceRecord(
                    attachmentRowId: attachmentRowId,
                    sourceFilename: sourceFilename,
                    sourceUnencryptedByteCount: sourceUnencryptedByteCount,
                    sourceMediaSizePixels: sourceMediaSizePixels,
                    storyMessageSource: storyMessageSource
                )
            case .thread(let threadSource):
                return ThreadAttachmentReferenceRecord(
                    attachmentRowId: attachmentRowId,
                    threadSource: threadSource
                )
            }
        }
    }
}

extension AttachmentReference.OwnerBuilder {

    internal var id: AttachmentReference.OwnerId {
        switch self {
        case .messageBodyAttachment(let bodyOwnerBuilder):
            return .messageBodyAttachment(messageRowId: bodyOwnerBuilder.messageRowId)
        case .messageOversizeText(let messageRowId):
            return .messageOversizeText(messageRowId: messageRowId)
        case .messageLinkPreview(let messageRowId):
            return .messageLinkPreview(messageRowId: messageRowId)
        case .quotedReplyAttachment(let builder):
            return .quotedReplyAttachment(messageRowId: builder.messageRowId)
        case .messageSticker(let stickerOwnerBuilder):
            return .messageSticker(messageRowId: stickerOwnerBuilder.messageRowId)
        case .messageContactAvatar(let messageRowId):
            return .messageContactAvatar(messageRowId: messageRowId)
        case .storyMessageMedia(let mediaOwnerBuilder):
            return .storyMessageMedia(storyMessageRowId: mediaOwnerBuilder.storyMessageRowId)
        case .storyMessageLinkPreview(let storyMessageRowId):
            return .storyMessageLinkPreview(storyMessageRowId: storyMessageRowId)
        case .threadWallpaperImage(let threadRowId):
            return .threadWallpaperImage(threadRowId: threadRowId)
        case .globalThreadWallpaperImage:
            return .globalThreadWallpaperImage
        }
    }
}
