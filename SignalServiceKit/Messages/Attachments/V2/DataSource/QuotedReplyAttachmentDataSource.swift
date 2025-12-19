//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// A data source for creating quoted-reply thumbnail attachments locally.
public enum QuotedReplyAttachmentDataSource {
    /// This thumbnail is a new independent attachment created from an
    /// attachment on the message being quoted.
    case pendingAttachment(PendingAttachmentSource)

    /// This thumbnail refers to an attachment on the message being quoted.
    case originalAttachment(OriginalAttachmentSource)

    /// This thumbnail refers to an attachment that was not found locally, and
    /// so instead we use an attahcment pointer provided by the quote author.
    case notFoundLocallyAttachment(NotFoundLocallyAttachmentSource)

    public var originalAttachmentMimeType: String {
        switch self {
        case .pendingAttachment(let pendingAttachmentSource):
            return pendingAttachmentSource.originalAttachmentMimeType
        case .originalAttachment(let originalAttachmentSource):
            return originalAttachmentSource.mimeType
        case .notFoundLocallyAttachment(let notFoundLocallyAttachmentSource):
            return notFoundLocallyAttachmentSource.originalAttachmentMimeType
        }
    }

    public struct PendingAttachmentSource {
        let pendingAttachment: PendingAttachment
        let originalAttachmentMimeType: String
    }

    public struct OriginalAttachmentSource {
        public let id: Attachment.IDType
        public let mimeType: String
        public let renderingFlag: AttachmentReference.RenderingFlag
        public let sourceFilename: String?
        public let sourceUnencryptedByteCount: UInt32?
        public let sourceMediaSizePixels: CGSize?

        /// Pointer proto from the sender of the quoted reply.
        public let thumbnailPointerFromSender: SSKProtoAttachmentPointer?
    }

    public struct NotFoundLocallyAttachmentSource {
        public let thumbnailPointerProto: SSKProtoAttachmentPointer
        public let originalAttachmentMimeType: String
    }
}
