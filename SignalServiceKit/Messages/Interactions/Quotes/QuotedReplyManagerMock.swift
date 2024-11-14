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

    open func prepareDraftForSending(
        _ draft: DraftQuotedReplyModel
    ) throws -> DraftQuotedReplyModel.ForSending {
        return .init(
            originalMessageTimestamp: draft.originalMessageTimestamp,
            originalMessageAuthorAddress: draft.originalMessageAuthorAddress,
            originalMessageIsGiftBadge: draft.content.isGiftBadge,
            originalMessageIsViewOnce: draft.content.isViewOnce,
            threadUniqueId: draft.threadUniqueId,
            quoteBody: draft.bodyForSending,
            attachment: nil,
            quotedMessageFromEdit: nil
        )
    }

    open func buildQuotedReplyForSending(
        draft: DraftQuotedReplyModel.ForSending,
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
