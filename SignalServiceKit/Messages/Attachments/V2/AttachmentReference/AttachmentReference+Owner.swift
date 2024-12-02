//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AttachmentReference {

    /// What type of  message "owner" this is, as stored in the sql table column.
    public enum MessageOwnerTypeRaw: Int, Codable, CaseIterable {
        case bodyAttachment = 0
        case oversizeText = 1
        case linkPreview = 2
        case quotedReplyAttachment = 3
        case sticker = 4
        case contactAvatar = 5
    }

    /// What type of  message "owner" this is, as stored in the sql table column.
    public enum StoryMessageOwnerTypeRaw: Int, Codable, CaseIterable {
        case media = 0
        case linkPreview = 1
    }

    /// What "owns" this attachment, as stored in the various sql table columns.
    public enum OwnerId: Hashable, Equatable {
        case messageBodyAttachment(messageRowId: Int64)
        case messageOversizeText(messageRowId: Int64)
        case messageLinkPreview(messageRowId: Int64)
        /// Note that the row id is for the parent message containing the quoted reply,
        /// not the original message being quoted.
        case quotedReplyAttachment(messageRowId: Int64)
        case messageSticker(messageRowId: Int64)
        case messageContactAvatar(messageRowId: Int64)
        case storyMessageMedia(storyMessageRowId: Int64)
        case storyMessageLinkPreview(storyMessageRowId: Int64)
        case threadWallpaperImage(threadRowId: Int64)
        /// The global default thread wallpaper; a single global owner.
        /// Has no associated owner in any other table; managed manually.
        case globalThreadWallpaperImage
    }

    /// A more friendly in-memory representation of the "owner" of the attachment
    /// with any associated metadata.
    public enum Owner {
        case message(MessageSource)
        case storyMessage(StoryMessageSource)
        case thread(ThreadSource)

        // MARK: - Message

        public enum MessageSource {
            case bodyAttachment(BodyAttachmentMetadata)

            /// Always assumed to have a text content type.
            case oversizeText(Metadata)

            /// Always assumed to have an image content type.
            case linkPreview(Metadata)

            /// Note that the row id is for the parent message containing the quoted reply,
            /// not the original message being quoted.
            case quotedReply(QuotedReplyMetadata)

            case sticker(StickerMetadata)

            /// Always assumed to have an image content type.
            case contactAvatar(Metadata)

            // MARK: - Message Metadata

            public class Metadata {
                /// The sqlite row id of the message owner.
                public let messageRowId: Int64

                /// The local receivedAtTimestamp of the owning message.
                public let receivedAtTimestamp: UInt64

                /// The row id for the thread containing the owning message.
                ///
                /// Confusingly, this is NOT the foreign reference used when the source type is thread
                /// (that's just set in ``threadOwnerRowId``!).
                /// This isn't exposed to most consumers of this object; its used for indexing/filtering
                /// when we want to e.g. get all files sent on messages in a thread.
                internal let threadRowId: Int64

                /// Validated type of the actual file content on disk, if we have it.
                /// Mirrors `Attachment.contentType`.
                ///
                /// We _write_ and keep this value if available for all attachments,
                /// but only _read_ it for:
                /// * message body attachments
                /// * quoted reply attachment (note some types are disallowed)
                ///
                /// Note: if you want to know if an attachment is, say, a video,
                /// even if you are ok using the mimeType for that if undownloaded,
                /// you must fetch the full attachment object and use its mimeType.
                public let contentType: ContentType?

                /// True if the owning message's ``TSEditState`` is `pastRevision`.
                public let isPastEditRevision: Bool

                internal init(
                    messageRowId: Int64,
                    receivedAtTimestamp: UInt64,
                    threadRowId: Int64,
                    contentType: ContentType?,
                    isPastEditRevision: Bool
                ) {
                    self.messageRowId = messageRowId
                    self.receivedAtTimestamp = receivedAtTimestamp
                    self.threadRowId = threadRowId
                    self.contentType = contentType
                    self.isPastEditRevision = isPastEditRevision
                }
            }

            public class BodyAttachmentMetadata: MessageSource.Metadata {
                /// Read-only in practice; we never set this for new message body attachments but
                /// it may be set for older messages.
                public let caption: String?

                /// Flag from the sender giving us a hint for how it should be rendered.
                public let renderingFlag: RenderingFlag

                /// Order of this attachment appears in the owning message's "array" of body attachments.
                /// Not necessarily an index; there may be gaps.
                public let orderInOwner: UInt32
                /// Uniquely identifies this attachment in the owning message's body attachments.
                public let idInOwner: UUID?

                /// If the message owning this body attachment is a view-once message
                public let isViewOnce: Bool

                internal init(
                    messageRowId: Int64,
                    receivedAtTimestamp: UInt64,
                    threadRowId: Int64,
                    contentType: ContentType?,
                    isPastEditRevision: Bool,
                    caption: String?,
                    renderingFlag: RenderingFlag,
                    orderInOwner: UInt32,
                    idInOwner: UUID?,
                    isViewOnce: Bool
                ) {
                    self.caption = caption
                    self.renderingFlag = renderingFlag
                    self.orderInOwner = orderInOwner
                    self.idInOwner = idInOwner
                    self.isViewOnce = isViewOnce
                    super.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: receivedAtTimestamp,
                        threadRowId: threadRowId,
                        contentType: contentType,
                        isPastEditRevision: isPastEditRevision
                    )
                }
            }

            public class QuotedReplyMetadata: MessageSource.Metadata {
                /// Flag from the sender giving us a hint for how it should be rendered.
                public let renderingFlag: RenderingFlag

                internal init(
                    messageRowId: Int64,
                    receivedAtTimestamp: UInt64,
                    threadRowId: Int64,
                    contentType: ContentType?,
                    isPastEditRevision: Bool,
                    renderingFlag: RenderingFlag
                ) {
                    self.renderingFlag = renderingFlag
                    super.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: receivedAtTimestamp,
                        threadRowId: threadRowId,
                        contentType: contentType,
                        isPastEditRevision: isPastEditRevision
                    )
                }
            }

            public class StickerMetadata: MessageSource.Metadata {
                /// Sticker pack info, only used (and required) for sticker messages.
                public let stickerPackId: Data
                public let stickerId: UInt32

                internal init(
                    messageRowId: Int64,
                    receivedAtTimestamp: UInt64,
                    threadRowId: Int64,
                    contentType: ContentType?,
                    isPastEditRevision: Bool,
                    stickerPackId: Data,
                    stickerId: UInt32
                ) {
                    self.stickerPackId = stickerPackId
                    self.stickerId = stickerId
                    super.init(
                        messageRowId: messageRowId,
                        receivedAtTimestamp: receivedAtTimestamp,
                        threadRowId: threadRowId,
                        contentType: contentType,
                        isPastEditRevision: isPastEditRevision
                    )
                }
            }

            public var messageRowId: Int64 {
                switch self {
                case .bodyAttachment(let metadata):
                    return metadata.messageRowId
                case .oversizeText(let metadata):
                    return metadata.messageRowId
                case .linkPreview(let metadata):
                    return metadata.messageRowId
                case .quotedReply(let metadata):
                    return metadata.messageRowId
                case .sticker(let metadata):
                    return metadata.messageRowId
                case .contactAvatar(let metadata):
                    return metadata.messageRowId
                }
            }
        }

        // MARK: - Story Message

        public enum StoryMessageSource {
            case media(MediaMetadata)
            case textStoryLinkPreview(StoryMessageSource.Metadata)

            // MARK: - Story Message Metadata

            public class Metadata {
                /// The sqlite row id of the story message owner.
                public let storyMessageRowId: Int64

                internal init(storyMessageRowId: Int64) {
                    self.storyMessageRowId = storyMessageRowId
                }
            }

            public class MediaMetadata: StoryMessageSource.Metadata {
                /// Caption on the attachment.
                public var caption: StyleOnlyMessageBody?
                /// Equivalent to RenderingFlag.shouldLoop; the only allowed flag for stories.
                public var shouldLoop: Bool

                internal init(
                    storyMessageRowId: Int64,
                    caption: StyleOnlyMessageBody?,
                    shouldLoop: Bool
                ) {
                    self.caption = caption
                    self.shouldLoop = shouldLoop
                    super.init(storyMessageRowId: storyMessageRowId)
                }
            }

            public var storyMsessageRowId: Int64 {
                switch self {
                case .media(let metadata):
                    return metadata.storyMessageRowId
                case .textStoryLinkPreview(let metadata):
                    return metadata.storyMessageRowId
                }
            }
        }

        // MARK: - Thread Metadata

        public enum ThreadSource {
            case threadWallpaperImage(ThreadMetadata)
            /// creationTimestamp is the local timestamp at which this ownership reference was created
            /// (in other words, when the user set this wallpaper).
            case globalThreadWallpaperImage(creationTimestamp: UInt64)

            public class ThreadMetadata {
                /// The sqlite row id of the thread owner.
                public let threadRowId: Int64
                /// Local timestamp at which this ownership reference was created
                /// (in other words, when the user set this wallpaper).
                public let creationTimestamp: UInt64

                internal init(threadRowId: Int64, creationTimestamp: UInt64) {
                    self.threadRowId = threadRowId
                    self.creationTimestamp = creationTimestamp
                }
            }
        }
    }
}

