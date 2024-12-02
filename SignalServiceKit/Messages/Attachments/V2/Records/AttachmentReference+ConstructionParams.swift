//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

extension AttachmentReference {

    /// A builder for the "owner" metadata of an attachment, with the bare minimum per-type
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
        case messageOversizeText(MessageAttachmentBuilder)
        case messageLinkPreview(MessageAttachmentBuilder)
        /// Note that the row id is for the parent message containing the quoted reply,
        /// not the original message being quoted.
        case quotedReplyAttachment(MessageAttachmentBuilder)
        case messageSticker(MessageStickerBuilder)
        case messageContactAvatar(MessageAttachmentBuilder)
        case storyMessageMedia(StoryMediaBuilder)
        case storyMessageLinkPreview(storyMessageRowId: Int64)
        case threadWallpaperImage(threadRowId: Int64)
        case globalThreadWallpaperImage

        /// A known identifier for this attachment within the owner, shared
        /// with linked devices and other users.
        ///
        /// - Note
        /// This is only relevant for message body attachments.
        public enum KnownIdInOwner {
            /// No known identifier is available and a new random one will be assigned.
            /// This should be preferred for most callers, especially local outgoing attachments.
            case none
            /// An identifier is affirmatively known to be missing.
            case knownNil
            /// A known identifier is present.
            case known(UUID)
        }

        /// Build the owner of this attachment reference.
        ///
        /// - Parameter knowIdInOwner
        /// A known identifier for this attachment within the owner. Callers
        /// should pass ``KnownIdInOwner/none`` if no identifier information is
        /// available. Only relevant for message body attachments!
        /// - Parameter caption
        /// A caption for a message body attachment. This field is no longer
        /// used by new attachments; however, it might be present when dealing
        /// with legacy data.
        public func build(
            orderInOwner: UInt32?,
            knownIdInOwner: KnownIdInOwner,
            renderingFlag: AttachmentReference.RenderingFlag,
            contentType: AttachmentReference.ContentType?,
            caption: String? = nil
        ) throws -> AttachmentReference.Owner {
            switch self {
            case .messageBodyAttachment(let metadata):
                // idInOwner is optional; old clients may not send it.
                guard let orderInOwner else {
                    throw OWSAssertionError("OrderInOwner must be provided for body attachments.")
                }
                return .message(.bodyAttachment(.init(
                    messageRowId: metadata.messageRowId,
                    receivedAtTimestamp: metadata.receivedAtTimestamp,
                    threadRowId: metadata.threadRowId,
                    contentType: contentType,
                    isPastEditRevision: metadata.isPastEditRevision,
                    // We ignore captions in modern instances.
                    caption: caption,
                    renderingFlag: renderingFlag,
                    orderInOwner: orderInOwner,
                    idInOwner: { () -> UUID? in
                        switch knownIdInOwner {
                        case .none: return UUID()
                        case .knownNil: return nil
                        case .known(let knownValue): return knownValue
                        }
                    }(),
                    isViewOnce: metadata.isViewOnce
                )))
            case .messageOversizeText(let metadata):
                return .message(.oversizeText(.init(
                    messageRowId: metadata.messageRowId,
                    receivedAtTimestamp: metadata.receivedAtTimestamp,
                    threadRowId: metadata.threadRowId,
                    contentType: contentType,
                    isPastEditRevision: metadata.isPastEditRevision
                )))
            case .messageLinkPreview(let metadata):
                return .message(.linkPreview(.init(
                    messageRowId: metadata.messageRowId,
                    receivedAtTimestamp: metadata.receivedAtTimestamp,
                    threadRowId: metadata.threadRowId,
                    contentType: contentType,
                    isPastEditRevision: metadata.isPastEditRevision
                )))
            case .quotedReplyAttachment(let metadata):
                return .message(.quotedReply(.init(
                    messageRowId: metadata.messageRowId,
                    receivedAtTimestamp: metadata.receivedAtTimestamp,
                    threadRowId: metadata.threadRowId,
                    contentType: contentType,
                    isPastEditRevision: metadata.isPastEditRevision,
                    renderingFlag: renderingFlag
                )))
            case .messageSticker(let metadata):
                return .message(.sticker(.init(
                    messageRowId: metadata.messageRowId,
                    receivedAtTimestamp: metadata.receivedAtTimestamp,
                    threadRowId: metadata.threadRowId,
                    contentType: contentType,
                    isPastEditRevision: metadata.isPastEditRevision,
                    stickerPackId: metadata.stickerPackId,
                    stickerId: metadata.stickerId
                )))
            case .messageContactAvatar(let metadata):
                return .message(.contactAvatar(.init(
                    messageRowId: metadata.messageRowId,
                    receivedAtTimestamp: metadata.receivedAtTimestamp,
                    threadRowId: metadata.threadRowId,
                    contentType: contentType,
                    isPastEditRevision: metadata.isPastEditRevision
                )))
            case .storyMessageMedia(let metadata):
                return .storyMessage(.media(.init(
                    storyMessageRowId: metadata.storyMessageRowId,
                    caption: metadata.caption,
                    shouldLoop: renderingFlag == .shouldLoop
                )))
            case .storyMessageLinkPreview(let storyMessageRowId):
                return .storyMessage(.textStoryLinkPreview(.init(storyMessageRowId: storyMessageRowId)))
            case .threadWallpaperImage(let threadRowId):
                return .thread(.threadWallpaperImage(.init(
                    threadRowId: threadRowId,
                    creationTimestamp: Date().ows_millisecondsSince1970
                )))
            case .globalThreadWallpaperImage:
                return .thread(.globalThreadWallpaperImage(creationTimestamp: Date().ows_millisecondsSince1970))
            }
        }

