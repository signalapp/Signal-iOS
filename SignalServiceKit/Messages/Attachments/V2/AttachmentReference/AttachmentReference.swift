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
        ownerTypeRaw: OwnerTypeRaw,
        attachmentRowId: Int64,
        ownerRowId: Int64,
        orderInOwner: UInt32?,
        renderingFlag: RenderingFlag,
        threadRowId: UInt64?,
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
        let ownerId = ownerTypeRaw.with(ownerId: ownerRowId)

        // Do source validation
        guard
            let owner = Owner.validateAndBuild(
                ownerId: ownerId,
                orderInOwner: orderInOwner,
                renderingFlag: renderingFlag,
                threadRowId: threadRowId,
                caption: caption,
                captionBodyRanges: captionBodyRanges,
                stickerPackId: stickerPackId,
                stickerId: stickerId,
                contentType: contentType
            )
        else {
            return nil
        }

        fatalError("No instances should exist yet!")
    }
}
