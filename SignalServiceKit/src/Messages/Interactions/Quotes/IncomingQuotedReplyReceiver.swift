//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public protocol QuotedMessageAttachmentBuilder {

    /// Immediately available before inserting the message (and in fact is needed for message creation).
    var attachmentInfo: OWSAttachmentInfo { get }

    /// Finalize the quoted reply, potentially creating any attachments.
    /// Must be called after the parent TSMessage has been inserted,
    /// within the same write transaction.
    func finalize(
        newMessageRowId: Int64,
        tx: DBWriteTransaction
    )

    var hasBeenFinalized: Bool { get }
}

public class QuotedMessageBuilder {

    public let quotedMessage: TSQuotedMessage
    public let attachmentBuilder: QuotedMessageAttachmentBuilder?

    internal init(quotedMessage: TSQuotedMessage, attachmentBuilder: QuotedMessageAttachmentBuilder?) {
        self.quotedMessage = quotedMessage
        self.attachmentBuilder = attachmentBuilder
    }

    deinit {
        if let attachmentBuilder, attachmentBuilder.hasBeenFinalized.negated {
            owsFailDebug("Did not finalize attachments!")
        }
    }
}

public protocol IncomingQuotedReplyReceiver {

    func quotedMessage(
        for dataMessage: SSKProtoDataMessage,
        thread: TSThread,
        tx: DBWriteTransaction
    ) -> QuotedMessageBuilder?
}
