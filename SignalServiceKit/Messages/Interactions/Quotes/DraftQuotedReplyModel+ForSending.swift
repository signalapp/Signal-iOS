//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension DraftQuotedReplyModel {

    public struct ForSending {
        public let originalMessageTimestamp: UInt64?
        public let originalMessageAuthorAddress: SignalServiceAddress
        public let originalMessageIsGiftBadge: Bool
        public let originalMessageIsViewOnce: Bool
        public let threadUniqueId: String

        public let quoteBody: MessageBody?

        public enum Attachment {
            case stub(QuotedMessageAttachmentReference.Stub)
            case thumbnail(dataSource: QuotedReplyAttachmentDataSource)
        }
        public let attachment: Attachment?

        /// IFF this is a draft edit on a message that had a quoted reply, this is the TSQuotedMessage
        /// previously used on the version of the reply message prior to editing.
        /// NOTE: edits can only keep the existing quote or remove it; if this is present just reuse it.
        public let quotedMessageFromEdit: TSQuotedMessage?
    }
}
