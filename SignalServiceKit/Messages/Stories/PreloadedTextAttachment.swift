//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A text attachment with the associated image preview loaded from the database.
/// Doesn't load the preview's _image_, just the attachment database object.
public struct PreloadedTextAttachment: Equatable {
    public let textAttachment: TextAttachment
    public let linkPreviewAttachment: ReferencedAttachment?

    private init(textAttachment: TextAttachment, linkPreviewAttachment: ReferencedAttachment?) {
        self.textAttachment = textAttachment
        self.linkPreviewAttachment = linkPreviewAttachment
    }

    public static func from(
        _ textAttachment: TextAttachment,
        storyMessage: StoryMessage,
        tx: SDSAnyReadTransaction
    ) -> Self {
        let linkPreviewAttachment: ReferencedAttachment? = storyMessage.id.map { rowId in
            DependenciesBridge.shared.attachmentStore
                .fetchFirstReferencedAttachment(
                    for: .storyMessageLinkPreview(storyMessageRowId: rowId),
                    tx: tx.asV2Read
                )
        } ?? nil
        return .init(textAttachment: textAttachment, linkPreviewAttachment: linkPreviewAttachment)
    }

    public static func == (lhs: PreloadedTextAttachment, rhs: PreloadedTextAttachment) -> Bool {
        var linkPreviewAttachmentsMatch = (lhs.linkPreviewAttachment == nil) == (rhs.linkPreviewAttachment == nil)
        if
            let lhsAttachment = lhs.linkPreviewAttachment,
            let rhsAttachment = rhs.linkPreviewAttachment
        {
            linkPreviewAttachmentsMatch =
                lhsAttachment.attachment.id == rhsAttachment.attachment.id
                && lhsAttachment.reference.hasSameOwner(as: rhsAttachment.reference)
        }
        return lhs.textAttachment == rhs.textAttachment && linkPreviewAttachmentsMatch
    }
}
