//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// TODO: actually define this class; just a placeholder for now.
/// Represents an edge between some owner (a message, a story, a thread, etc) and an attachment.
public class AttachmentReference {

    /// We keep the raw type, without any metadata, on the reference table.
    public typealias ContentType = Attachment.ContentTypeRaw

    // MARK: - Vars

    /// Sqlite row id of the attachment on the Attachments table.
    /// Multiple AttachmentReferences can point to the same Attachment.
    public let attachmentRowId: Int64

    /// We compute/validate this once, when we read from disk (or instantate an instance in memory).
    public let owner: Owner

    /// For message owners, the local receivedAtTimestamp of the owning message.
    /// For thread owners, the local timestamp when we created the ownership reference.
    public let receivedAtTimestamp: UInt64

    /// Filename from the sender, used for rendering as a file attachment.
    /// NOT the same as the file name on disk.
    /// Comes from ``SSKProtoAttachmentPointer.fileName``.
    public let sourceFilename: String?

    /// Byte count from the sender of this attachment (can therefore be spoofed).
    /// Comes from ``SSKProtoAttachmentPointer.size``.
    public let sourceUnencryptedByteCount: UInt32?

    /// Width/height from the sender of this attachment (can therefore be spoofed).
    /// Comes from ``SSKProtoAttachmentPointer.width`` and ``SSKProtoAttachmentPointer.height``.
    public let sourceMediaSizePixels: CGSize?

    // MARK: - Init

    private init?(
        messageOwnerTypeRaw: MessageOwnerTypeRaw,
        attachmentRowId: Int64,
        messageRowId: Int64,
        orderInOwner: UInt32?,
        receivedAtTimestamp: UInt64,
        renderingFlag: RenderingFlag,
        threadRowId: UInt64,
        caption: String?,
        captionBodyRanges: MessageBodyRanges,
        sourceFileName: String?,
        sourceUnencryptedByteCount: UInt32,
        sourceMediaHeightPixels: UInt32,
        sourceMediaWidthPixels: UInt32,
        stickerPackId: Data?,
        stickerId: UInt32?,
        contentType: ContentType?
    ) {
        let ownerId = messageOwnerTypeRaw.with(messageRowId: messageRowId)

        // Do source validation
        guard
            Owner.validateAndBuild(
                messageRowId: messageRowId,
                messageOwnerType: messageOwnerTypeRaw,
                orderInOwner: orderInOwner,
                renderingFlag: renderingFlag,
                threadRowId: threadRowId,
                caption: caption,
                captionBodyRanges: captionBodyRanges,
                stickerPackId: stickerPackId,
                stickerId: stickerId,
                contentType: contentType
            ) != nil
        else {
            return nil
        }

        fatalError("No instances should exist yet!")
    }

    private init?(
        storyMessageOwnerTypeRaw: StoryMessageOwnerTypeRaw,
        attachmentRowId: Int64,
        storyMessageRowId: Int64,
        receivedAtTimestamp: UInt64,
        shouldLoop: Bool,
        caption: String?,
        captionBodyRanges: MessageBodyRanges,
        sourceFileName: String?,
        sourceUnencryptedByteCount: UInt32,
        sourceMediaHeightPixels: UInt32,
        sourceMediaWidthPixels: UInt32
    ) {
        let ownerId = storyMessageOwnerTypeRaw.with(storyMessageRowId: storyMessageRowId)

        // Do source validation
        guard
            Owner.validateAndBuild(
                storyMessageRowId: storyMessageRowId,
                storyMessageOwnerType: storyMessageOwnerTypeRaw,
                shouldLoop: shouldLoop,
                caption: caption,
                captionBodyRanges: captionBodyRanges
            ) != nil
        else {
            return nil
        }

        fatalError("No instances should exist yet!")
    }

    private init?(
        attachmentRowId: Int64,
        threadOwnerRowId: Int64,
        creationTimestamp: UInt64
    ) {
        let ownerId = OwnerId.threadWallpaperImage(threadRowId: threadOwnerRowId)

        // Do source validation
        guard
            Owner.validateAndBuild(threadRowId: threadOwnerRowId) != nil
        else {
            return nil
        }

        fatalError("No instances should exist yet!")
    }
}