// MARK: - Validation

extension AttachmentReference.Owner {

    internal static func validateAndBuild(record: AttachmentReference.MessageAttachmentReferenceRecord) throws -> AttachmentReference.Owner {
        guard
            let ownerTypeRaw = Int(exactly: record.ownerType),
            let ownerType = AttachmentReference.MessageOwnerTypeRaw(rawValue: ownerTypeRaw)
        else {
            throw OWSAssertionError("Invalid owner type")
        }

        switch ownerType {
        case .bodyAttachment:
            guard let orderInOwner = record.orderInMessage else {
                throw OWSAssertionError("OrderInOwner required for body attachment")
            }
            return .message(.bodyAttachment(.init(
                messageRowId: record.ownerRowId,
                receivedAtTimestamp: record.receivedAtTimestamp,
                threadRowId: record.threadRowId,
                contentType: try record.contentType.map { try .init(rawValue: $0) },
                isPastEditRevision: record.ownerIsPastEditRevision,
                caption: record.caption,
                renderingFlag: try .init(rawValue: record.renderingFlag),
                orderInOwner: orderInOwner,
                idInOwner: record.idInMessage.flatMap { UUID(uuidString: $0) },
                isViewOnce: record.isViewOnce
            )))
        case .oversizeText:
            return .message(.oversizeText(.init(
                messageRowId: record.ownerRowId,
                receivedAtTimestamp: record.receivedAtTimestamp,
                threadRowId: record.threadRowId,
                contentType: try record.contentType.map { try .init(rawValue: $0) },
                isPastEditRevision: record.ownerIsPastEditRevision
            )))
        case .linkPreview:
            return .message(.linkPreview(.init(
                messageRowId: record.ownerRowId,
                receivedAtTimestamp: record.receivedAtTimestamp,
                threadRowId: record.threadRowId,
                contentType: try record.contentType.map { try .init(rawValue: $0) },
                isPastEditRevision: record.ownerIsPastEditRevision
            )))
        case .quotedReplyAttachment:
            return .message(.quotedReply(.init(
                messageRowId: record.ownerRowId,
                receivedAtTimestamp: record.receivedAtTimestamp,
                threadRowId: record.threadRowId,
                contentType: try record.contentType.map { try .init(rawValue: $0) },
                isPastEditRevision: record.ownerIsPastEditRevision,
                renderingFlag: try .init(rawValue: record.renderingFlag)
            )))
        case .sticker:
            guard
                let stickerId = record.stickerId,
                let stickerPackId = record.stickerPackId
            else {
                throw OWSAssertionError("Sticker metadata required for sticker attachment")
            }
            return .message(.sticker(.init(
                messageRowId: record.ownerRowId,
                receivedAtTimestamp: record.receivedAtTimestamp,
                threadRowId: record.threadRowId,
                contentType: try record.contentType.map { try .init(rawValue: $0) },
                isPastEditRevision: record.ownerIsPastEditRevision,
                stickerPackId: stickerPackId,
                stickerId: stickerId
            )))
        case .contactAvatar:
            return .message(.contactAvatar(.init(
                messageRowId: record.ownerRowId,
                receivedAtTimestamp: record.receivedAtTimestamp,
                threadRowId: record.threadRowId,
                contentType: try record.contentType.map { try .init(rawValue: $0) },
                isPastEditRevision: record.ownerIsPastEditRevision
            )))
        }
    }

