//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension AttachmentStore {

    public func quotedAttachmentReference(
        from info: OWSAttachmentInfo,
        parentMessage: TSMessage,
        tx: DBReadTransaction
    ) -> QuotedMessageAttachmentReference? {
        guard let messageRowId = parentMessage.sqliteRowId else {
            owsFailDebug("Uninserted message!")
            return nil
        }

        let reference = self.fetchFirstReference(
            owner: .quotedReplyAttachment(messageRowId: messageRowId),
            tx: tx
        )

        if let reference {
            return .thumbnail(reference)
        } else if let stub = QuotedMessageAttachmentReference.Stub(info) {
            return .stub(stub)
        } else {
            return nil
        }
    }

    public func quotedAttachmentReference(
            for message: TSMessage,
            tx: DBReadTransaction
    ) -> QuotedMessageAttachmentReference? {
        guard let info = message.quotedMessage?.attachmentInfo() else {
            return nil
        }
        return quotedAttachmentReference(from: info, parentMessage: message, tx: tx)
    }

    public func quotedThumbnailAttachment(
        for message: TSMessage,
        tx: DBReadTransaction
    ) -> AttachmentReference? {
        let ref = self.quotedAttachmentReference(for: message, tx: tx)
        switch ref {
        case .thumbnail(let attachmentRef):
            return attachmentRef
        case .stub, nil:
            return nil
        }
    }

    public func attachmentToUseInQuote(
        originalMessage: TSMessage,
        tx: DBReadTransaction
    ) -> AttachmentReference? {
        guard let messageRowId = originalMessage.sqliteRowId else {
            owsFailDebug("Cloning attachment for un-inserted message")
            return nil
        }
        return self.orderedBodyAttachments(for: originalMessage, tx: tx).first
            ?? self.fetchFirstReference(owner: .messageLinkPreview(messageRowId: messageRowId), tx: tx)
            ?? self.fetchFirstReference(owner: .messageSticker(messageRowId: messageRowId), tx: tx)
    }
}
