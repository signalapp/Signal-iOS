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
    ) -> Promise<[TSThread]> {
        return TSAttachmentMultisend.sendApprovedMedia(
            conversations: conversations,
            approvalMessageBody: approvalMessageBody,
            approvedAttachments: approvedAttachments
        )
    }

    public class func sendApprovedMediaFromShareExtension(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment],
        messagesReadyToSend: @escaping ([PreparedOutgoingMessage]) -> Void
    ) -> Promise<[TSThread]> {
        return TSAttachmentMultisend.sendApprovedMediaFromShareExtension(
            conversations: conversations,
            approvalMessageBody: approvalMessageBody,
            approvedAttachments: approvedAttachments,
            messagesReadyToSend: messagesReadyToSend
        )
    }

    public class func sendTextAttachment(
        _ textAttachment: UnsentTextAttachment,
        to conversations: [ConversationItem]
    ) -> Promise<[TSThread]> {
        return TSAttachmentMultisend.sendTextAttachment(textAttachment, to: conversations)
    }

    public class func sendTextAttachmentFromShareExtension(
        _ textAttachment: UnsentTextAttachment,
        to conversations: [ConversationItem],
        messagesReadyToSend: @escaping ([PreparedOutgoingMessage]) -> Void
    ) -> Promise<[TSThread]> {
        return TSAttachmentMultisend.sendTextAttachmentFromShareExtension(
            textAttachment,
            to: conversations,
            messagesReadyToSend: messagesReadyToSend
        )
    }
}