        public struct MessageAttachmentBuilder: Equatable {
            public let messageRowId: Int64
            public let receivedAtTimestamp: UInt64
            public let threadRowId: Int64
            /// True if the owning message's ``TSEditState`` is `pastRevision`.
            public let isPastEditRevision: Bool

            public init(
                messageRowId: Int64,
                receivedAtTimestamp: UInt64,
                threadRowId: Int64,
                isPastEditRevision: Bool
            ) {
                self.messageRowId = messageRowId
                self.receivedAtTimestamp = receivedAtTimestamp
                self.threadRowId = threadRowId
                self.isPastEditRevision = isPastEditRevision
            }
        }

        public struct MessageBodyAttachmentBuilder: Equatable {
            public let messageRowId: Int64
            public let receivedAtTimestamp: UInt64
            public let threadRowId: Int64
            public let isViewOnce: Bool
            /// True if the owning message's ``TSEditState`` is `pastRevision`.
            public let isPastEditRevision: Bool

            public init(
                messageRowId: Int64,
                receivedAtTimestamp: UInt64,
                threadRowId: Int64,
                isViewOnce: Bool,
                isPastEditRevision: Bool
            ) {
                self.messageRowId = messageRowId
                self.receivedAtTimestamp = receivedAtTimestamp
                self.threadRowId = threadRowId
                self.isViewOnce = isViewOnce
                self.isPastEditRevision = isPastEditRevision
            }
        }

        public struct MessageStickerBuilder: Equatable {
            public let messageRowId: Int64
            public let receivedAtTimestamp: UInt64
            public let threadRowId: Int64
            /// True if the owning message's ``TSEditState`` is `pastRevision`.
            public let isPastEditRevision: Bool
            public let stickerPackId: Data
            public let stickerId: UInt32

            public init(
                messageRowId: Int64,
                receivedAtTimestamp: UInt64,
                threadRowId: Int64,
                isPastEditRevision: Bool,
                stickerPackId: Data,
                stickerId: UInt32
            ) {
                self.messageRowId = messageRowId
                self.receivedAtTimestamp = receivedAtTimestamp
                self.threadRowId = threadRowId
                self.isPastEditRevision = isPastEditRevision
                self.stickerPackId = stickerPackId
                self.stickerId = stickerId
            }
        }

        public struct StoryMediaBuilder: Equatable {
            public let storyMessageRowId: Int64
            public let caption: StyleOnlyMessageBody?

            public init(
                storyMessageRowId: Int64,
                caption: StyleOnlyMessageBody?
            ) {
                self.storyMessageRowId = storyMessageRowId
                self.caption = caption
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

        internal func buildRecord(attachmentRowId: Attachment.IDType) throws -> any FetchableAttachmentReferenceRecord {
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
        case .messageOversizeText(let builder):
            return .messageOversizeText(messageRowId: builder.messageRowId)
        case .messageLinkPreview(let builder):
            return .messageLinkPreview(messageRowId: builder.messageRowId)
        case .quotedReplyAttachment(let builder):
            return .quotedReplyAttachment(messageRowId: builder.messageRowId)
        case .messageSticker(let stickerOwnerBuilder):
            return .messageSticker(messageRowId: stickerOwnerBuilder.messageRowId)
        case .messageContactAvatar(let builder):
            return .messageContactAvatar(messageRowId: builder.messageRowId)
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
