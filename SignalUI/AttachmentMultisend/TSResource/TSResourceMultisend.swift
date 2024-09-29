//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import SignalServiceKit

public class TSResourceMultisend {

    private init() {}

    public class func sendApprovedMedia(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) -> AttachmentMultisend.Result {
        return AttachmentMultisend.sendApprovedMedia(
            conversations: conversations,
            approvedMessageBody: approvalMessageBody,
            approvedAttachments: approvedAttachments
        )
    }

    public class func sendTextAttachment(
        _ textAttachment: UnsentTextAttachment,
        to conversations: [ConversationItem]
    ) -> AttachmentMultisend.Result {
        return AttachmentMultisend.sendTextAttachment(textAttachment, to: conversations)
    }
}
