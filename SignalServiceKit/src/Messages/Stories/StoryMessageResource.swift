//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class StoryMessageResource {

    private let storyRowId: Int64
    private let attachmentRowId: Int64

    public let caption: String?
    // Empty if nil in the db.
    public let captionStyles: [NSRangedValue<MessageBodyRanges.CollapsedStyle>]
    public let isLoopingVideo: Bool

    private init(
        storyRowId: Int64,
        attachmentRowId: Int64,
        caption: String,
        captionStyles: [NSRangedValue<MessageBodyRanges.CollapsedStyle>],
        isLoopingVideo: Bool
    ) {
        self.storyRowId = storyRowId
        self.attachmentRowId = attachmentRowId
        self.caption = caption
        self.captionStyles = captionStyles
        self.isLoopingVideo = isLoopingVideo
    }

    public static func fetch(storyMessage: StoryMessage, tx: SDSAnyReadTransaction) -> StoryMessageResource? {
        // TODO: add the AttachmentReferences table and do a lookup here.
        owsFailDebug("We should not YET be looking up attachment references")
        return nil
    }

    // TODO: this should return a new style attachment
    public func fetchAttachment(tx: SDSAnyReadTransaction) -> TSAttachment? {
        // TODO: add the Attachments table and do a lookup here.
        owsFailDebug("We should not YET be looking up v2 attachments")
        return nil
    }

    public func captionProtoBodyRanges() -> [SSKProtoBodyRange] {
        return MessageBodyRanges(mentions: [:], orderedMentions: [], collapsedStyles: captionStyles).toProtoBodyRanges()
    }
}
