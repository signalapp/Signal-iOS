//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public struct QuotedMessageInfo {
    public let quotedMessage: TSQuotedMessage
    public let renderingFlag: AttachmentReference.RenderingFlag
}

public protocol QuotedReplyManager {

    func quotedMessage(
        for dataMessage: SSKProtoDataMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedMessageInfo>?

    func buildDraftQuotedReply(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> DraftQuotedReplyModel?

    func buildDraftQuotedReplyForEditing(
        quotedReplyMessage: TSMessage,
        quotedReply: TSQuotedMessage,
        originalMessage: TSMessage?,
        tx: DBReadTransaction
    ) -> DraftQuotedReplyModel

    func buildQuotedReplyForSending(
        draft: DraftQuotedReplyModel,
        threadUniqueId: String,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<QuotedMessageInfo>

    func buildProtoForSending(
        _ quote: TSQuotedMessage,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoDataMessageQuote
}