    internal static func validateAndBuild(
        record: AttachmentReference.StoryMessageAttachmentReferenceRecord
    ) throws -> AttachmentReference.Owner {
        guard
            let ownerTypeRaw = Int(exactly: record.ownerType),
            let ownerType = AttachmentReference.StoryMessageOwnerTypeRaw(rawValue: ownerTypeRaw)
        else {
            throw OWSAssertionError("Invalid owner type")
        }

        switch ownerType {
        case .media:
            let caption: StyleOnlyMessageBody? = try record.caption.map { text in
                guard let rawRanges = record.captionBodyRanges else {
                    return .init(plaintext: text)
                }
                let decoder = JSONDecoder()
                let ranges = try decoder.decode([NSRangedValue<MessageBodyRanges.CollapsedStyle>].self, from: rawRanges)
                return .init(text: text, collapsedStyles: ranges)
            }
            return .storyMessage(.media(.init(
                storyMessageRowId: record.ownerRowId,
                caption: caption,
                shouldLoop: record.shouldLoop
            )))
        case .linkPreview:
            return .storyMessage(.textStoryLinkPreview(.init(storyMessageRowId: record.ownerRowId)))
        }
    }

    internal static func validateAndBuild(record: AttachmentReference.ThreadAttachmentReferenceRecord) throws -> AttachmentReference.Owner {
        if let ownerRowId = record.ownerRowId {
            return .thread(.threadWallpaperImage(.init(threadRowId: ownerRowId, creationTimestamp: record.creationTimestamp)))
        } else {
            return .thread(.globalThreadWallpaperImage(creationTimestamp: record.creationTimestamp))
        }
    }

