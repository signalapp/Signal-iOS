//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// A ``TSAttachmentReference`` for a story message's TSAttachment.
public class StoryMessageTSAttachmentReference: TSAttachmentReference {

    private let caption: StyleOnlyMessageBody?

    internal init(uniqueId: String, attachment: TSAttachment?, caption: StyleOnlyMessageBody?) {
        self.caption = caption
        super.init(uniqueId: uniqueId, attachment: attachment)
    }

    override public var storyMediaCaption: StyleOnlyMessageBody? { caption }
}
