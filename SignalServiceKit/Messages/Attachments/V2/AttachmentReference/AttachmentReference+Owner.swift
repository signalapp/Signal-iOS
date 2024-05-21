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

    /// A builder for the "owner" metadata of the attachment, with per-type
    /// metadata required for construction.
    ///
    /// Note: some metadata is generically available on the source (proto or in-memory draft);
    /// this enum contains only type-specific fields.
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

            public class Metadata: AttachmentReference.Metadata {
                public var messageRowId: Int64 { _messageOwnerRowId! }
            }

            public class BodyAttachmentMetadata: Metadata {
                public var contentType: ContentType? { _contentType }
                /// Read-only in practice; we never set this for new message body attachments but
                /// it may be set for older messages.
                public var caption: MessageBody? { _caption }
                public var renderingFlag: RenderingFlag { _renderingFlag }
                public var index: UInt32 { _orderInOwner! }

                override class var requiredFields: [AnyKeyPath] { [\Self._orderInOwner] }
            }

            public class QuotedReplyMetadata: Metadata {
                public var contentType: ContentType? { _contentType }
                public var renderingFlag: RenderingFlag { _renderingFlag }
            }

            public class StickerMetadata: Metadata {
                public var stickerPackId: Data { _stickerPackId! }
                public var stickerId: UInt32 { _stickerId! }

                override class var requiredFields: [AnyKeyPath] { [\Self._stickerPackId, \Self._stickerId] }
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
            case textStoryLinkPreview(Metadata)

            // MARK: - Story Message Metadata

            public class Metadata: AttachmentReference.Metadata {
                public var storyMessageRowId: Int64 { _storyMessageOwnerRowId! }
            }

            public class MediaMetadata: Metadata {
                public var contentType: ContentType? { _contentType }
                public var caption: StyleOnlyMessageBody? { _caption.map(StyleOnlyMessageBody.init(messageBody:)) }
                public var shouldLoop: Bool { _renderingFlag == .shouldLoop }
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
            case globalThreadWallpaperImage

            public class ThreadMetadata: AttachmentReference.Metadata {
                public var threadRowId: Int64 { _threadOwnerRowId! }
            }
        }
    }

    // MARK: - Metadata

    /// Every AttachmentReference keeps all the metadata provided when it is initialized (or updated).
    /// However, we only expose (and use) each field on specific cases; these are represented by
    /// subclasses of this class defined in this file.
    public class Metadata {
        /// The sqlite row id of the message owner.
        /// Required in all message cases.
        fileprivate let _messageOwnerRowId: Int64?

        /// The sqlite row id of the story message owner.
        /// Required in all story message cases.
        fileprivate let _storyMessageOwnerRowId: Int64?

        /// The sqlite row id of the thread owner.
        /// Required in all thread cases.
        fileprivate let _threadOwnerRowId: Int64?

        /// Order on the containing message.
        /// Message body attachments only, but required in that case.
        fileprivate let _orderInOwner: UInt32?

        /// Flag from the sender giving us a hint for how it should be rendered.
        /// Used for:
        /// * message body attachments
        /// * quoted reply attachment
        /// * story media, but only the "shouldLoop" case is respected.
        /// Even in those cases the default value is allowed.
        fileprivate let _renderingFlag: RenderingFlag

        /// For message sources, the row id for the thread containing that message.
        /// Required for message sources.
        ///
        /// Confusingly, this is NOT the foreign reference used when the source type is thread
        /// (that's just set in ``threadOwnerRowId``!).
        /// This isn't exposed to consumers of this object; its used for indexing/filtering
        /// when we want to e.g. get all files sent on messages in a thread.
        fileprivate let _threadRowId: UInt64?

        /// Caption on the attachment.
        /// Used for:
        /// * message body attachments
        ///   * legacy only; the ability to set captions on message
        ///     attachments was removed long ago. We maintain them
        ///     for existing messages. New message attachments always
        ///     inherit their "caption" from their parent message.
        /// * story media
        /// But even in those cases its optional.
        fileprivate let _caption: MessageBody?

        /// Sticker pack info, only used (and required) for sticker messages.
        fileprivate let _stickerPackId: Data?
        fileprivate let _stickerId: UInt32?

        /// Validated type of the actual file content on disk, if we have it.
        /// Mirrors `Attachment.contentType`.
        ///
        /// We _write_ and keep this value if available for all attachments,
        /// but only _read_ it for:
        /// * message body attachments
        /// * quoted reply attachment (note some types are disallowed)
        /// * story media (note some types are disallowed)
        /// Null if the attachment is undownloaded.
        /// 
        /// Note: if you want to know if an attachment is, say, a video,
        /// even if you are ok using the mimeType for that if undownloaded,
        /// you must fetch the full attachment object and use its mimeType.
        fileprivate let _contentType: ContentType?

        fileprivate class var requiredFields: [AnyKeyPath] { [] }

        class MissingRequiredFieldError: Error {}

        public required init(
            messageOwnerRowId: Int64,
            orderInOwner: UInt32?,
            renderingFlag: RenderingFlag,
            threadRowId: UInt64?,
            caption: MessageBody?,
            stickerPackId: Data?,
            stickerId: UInt32?,
            contentType: AttachmentReference.ContentType?
        ) throws {
            self._messageOwnerRowId = messageOwnerRowId
            self._storyMessageOwnerRowId = nil
            self._threadOwnerRowId = nil
            self._orderInOwner = orderInOwner
            self._renderingFlag = renderingFlag
            self._threadRowId = threadRowId
            self._caption = caption
            self._stickerPackId = stickerPackId
            self._stickerId = stickerId
            self._contentType = contentType

            for keyPath in type(of: self).requiredFields {
                guard self[keyPath: keyPath] != nil else {
                    throw MissingRequiredFieldError()
                }
            }
        }

        public required init(
            storyMessageOwnerRowId: Int64,
            shouldLoop: Bool,
            caption: MessageBody?
        ) throws {
            self._messageOwnerRowId = nil
            self._storyMessageOwnerRowId = storyMessageOwnerRowId
            self._threadOwnerRowId = nil
            self._orderInOwner = nil
            self._renderingFlag = shouldLoop ? .shouldLoop : .default
            self._threadRowId = nil
            self._caption = caption
            self._stickerPackId = nil
            self._stickerId = nil
            self._contentType = nil

            for keyPath in type(of: self).requiredFields {
                guard self[keyPath: keyPath] != nil else {
                    throw MissingRequiredFieldError()
                }
            }
        }

        public required init(
            threadOwnerRowId: Int64
        ) throws {
            self._messageOwnerRowId = nil
            self._storyMessageOwnerRowId = nil
            self._threadOwnerRowId = threadOwnerRowId
            self._orderInOwner = nil
            self._renderingFlag = .default
            self._threadRowId = nil
            self._caption = nil
            self._stickerPackId = nil
            self._stickerId = nil
            self._contentType = nil

            for keyPath in type(of: self).requiredFields {
                guard self[keyPath: keyPath] != nil else {
                    throw MissingRequiredFieldError()
                }
            }
        }
    }
}

