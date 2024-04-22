//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public class TSResourceMultisend {

    private init() {}

    public class func sendApprovedMedia(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) -> AttachmentMultisend.Result {
        if FeatureFlags.newAttachmentsUseV2 {
            return AttachmentMultisend.sendApprovedMedia(
                conversations: conversations,
                approvedMessageBody: approvalMessageBody,
                approvedAttachments: approvedAttachments
            )
        } else {
            return TSAttachmentMultisend.sendApprovedMedia(
                conversations: conversations,
                approvalMessageBody: approvalMessageBody,
                approvedAttachments: approvedAttachments
            )
        }
    }

    public class func sendTextAttachment(
        _ textAttachment: UnsentTextAttachment,
        to conversations: [ConversationItem]
    ) -> AttachmentMultisend.Result {
        if FeatureFlags.newAttachmentsUseV2 {
            return AttachmentMultisend.sendTextAttachment(textAttachment, to: conversations)
        } else {
            return TSAttachmentMultisend.sendTextAttachment(textAttachment, to: conversations)
        }
    }
}
