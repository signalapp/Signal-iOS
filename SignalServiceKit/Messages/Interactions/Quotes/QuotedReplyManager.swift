//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol QuotedReplyManager {

    func quotedMessage(
        for dataMessage: SSKProtoDataMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<TSQuotedMessage>?

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

    func prepareDraftForSending(
        _ draft: DraftQuotedReplyModel
    ) throws -> DraftQuotedReplyModel.ForSending

    func buildQuotedReplyForSending(
        draft: DraftQuotedReplyModel.ForSending,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<TSQuotedMessage>

    func buildProtoForSending(
        _ quote: TSQuotedMessage,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoDataMessageQuote
}
