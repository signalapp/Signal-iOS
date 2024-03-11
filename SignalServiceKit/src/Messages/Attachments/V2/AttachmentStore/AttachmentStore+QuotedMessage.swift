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
            return .thumbnail(QuotedMessageAttachmentReference.Thumbnail(
                attachmentRef: reference,
                mimeType: info.contentType,
                sourceFilename: info.sourceFilename
            ))
        } else if let stub = QuotedMessageAttachmentReference.Stub(info) {
            return .stub(stub)
        } else {
            return nil
        }
    }
}