    /// When we go from a pointer to a stream (e.g. by downloading) and find another attachment with the same plaintext hash,
    /// we instead reassign the pointer's references to that existing attachment. When we do so, we need to update their contentType
    /// to match the new/old attachment (theyre the same plaintext hash so same content type).
    public func forReassignmentWithContentType(_ contentType: AttachmentReference.ContentType) -> Self {
        switch self {
        case .message(let messageSource):
            return .message({
                switch messageSource {
                case .bodyAttachment(let metadata):
                    return .bodyAttachment(.init(
                        messageRowId: metadata.messageRowId,
                        receivedAtTimestamp: metadata.receivedAtTimestamp,
                        threadRowId: metadata.threadRowId,
                        contentType: contentType,
                        isPastEditRevision: metadata.isPastEditRevision,
                        caption: metadata.caption,
                        renderingFlag: metadata.renderingFlag,
                        orderInOwner: metadata.orderInOwner,
                        idInOwner: metadata.idInOwner,
                        isViewOnce: metadata.isViewOnce
                    ))
                case .oversizeText(let metadata):
                    return .oversizeText(.init(
                        messageRowId: metadata.messageRowId,
                        receivedAtTimestamp: metadata.receivedAtTimestamp,
                        threadRowId: metadata.threadRowId,
                        contentType: contentType,
                        isPastEditRevision: metadata.isPastEditRevision
                    ))
                case .linkPreview(let metadata):
                    return .linkPreview(.init(
                        messageRowId: metadata.messageRowId,
                        receivedAtTimestamp: metadata.receivedAtTimestamp,
                        threadRowId: metadata.threadRowId,
                        contentType: contentType,
                        isPastEditRevision: metadata.isPastEditRevision
                    ))
                case .quotedReply(let metadata):
                    return .quotedReply(.init(
                        messageRowId: metadata.messageRowId,
                        receivedAtTimestamp: metadata.receivedAtTimestamp,
                        threadRowId: metadata.threadRowId,
                        contentType: contentType,
                        isPastEditRevision: metadata.isPastEditRevision,
                        renderingFlag: metadata.renderingFlag
                    ))
                case .sticker(let metadata):
                    return .sticker(.init(
                        messageRowId: metadata.messageRowId,
                        receivedAtTimestamp: metadata.receivedAtTimestamp,
                        threadRowId: metadata.threadRowId,
                        contentType: contentType,
                        isPastEditRevision: metadata.isPastEditRevision,
                        stickerPackId: metadata.stickerPackId,
                        stickerId: metadata.stickerId
                    ))
                case .contactAvatar(let metadata):
                    return .contactAvatar(.init(
                        messageRowId: metadata.messageRowId,
                        receivedAtTimestamp: metadata.receivedAtTimestamp,
                        threadRowId: metadata.threadRowId,
                        contentType: contentType,
                        isPastEditRevision: metadata.isPastEditRevision
                    ))
                }
            }())
        case .storyMessage(let storyMessageSource):
            switch storyMessageSource {
            case .media(let metadata):
                return .storyMessage(.media(metadata))
            case .textStoryLinkPreview(let metadata):
                return .storyMessage(.textStoryLinkPreview(metadata))
            }
        case .thread(let threadSource):
            switch threadSource {
            case .threadWallpaperImage(let metadata):
                return .thread(.threadWallpaperImage(metadata))
            case .globalThreadWallpaperImage(let creationTimestamp):
                return .thread(.globalThreadWallpaperImage(creationTimestamp: creationTimestamp))
            }
        }
    }
}