// MARK: - Validation

extension AttachmentReference.Owner {

    internal static func validateAndBuild(
        messageRowId: Int64,
        messageOwnerType: AttachmentReference.MessageOwnerTypeRaw,
        orderInOwner: UInt32?,
        renderingFlag: AttachmentReference.RenderingFlag,
        threadRowId: UInt64?,
        caption: String?,
        captionBodyRanges: MessageBodyRanges,
        stickerPackId: Data?,
        stickerId: UInt32?,
        contentType: AttachmentReference.ContentType?
    ) -> AttachmentReference.Owner? {
        func buildAndValidateMetadata<MetadataType: AttachmentReference.Metadata>() throws -> MetadataType {
            let captionBody = caption.map { MessageBody(text: $0, ranges: captionBodyRanges) }
            return try MetadataType.init(
                messageOwnerRowId: messageRowId,
                orderInOwner: orderInOwner,
                renderingFlag: renderingFlag,
                threadRowId: threadRowId,
                caption: captionBody,
                stickerPackId: stickerPackId,
                stickerId: stickerId,
                contentType: contentType
            )
        }

        do {
            switch messageOwnerType {
            case .bodyAttachment:
                return .message(.bodyAttachment(try buildAndValidateMetadata()))
            case .oversizeText:
                return .message(.oversizeText(try buildAndValidateMetadata()))
            case .linkPreview:
                return .message(.linkPreview(try buildAndValidateMetadata()))
            case .quotedReplyAttachment:
                return .message(.quotedReply(try buildAndValidateMetadata()))
            case .sticker:
                return .message(.sticker(try buildAndValidateMetadata()))
            case .contactAvatar:
                return .message(.contactAvatar(try buildAndValidateMetadata()))
            }
        } catch {
            return nil
        }
    }

