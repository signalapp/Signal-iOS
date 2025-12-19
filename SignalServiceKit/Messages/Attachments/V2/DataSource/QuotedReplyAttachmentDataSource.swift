//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A DataSource for a quoted reply thumbnail attachment to be created locally, with
/// additional required metadata.
public enum QuotedReplyAttachmentDataSource {
    /// We took the original message's attachment, transcoded/resized it as needed,
    /// and have prepared it for use as a totally independent attachment.
    /// No reference to the original attachment is needed.
    /// (It may even have been a legacy attachment!)
    case pendingAttachment(PendingAttachmentSource)

    /// The original message's attachment.
    /// Used only if we were unable to transcode and create a PendingAttachment.
    /// This could be because it came from the message receive flow, or because
    /// the original is/was only a pointer and not available locally to transcode.
    /// The original can be used at download time as the "source", if it is a stream by then.
    case originalAttachment(OriginalAttachmentSource)

    public var originalAttachmentMimeType: String {
        switch self {
        case .pendingAttachment(let pendingAttachmentSource):
            return pendingAttachmentSource.originalAttachmentMimeType
        case .originalAttachment(let originalAttachmentSource):
            return originalAttachmentSource.mimeType
        }
    }

    public var originalAttachmentSourceFilename: String? {
        switch self {
        case .pendingAttachment(let pendingAttachmentSource):
            return pendingAttachmentSource.originalAttachmentSourceFilename
        case .originalAttachment(let originalAttachmentSource):
            return originalAttachmentSource.sourceFilename
        }
    }

    public struct PendingAttachmentSource {
        /// A pending attachment representing the thumbnail.
        let pendingAttachment: PendingAttachment
        /// The mime type of the original (thumbnailed) attachment.
        let originalAttachmentMimeType: String
        /// The source filename of the original (thumbnailed) attachment.
        let originalAttachmentSourceFilename: String?
    }

    /// Reference to an existing attachment to use as the source for the quoted reply.
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
}
