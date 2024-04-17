//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public struct TSResourceMultisendResult {
    /// Resolved when the messages are prepared but before uploading/sending.
    public let preparedPromise: Promise<[PreparedOutgoingMessage]>
    /// Resolved when sending is durably enqueued but before uploading/sending.
    public let enqueuedPromise: Promise<[TSThread]>
    /// Resolved when the message is sent.
    public let sentPromise: Promise<[TSThread]>
}

public class TSResourceMultisend {

    private init() {}

    public class func sendApprovedMedia(
        conversations: [ConversationItem],
        approvalMessageBody: MessageBody?,
        approvedAttachments: [SignalAttachment]
    ) -> TSResourceMultisendResult {
        return TSAttachmentMultisend.sendApprovedMedia(
            conversations: conversations,
            approvalMessageBody: approvalMessageBody,
            approvedAttachments: approvedAttachments
        )
    }

    public class func sendTextAttachment(
        _ textAttachment: UnsentTextAttachment,
        to conversations: [ConversationItem]
    ) -> TSResourceMultisendResult {
        return TSAttachmentMultisend.sendTextAttachment(textAttachment, to: conversations)
    }
}