    internal static func validateAndBuild(
        storyMessageRowId: Int64,
        storyMessageOwnerType: AttachmentReference.StoryMessageOwnerTypeRaw,
        shouldLoop: Bool,
        caption: String?,
        captionBodyRanges: MessageBodyRanges
    ) -> AttachmentReference.Owner? {
        func buildAndValidateMetadata<MetadataType: AttachmentReference.Metadata>() throws -> MetadataType {
            let captionBody = caption.map { MessageBody(text: $0, ranges: captionBodyRanges) }
            return try MetadataType.init(
                storyMessageOwnerRowId: storyMessageRowId,
                shouldLoop: shouldLoop,
                caption: captionBody
            )
        }

        do {
            switch storyMessageOwnerType {
            case .media:
                return .storyMessage(.media(try buildAndValidateMetadata()))
            case .linkPreview:
                return .storyMessage(.textStoryLinkPreview(try buildAndValidateMetadata()))
            }
        } catch {
            return nil
        }
    }

    internal static func validateAndBuild(
        threadRowId: Int64
    ) -> AttachmentReference.Owner? {
        func buildAndValidateMetadata<MetadataType: AttachmentReference.Metadata>() throws -> MetadataType {
            return try MetadataType.init(
                threadOwnerRowId: threadRowId
            )
        }

        do {
            return .thread(.threadWallpaperImage(try buildAndValidateMetadata()))
        } catch {
            return nil
        }
    }

    internal static func validateAndBuildGlobalThreadWallpaper(
        threadRowId: Int64
    ) -> AttachmentReference.Owner? {
        return .thread(.globalThreadWallpaperImage)
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

extension AttachmentReference.OwnerId {

    internal var rawMessageOwnerType: AttachmentReference.MessageOwnerTypeRaw? {
        switch self {
        case .messageBodyAttachment:
            return .bodyAttachment
        case .messageOversizeText:
            return .oversizeText
        case .messageLinkPreview:
            return .linkPreview
        case .quotedReplyAttachment:
            return .quotedReplyAttachment
        case .messageSticker:
            return .sticker
        case .messageContactAvatar:
            return .contactAvatar
        case .storyMessageMedia, .storyMessageLinkPreview, .threadWallpaperImage, .globalThreadWallpaperImage:
            return nil
        }
    }

    internal var rawStoryMessageOwnerType: AttachmentReference.StoryMessageOwnerTypeRaw? {
        switch self {
        case
                .messageBodyAttachment,
                .messageOversizeText,
                .messageLinkPreview,
                .quotedReplyAttachment,
                .messageSticker,
                .messageContactAvatar,
                .threadWallpaperImage,
                .globalThreadWallpaperImage:
            return nil
        case .storyMessageMedia:
            return .media
        case .storyMessageLinkPreview:
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
