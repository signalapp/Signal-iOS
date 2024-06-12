//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

#if TESTABLE_BUILD

open class QuotedReplyManagerMock: QuotedReplyManager {

    public init() {}

    open func quotedMessage(
        for dataMessage: SSKProtoDataMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<TSQuotedMessage>? {
        return nil
    }

    open func buildDraftQuotedReply(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> DraftQuotedReplyModel? {
        return nil
    }

    open func buildDraftQuotedReplyForEditing(
        quotedReplyMessage: TSMessage,
        quotedReply: TSQuotedMessage,
        originalMessage: TSMessage?,
        tx: DBReadTransaction
    ) -> DraftQuotedReplyModel {
        fatalError("Unimplemented!")
    }

    open func buildQuotedReplyForSending(
        draft: DraftQuotedReplyModel,
        tx: DBWriteTransaction
    ) -> OwnedAttachmentBuilder<TSQuotedMessage> {
        fatalError("Unimplemented!")
    }

    open func buildProtoForSending(
        _ quote: TSQuotedMessage,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) throws -> SSKProtoDataMessageQuote {
        fatalError("Unimplemented!")
    }
}

#endif
