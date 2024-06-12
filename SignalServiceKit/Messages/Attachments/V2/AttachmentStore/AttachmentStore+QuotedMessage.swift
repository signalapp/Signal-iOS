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
        originalMessageRowId: Int64,
        tx: DBReadTransaction
    ) -> AttachmentReference? {
        return self.orderedBodyAttachments(forMessageRowId: originalMessageRowId, tx: tx).first
            ?? self.fetchFirstReference(owner: .messageLinkPreview(messageRowId: originalMessageRowId), tx: tx)
            ?? self.fetchFirstReference(owner: .messageSticker(messageRowId: originalMessageRowId), tx: tx)
    }
}