// MARK: - Converters

extension AttachmentReference.Owner {

    public var id: AttachmentReference.OwnerId {
        switch self {
        case .message(.bodyAttachment(let metadata)):
            return .messageBodyAttachment(messageRowId: metadata.messageRowId)
        case .message(.oversizeText(let metadata)):
            return .messageOversizeText(messageRowId: metadata.messageRowId)
        case .message(.linkPreview(let metadata)):
            return .messageLinkPreview(messageRowId: metadata.messageRowId)
        case .message(.quotedReply(let metadata)):
            return .quotedReplyAttachment(messageRowId: metadata.messageRowId)
        case .message(.sticker(let metadata)):
            return .messageSticker(messageRowId: metadata.messageRowId)
        case .message(.contactAvatar(let metadata)):
            return .messageContactAvatar(messageRowId: metadata.messageRowId)
        case .storyMessage(.media(let metadata)):
            return .storyMessageMedia(storyMessageRowId: metadata.storyMessageRowId)
        case .storyMessage(.textStoryLinkPreview(let metadata)):
            return .storyMessageLinkPreview(storyMessageRowId: metadata.storyMessageRowId)
        case .thread(.threadWallpaperImage(let metadata)):
            return .threadWallpaperImage(threadRowId: metadata.threadRowId)
        case .thread(.globalThreadWallpaperImage):
            return .globalThreadWallpaperImage
        }
    }
}

extension AttachmentReference.Owner.MessageSource {

    internal var rawMessageOwnerType: AttachmentReference.MessageOwnerTypeRaw {
        switch self {
        case .bodyAttachment:
            return .bodyAttachment
        case .oversizeText:
            return .oversizeText
        case .linkPreview:
            return .linkPreview
        case .quotedReply:
            return .quotedReplyAttachment
        case .sticker:
            return .sticker
        case .contactAvatar:
            return .contactAvatar
        }
    }
}

extension AttachmentReference.Owner.StoryMessageSource {

    internal var rawStoryMessageOwnerType: AttachmentReference.StoryMessageOwnerTypeRaw {
        switch self {
        case .media:
            return .media
        case .textStoryLinkPreview:
            return .linkPreview
        }
    }
}

extension AttachmentReference.MessageOwnerTypeRaw {

    internal func with(messageRowId: Int64) -> AttachmentReference.OwnerId {
        switch self {
        case .bodyAttachment:
            return .messageBodyAttachment(messageRowId: messageRowId)
        case .oversizeText:
            return .messageOversizeText(messageRowId: messageRowId)
        case .linkPreview:
            return .messageLinkPreview(messageRowId: messageRowId)
        case .quotedReplyAttachment:
            return .quotedReplyAttachment(messageRowId: messageRowId)
        case .sticker:
            return .messageSticker(messageRowId: messageRowId)
        case .contactAvatar:
            return .messageContactAvatar(messageRowId: messageRowId)
        }
    }
}

extension AttachmentReference.StoryMessageOwnerTypeRaw {

    internal func with(storyMessageRowId: Int64) -> AttachmentReference.OwnerId {
        switch self {
        case .media:
            return .storyMessageMedia(storyMessageRowId: storyMessageRowId)
        case .linkPreview:
            return .storyMessageLinkPreview(storyMessageRowId: storyMessageRowId)
        }
    }
}
