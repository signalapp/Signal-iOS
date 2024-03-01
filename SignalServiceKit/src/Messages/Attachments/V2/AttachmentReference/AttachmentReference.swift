//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// TODO: actually define this class; just a placeholder for now.
/// Represents an edge between some owner (a message, a story, a thread, etc) and an attachment.
public class AttachmentReference {

    // MARK: - Vars

    /// Sqlite row id of the attachment on the Attachments table.
    /// Multiple AttachmentReferences can point to the same Attachment.
    public let attachmentRowId: Int64

    /// We compute/validate this once, when we read from disk (or instantate an instance in memory).
    public let owner: Owner

    // MARK: - Init

    private init?(
        ownerTypeRaw: OwnerTypeRaw,
        attachmentRowId: Int64,
        ownerRowId: Int64,
        orderInOwner: UInt32?,
        flags: TSAttachmentType,
        threadRowId: UInt64?,
        caption: String?,
        captionBodyRanges: MessageBodyRanges,
        sourceFileName: String?,
        stickerPackId: Data?,
        stickerId: UInt64?,
        contentType: TSResourceContentType?
    ) {
        let ownerType = ownerTypeRaw.with(ownerId: ownerRowId)

        // Do source validation
        guard
            let owner = Owner.validateAndBuild(
                ownerType: ownerType,
                orderInOwner: orderInOwner,
                flags: flags,
                threadRowId: threadRowId,
                caption: caption,
                captionBodyRanges: captionBodyRanges,
                sourceFilename: sourceFileName,
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
