//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A text attachment with the associated image preview loaded from the database.
/// Doesn't load the preview's _image_, just the attachment database object.
public struct PreloadedTextAttachment: Equatable {
    public let textAttachment: TextAttachment
    public let linkPreviewAttachment: TSAttachment?

    private init(textAttachment: TextAttachment, linkPreviewAttachment: TSAttachment?) {
        self.textAttachment = textAttachment
        self.linkPreviewAttachment = linkPreviewAttachment
    }

    public static func from(
        _ textAttachment: TextAttachment,
        storyMessage: StoryMessage,
        tx: SDSAnyReadTransaction
    ) -> Self {
        let linkPreviewAttachment: TSAttachment? = textAttachment.preview?.imageAttachmentUniqueId(
            forParentStoryMessage: storyMessage,
            tx: tx
        ).map { uniqueId in
            return TSAttachment.anyFetch(uniqueId: uniqueId, transaction: tx)
        } ?? nil
        return .init(textAttachment: textAttachment, linkPreviewAttachment: linkPreviewAttachment)
    }
}
