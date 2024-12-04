//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A text attachment with the associated image preview loaded from the database.
/// Doesn't load the preview's _image_, just the attachment database object.
public struct PreloadedTextAttachment: Equatable {
    public let textAttachment: TextAttachment
    public let linkPreviewAttachment: Attachment?

    private init(textAttachment: TextAttachment, linkPreviewAttachment: Attachment?) {
        self.textAttachment = textAttachment
        self.linkPreviewAttachment = linkPreviewAttachment
    }

    public static func from(
        _ textAttachment: TextAttachment,
        storyMessage: StoryMessage,
        tx: SDSAnyReadTransaction
    ) -> Self {
        let linkPreviewAttachment: Attachment? = storyMessage.id.map { rowId in
            DependenciesBridge.shared.attachmentStore
                .fetchFirstReferencedAttachment(
                    for: .storyMessageLinkPreview(storyMessageRowId: rowId),
                    tx: tx.asV2Read
                )?
                .attachment
        } ?? nil
        return .init(textAttachment: textAttachment, linkPreviewAttachment: linkPreviewAttachment)
    }

    public static func == (lhs: PreloadedTextAttachment, rhs: PreloadedTextAttachment) -> Bool {
        return lhs.textAttachment == rhs.textAttachment
            && lhs.linkPreviewAttachment?.id == rhs.linkPreviewAttachment?.id
    }
}
